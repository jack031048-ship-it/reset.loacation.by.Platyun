// Customized by Platyun
#import <Foundation/Foundation.h>
#import "PLRequestGate.h"
#import "PLRequestCoordinator.h"
#import "PLWidgetSender.h"
#include <spawn.h>
#include <sys/wait.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>

extern char **environ;

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) { printf("PASS  %s\n", msg); } else { printf("FAIL  %s  (%s:%d)\n", msg, __FILE__, __LINE__); failures++; } } while (0)

static const uint64_t S = NSEC_PER_SEC;

typedef NS_ENUM(NSInteger, FakeMode) { FakeReturnYes, FakeThrow, FakeValidationFails };

@interface FakeBackend : NSObject <PLProbeBackend>
@property(nonatomic) FakeMode mode;
@property(nonatomic, copy) void (^probe)(void);
@end

@implementation FakeBackend {
    atomic_int _calls;
}
- (int)calls { return atomic_load(&_calls); }
- (BOOL)checkInterfaceWithReason:(NSString **)reason kind:(PLInterfaceCheck *)kind returnType:(NSString **)returnType {
    if (kind) *kind = PLInterfaceCheckPassed;
    return YES;
}
- (PLRequestOutcome *)performRequest {
    PLRequestOutcome *o = [PLRequestOutcome new];
    if (self.mode == FakeValidationFails) {
        o.invoked = NO;
        o.check = PLInterfaceCheckSignatureMismatch;
        o.message = @"假後端：驗證未通過";
        return o;
    }
    if (self.probe) self.probe();
    atomic_fetch_add(&_calls, 1);
    o.invoked = YES;
    o.threw = self.mode == FakeThrow;
    o.returnedByte = 1;
    o.message = o.threw ? @"假後端：例外" : @"假後端：已返回";
    return o;
}
@end

static NSString *selfPath(void) {
    char buffer[4096];
    uint32_t size = sizeof(buffer);
    _NSGetExecutablePath(buffer, &size);
    return [NSString stringWithUTF8String:buffer];
}

static pid_t spawnChild(NSString *mode, NSString *store) {
    pid_t pid = 0;
    const char *args[] = {selfPath().fileSystemRepresentation, mode.UTF8String, store.fileSystemRepresentation, NULL};
    posix_spawn(&pid, args[0], NULL, NULL, (char *const *)args, environ);
    return pid;
}

static int waitChild(pid_t pid) {
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "child-begin") == 0) {
            PLRequestGate *gate = [[PLRequestGate alloc] initWithCooldown:10 clock:nil storePath:[NSString stringWithUTF8String:argv[2]]];
            if (![gate tryBeginRequest]) return 1;
            usleep(500000);
            return 0;
        }
        if (argc == 3 && strcmp(argv[1], "child-exit") == 0) {
            return 0;
        }

        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pl-shared-gate-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *store = [dir stringByAppendingPathComponent:@"gate.plist"];

        __block uint64_t now = 1000 * S;
        PLMonotonicClock clock = ^uint64_t { return now; };
        PLRequestGate *app = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:store];
        PLRequestGate *widget = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:store];

        CHECK(app.isShared && widget.isShared, "兩個 gate 都使用共用紀錄");
        CHECK([widget tryBeginRequest], "小工具先開始請求");
        CHECK(app.phase == PLRequestGatePhaseInFlight, "App 看到處理中");
        CHECK(![app tryBeginRequest], "處理中 App 不能重入");
        now += 3600 * S;
        CHECK(![app tryBeginRequest], "同程序擁有者未返回時，過 1 小時仍不解鎖");
        [widget finishRequestStartingCooldown];
        CHECK(app.phase == PLRequestGatePhaseCoolingDown && app.remainingCooldownSeconds == 10, "小工具返回後 App 看到冷卻 10 秒");
        now += 9 * S;
        CHECK(![app tryBeginRequest] && ![widget tryBeginRequest], "返回後 9 秒兩邊都不能送");
        now += 1 * S;
        CHECK([app tryBeginRequest], "返回後 10 秒 App 可送");
        [app abortRequestWithoutCall];
        CHECK(widget.phase == PLRequestGatePhaseReady, "驗證失敗中止後不冷卻、解除處理中");

        pid_t dead = spawnChild(@"child-exit", store);
        waitChild(dead);
        NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"ownerPid"] = @(dead);
        record[@"ownerStartedAt"] = @(now);
        [record writeToFile:store atomically:YES];
        CHECK(app.phase == PLRequestGatePhaseReady && [app tryBeginRequest], "擁有者程序已結束：處理中自動失效");
        [app abortRequestWithoutCall];

        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"ownerPid"] = @(getppid());
        record[@"ownerIdentity"] = PLRequestGateProcessIdentity(getppid());
        record[@"ownerToken"] = @"foreign";
        record[@"ownerStartedAt"] = @(now);
        [record writeToFile:store atomically:YES];
        CHECK(![app tryBeginRequest], "其他存活程序處理中：不能送");
        now += 3600 * S;
        CHECK(app.phase == PLRequestGatePhaseInFlight && ![app tryBeginRequest], "其他存活程序處理中：過 1 小時（遠超 120 秒）仍被拒");

        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"ownerIdentity"] = [NSString stringWithFormat:@"%d@1.0", getppid()];
        [record writeToFile:store atomically:YES];
        CHECK(app.phase == PLRequestGatePhaseReady, "PID 被重用（啟動時間不同）：視為舊擁有者已結束");

        [NSFileManager.defaultManager removeItemAtPath:store error:nil];
        CHECK([widget tryBeginRequest], "所有權：小工具取得請求");
        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"ownerToken"] = @"newer-request";
        [record writeToFile:store atomically:YES];
        [widget finishRequestStartingCooldown];
        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        CHECK([record[@"ownerToken"] isEqual:@"newer-request"] && record[@"deadline"] == nil && widget.lastError.length > 0, "所有權：舊擁有者 finish 不覆寫新請求紀錄");
        record[@"ownerToken"] = @"newer-request";
        [record writeToFile:store atomically:YES];
        CHECK([app tryBeginRequest] == NO, "所有權：新請求仍被視為處理中");
        [NSFileManager.defaultManager removeItemAtPath:store error:nil];
        CHECK([widget tryBeginRequest], "所有權：小工具再取得請求");
        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"ownerToken"] = @"newer-request";
        [record writeToFile:store atomically:YES];
        [widget abortRequestWithoutCall];
        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        CHECK([record[@"ownerToken"] isEqual:@"newer-request"], "所有權：舊擁有者 abort 不清掉新請求紀錄");
        [NSFileManager.defaultManager removeItemAtPath:store error:nil];

        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"boot"] = @"other-boot";
        record[@"deadline"] = @(now + 5 * S);
        [record writeToFile:store atomically:YES];
        CHECK(app.phase == PLRequestGatePhaseReady, "開機識別不同（手機重開）：舊冷卻失效");

        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        [record removeObjectForKey:@"boot"];
        [record writeToFile:store atomically:YES];
        CHECK([app tryBeginRequest], "寫入目前開機識別");
        [app finishRequestStartingCooldown];
        record = [[NSDictionary dictionaryWithContentsOfFile:store] mutableCopy];
        record[@"deadline"] = @(now + 3600 * S);
        [record writeToFile:store atomically:YES];
        CHECK(app.phase == PLRequestGatePhaseReady, "期限異常（超過冷卻長度）時忽略");

        [NSFileManager.defaultManager removeItemAtPath:store error:nil];
        int children = 8;
        pid_t pids[8];
        for (int i = 0; i < children; i++) pids[i] = spawnChild(@"child-begin", store);
        int began = 0;
        for (int i = 0; i < children; i++) if (waitChild(pids[i]) == 0) began++;
        printf("      8 個程序同時搶：%d 個成功\n", began);
        CHECK(began == 1, "8 個獨立程序同時開始：只有 1 個成功（檔案鎖）");

        [NSFileManager.defaultManager removeItemAtPath:store error:nil];
        now = 5000 * S;
        FakeBackend *backend = [FakeBackend new];
        PLRequestGate *g = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:store];
        PLWidgetSendResult *r = [PLWidgetSender sendWithOneTapEnabled:NO gate:g backend:backend onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusOneTapOff && backend.calls == 0, "小工具：一鍵送出關閉不送");
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:g backend:backend onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusReturned && backend.calls == 1 && [r.lastResult isEqualToString:@"已返回 YES"], "小工具：開啟後點一次只呼叫一次");
        CHECK(r.cooldownSeconds == 10, "小工具：送出後回報冷卻 10 秒");
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:g backend:backend onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusBusy && backend.calls == 1 && !r.inFlight, "小工具：冷卻中再點被拒");
        CHECK(![app tryBeginRequest] || ([app abortRequestWithoutCall], NO), "小工具送出後 App 同樣在冷卻");
        now += 10 * S;
        backend.mode = FakeThrow;
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:g backend:backend onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusFailed && [r.lastResult isEqualToString:@"例外"], "小工具：例外不假裝成功");
        CHECK(r.cooldownSeconds == 10, "小工具：例外後仍冷卻");
        now += 10 * S;
        backend.mode = FakeValidationFails;
        int before = backend.calls;
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:g backend:backend onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusNotSent && backend.calls == before && r.cooldownSeconds == 0, "小工具：驗證失敗不呼叫、不冷卻");
        CHECK(g.phase == PLRequestGatePhaseReady, "小工具：驗證失敗後不卡處理中");

        NSString *missing = [dir stringByAppendingPathComponent:@"no-such-dir/gate.plist"];
        PLRequestGate *m1 = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:missing];
        PLRequestGate *m2 = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:missing];
        CHECK(![m1 tryBeginRequest] && ![m2 tryBeginRequest], "鎖檔無法開啟（父資料夾不存在）：兩個 gate 都拒絕");
        CHECK(m1.lastError.length > 0 && m1.phase == PLRequestGatePhaseUnavailable, "鎖檔無法開啟：回報錯誤且狀態為無法使用");
        FakeBackend *b2 = [FakeBackend new];
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:m1 backend:b2 onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusGateError && b2.calls == 0, "鎖檔無法開啟：小工具不呼叫假後端，回報錯誤");

        NSString *lockDir = [dir stringByAppendingPathComponent:@"lockdir/gate.plist"];
        [NSFileManager.defaultManager createDirectoryAtPath:[lockDir stringByAppendingString:@".lock"] withIntermediateDirectories:YES attributes:nil error:nil];
        PLRequestGate *m3 = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:lockDir];
        CHECK(![m3 tryBeginRequest] && m3.lastError.length > 0, "鎖路徑是資料夾（open 失敗）：拒絕並回報錯誤");

        NSString *dirAsStore = [dir stringByAppendingPathComponent:@"store-is-dir"];
        [NSFileManager.defaultManager createDirectoryAtPath:dirAsStore withIntermediateDirectories:YES attributes:nil error:nil];
        PLRequestGate *m4 = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:dirAsStore];
        FakeBackend *b4 = [FakeBackend new];
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:m4 backend:b4 onStarted:nil];
        CHECK(r.status == PLWidgetSendStatusGateError && b4.calls == 0 && m4.lastError.length > 0, "紀錄寫入失敗：拒絕送出、不呼叫假後端");

        [NSFileManager.defaultManager removeItemAtPath:store error:nil];
        now += 100 * S;
        PLRequestGate *pg = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:store];
        PLRequestGate *observer = [[PLRequestGate alloc] initWithCooldown:10 clock:clock storePath:store];
        FakeBackend *pb = [FakeBackend new];
        __block BOOL startedSeen = NO;
        __block PLRequestGatePhase phaseInside = PLRequestGatePhaseReady;
        pb.probe = ^{ phaseInside = observer.phase; };
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:pg backend:pb onStarted:^{ startedSeen = (pb.calls == 0); }];
        CHECK(startedSeen, "處理中發布：onStarted 在呼叫後端之前執行");
        CHECK(phaseInside == PLRequestGatePhaseInFlight, "處理中發布：後端執行期間，其他程序看到處理中");
        __block BOOL startedOnReject = NO;
        r = [PLWidgetSender sendWithOneTapEnabled:YES gate:pg backend:pb onStarted:^{ startedOnReject = YES; }];
        CHECK(r.status == PLWidgetSendStatusBusy && !startedOnReject, "處理中發布：gate 拒絕時不呼叫 onStarted");
        r = [PLWidgetSender sendWithOneTapEnabled:NO gate:pg backend:pb onStarted:^{ startedOnReject = YES; }];
        CHECK(!startedOnReject, "處理中發布：一鍵送出關閉時不呼叫 onStarted");

        [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    }
    printf(failures ? "\n%d FAILED\n" : "\nALL PASSED\n", failures);
    return failures ? 1 : 0;
}
