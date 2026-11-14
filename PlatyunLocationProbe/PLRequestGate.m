// Customized by Platyun
#import "PLRequestGate.h"
#include <time.h>
#include <math.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/file.h>
#include <sys/sysctl.h>
#include <unistd.h>

typedef NS_ENUM(NSInteger, PLOwnerState) {
    PLOwnerStateAlive,
    PLOwnerStateExited,
    PLOwnerStateUnknown
};

static NSString *PLBootIdentifier(void) {
    struct timeval boot;
    size_t length = sizeof(boot);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &boot, &length, NULL, 0) != 0) return @"unknown";
    return [NSString stringWithFormat:@"%ld.%d", (long)boot.tv_sec, (int)boot.tv_usec];
}

NSString *PLRequestGateProcessIdentity(pid_t pid) {
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return nil;
    struct timeval start = info.kp_proc.p_un.__p_starttime;
    return [NSString stringWithFormat:@"%d@%ld.%d", (int)pid, (long)start.tv_sec, (int)start.tv_usec];
}

static PLOwnerState PLOwnerStateFor(pid_t pid, NSString *identity) {
    if (pid <= 0) return PLOwnerStateExited;
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &info, &size, NULL, 0) == 0) {
        if (size == 0) return PLOwnerStateExited;
        NSString *current = PLRequestGateProcessIdentity(pid);
        if (identity.length && current.length && ![identity isEqualToString:current]) return PLOwnerStateExited;
        return PLOwnerStateAlive;
    }
    if (kill(pid, 0) == 0) return PLOwnerStateAlive;
    if (errno == ESRCH) return PLOwnerStateExited;
    return PLOwnerStateUnknown;
}

@implementation PLRequestGate {
    PLMonotonicClock _clock;
    uint64_t _cooldownNanos;
    BOOL _inFlight;
    BOOL _hasDeadline;
    uint64_t _deadline;
    NSString *_storePath;
    NSString *_ownerToken;
    NSString *_lastError;
}

+ (PLMonotonicClock)systemMonotonicClock {
    return ^uint64_t(void) {
        return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    };
}

- (instancetype)initWithCooldown:(NSTimeInterval)cooldownSeconds clock:(PLMonotonicClock)clock {
    return [self initWithCooldown:cooldownSeconds clock:clock storePath:nil];
}

- (instancetype)initWithCooldown:(NSTimeInterval)cooldownSeconds clock:(PLMonotonicClock)clock storePath:(NSString *)storePath {
    if ((self = [super init])) {
        _clock = [clock ?: [PLRequestGate systemMonotonicClock] copy];
        _cooldownNanos = (uint64_t)llround(MAX(cooldownSeconds, 0) * (double)NSEC_PER_SEC);
        _storePath = [storePath copy];
    }
    return self;
}

- (BOOL)isShared {
    return _storePath != nil;
}

- (NSString *)lastError {
    return _lastError;
}

- (BOOL)withLock:(int)operation run:(void (^)(void))block {
    NSString *lockPath = [_storePath stringByAppendingString:@".lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0644);
    if (fd < 0) {
        _lastError = [NSString stringWithFormat:@"無法開啟共用冷卻鎖（%s）", strerror(errno)];
        return NO;
    }
    BOOL locked = NO;
    @try {
        if (flock(fd, operation) != 0) {
            _lastError = [NSString stringWithFormat:@"無法取得共用冷卻鎖（%s）", strerror(errno)];
            return NO;
        }
        locked = YES;
        block();
        return YES;
    } @finally {
        if (locked) flock(fd, LOCK_UN);
        close(fd);
    }
}

- (NSMutableDictionary *)loadRecord {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:_storePath];
    if (![stored isKindOfClass:NSDictionary.class] || ![stored[@"boot"] isEqual:PLBootIdentifier()]) {
        return [NSMutableDictionary dictionary];
    }
    return [stored mutableCopy];
}

- (BOOL)saveRecord:(NSMutableDictionary *)record {
    record[@"boot"] = PLBootIdentifier();
    if (![record writeToFile:_storePath atomically:YES]) {
        _lastError = @"無法寫入共用冷卻紀錄";
        return NO;
    }
    return YES;
}

- (BOOL)recordHasActiveOwner:(NSDictionary *)record {
    NSNumber *owner = record[@"ownerPid"];
    if (![owner isKindOfClass:NSNumber.class]) return NO;
    NSString *identity = [record[@"ownerIdentity"] isKindOfClass:NSString.class] ? record[@"ownerIdentity"] : nil;
    return PLOwnerStateFor((pid_t)owner.intValue, identity) != PLOwnerStateExited;
}

- (BOOL)recordOwnedByMe:(NSDictionary *)record {
    return _ownerToken.length && [record[@"ownerToken"] isEqual:_ownerToken];
}

- (uint64_t)recordDeadline:(NSDictionary *)record now:(uint64_t)now {
    NSNumber *deadline = record[@"deadline"];
    if (![deadline isKindOfClass:NSNumber.class]) return 0;
    uint64_t value = deadline.unsignedLongLongValue;
    if (value > now + _cooldownNanos + NSEC_PER_SEC) return 0;
    return value;
}

- (PLRequestGatePhase)phase {
    if (_inFlight) return PLRequestGatePhaseInFlight;
    if (!self.isShared) {
        if (_hasDeadline && _clock() < _deadline) return PLRequestGatePhaseCoolingDown;
        return PLRequestGatePhaseReady;
    }
    __block PLRequestGatePhase result = PLRequestGatePhaseReady;
    BOOL locked = [self withLock:LOCK_SH run:^{
        NSDictionary *record = [self loadRecord];
        uint64_t now = self->_clock();
        if ([self recordHasActiveOwner:record]) {
            result = PLRequestGatePhaseInFlight;
        } else if (now < [self recordDeadline:record now:now]) {
            result = PLRequestGatePhaseCoolingDown;
        }
    }];
    return locked ? result : PLRequestGatePhaseUnavailable;
}

- (NSInteger)remainingCooldownSeconds {
    if (_inFlight) return 0;
    __block uint64_t deadline = 0;
    __block uint64_t now = 0;
    __block BOOL busy = NO;
    if (!self.isShared) {
        if (!_hasDeadline) return 0;
        deadline = _deadline;
        now = _clock();
    } else {
        BOOL locked = [self withLock:LOCK_SH run:^{
            NSDictionary *record = [self loadRecord];
            now = self->_clock();
            busy = [self recordHasActiveOwner:record];
            deadline = [self recordDeadline:record now:now];
        }];
        if (!locked) return 0;
    }
    if (busy || now >= deadline) return 0;
    uint64_t left = deadline - now;
    return (NSInteger)((left + NSEC_PER_SEC - 1) / NSEC_PER_SEC);
}

- (BOOL)tryBeginRequest {
    if (_inFlight) return NO;
    if (!self.isShared) {
        if (self.phase != PLRequestGatePhaseReady) return NO;
        _inFlight = YES;
        return YES;
    }
    _lastError = nil;
    NSString *token = NSUUID.UUID.UUIDString;
    NSString *identity = PLRequestGateProcessIdentity(getpid());
    __block BOOL began = NO;
    BOOL locked = [self withLock:LOCK_EX run:^{
        NSMutableDictionary *record = [self loadRecord];
        uint64_t now = self->_clock();
        if ([self recordHasActiveOwner:record]) return;
        if (now < [self recordDeadline:record now:now]) return;
        record[@"ownerPid"] = @(getpid());
        record[@"ownerToken"] = token;
        if (identity) record[@"ownerIdentity"] = identity;
        record[@"ownerStartedAt"] = @(now);
        began = [self saveRecord:record];
    }];
    if (!locked || !began) return NO;
    _ownerToken = token;
    _inFlight = YES;
    return YES;
}

- (void)finishRequestStartingCooldown {
    if (!_inFlight) return;
    _inFlight = NO;
    uint64_t now = _clock();
    if (!self.isShared) {
        _deadline = now + _cooldownNanos;
        _hasDeadline = YES;
        return;
    }
    [self withLock:LOCK_EX run:^{
        NSMutableDictionary *record = [self loadRecord];
        if (![self recordOwnedByMe:record]) {
            self->_lastError = @"共用冷卻紀錄的擁有者已不是本次請求，未覆寫";
            return;
        }
        [record removeObjectsForKeys:@[@"ownerPid", @"ownerToken", @"ownerIdentity", @"ownerStartedAt"]];
        record[@"deadline"] = @(now + self->_cooldownNanos);
        [self saveRecord:record];
    }];
    _ownerToken = nil;
}

- (void)abortRequestWithoutCall {
    if (!_inFlight) return;
    _inFlight = NO;
    if (!self.isShared) return;
    [self withLock:LOCK_EX run:^{
        NSMutableDictionary *record = [self loadRecord];
        if (![self recordOwnedByMe:record]) {
            self->_lastError = @"共用冷卻紀錄的擁有者已不是本次請求，未覆寫";
            return;
        }
        [record removeObjectsForKeys:@[@"ownerPid", @"ownerToken", @"ownerIdentity", @"ownerStartedAt"]];
        [self saveRecord:record];
    }];
    _ownerToken = nil;
}

@end
