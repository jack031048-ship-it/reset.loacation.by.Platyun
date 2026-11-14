// Customized by Platyun
#import <Foundation/Foundation.h>
#import "PLRequestCoordinator.h"
#include <stdatomic.h>

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) { printf("PASS  %s\n", msg); } else { printf("FAIL  %s  (%s:%d)\n", msg, __FILE__, __LINE__); failures++; } } while (0)

typedef NS_ENUM(NSInteger, FakeMode) { FakeReturnYes, FakeReturnNo, FakeThrow, FakeValidationFails };

@interface FakeBackend : NSObject <PLProbeBackend>
@property(nonatomic) BOOL checkPasses;
@property(nonatomic) FakeMode mode;
@property(nonatomic, strong) dispatch_semaphore_t hold;
@end

@implementation FakeBackend {
    atomic_int _calls;
}
- (int)calls { return atomic_load(&_calls); }
- (BOOL)checkInterfaceWithReason:(NSString **)reason kind:(PLInterfaceCheck *)kind returnType:(NSString **)returnType {
    if (!self.checkPasses) {
        if (reason) *reason = @"假後端：方法不存在";
        if (kind) *kind = PLInterfaceCheckMissingMethod;
        return NO;
    }
    if (reason) *reason = @"假後端：介面存在";
    if (kind) *kind = PLInterfaceCheckPassed;
    if (returnType) *returnType = @"B（1 byte）";
    return YES;
}
- (PLRequestOutcome *)performRequest {
    PLRequestOutcome *o = [PLRequestOutcome new];
    if (self.mode == FakeValidationFails) {
        o.invoked = NO;
        o.check = PLInterfaceCheckSignatureMismatch;
        o.message = @"假後端：送出前驗證未通過，未呼叫";
        return o;
    }
    atomic_fetch_add(&_calls, 1);
    if (self.hold) dispatch_semaphore_wait(self.hold, DISPATCH_TIME_FOREVER);
    o.invoked = YES;
    o.check = PLInterfaceCheckPassed;
    o.threw = self.mode == FakeThrow;
    o.returnedByte = self.mode == FakeReturnYes ? 1 : 0;
    o.message = o.threw ? @"假後端：呼叫發生例外" : @"假後端：請求已返回";
    return o;
}
@end

static void spinUntil(BOOL (^cond)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!cond() && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

static const uint64_t S = NSEC_PER_SEC;

int main(void) {
    @autoreleasepool {
        NSString *suite = [NSString stringWithFormat:@"pl.coordinator.test.%@", NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];

        __block uint64_t now = 5000 * S;
        PLRequestGate *gate = [[PLRequestGate alloc] initWithCooldown:10 clock:^uint64_t { return now; }];
        FakeBackend *backend = [FakeBackend new];
        backend.checkPasses = YES;
        backend.mode = FakeReturnYes;
        PLRequestCoordinator *c = [[PLRequestCoordinator alloc] initWithBackend:backend gate:gate defaults:defaults];
        __block PLWidgetSnapshot *last = nil;
        __block int snapshots = 0;
        c.snapshotHandler = ^(PLWidgetSnapshot *s) { last = s; snapshots++; };

        [c startWithSystemDescription:@"測試"];
        CHECK(c.status == PLProbeStatusReady && c.interfaceAvailable, "啟動檢查通過 → 可以送出");
        CHECK([last.phase isEqualToString:@"ready"] && snapshots > 0, "小工具快照為 ready");
        CHECK(!c.oneTapEnabled && !last.oneTapEnabled, "一鍵送出預設關閉");

        CHECK([c handleWidgetTap] == PLRequestResultRejectedOneTapOff, "一鍵送出關閉 → 小工具點擊被拒");
        CHECK(backend.calls == 0, "一鍵送出關閉 → 假呼叫 0 次");

        c.oneTapEnabled = YES;
        CHECK([defaults boolForKey:@"oneTapEnabled"] && last.oneTapEnabled, "開啟設定寫入共用 defaults 並發布");
        backend.hold = dispatch_semaphore_create(0);
        CHECK([c handleWidgetTap] == PLRequestResultStarted, "小工具點擊 → 開始送出");
        spinUntil(^BOOL { return backend.calls == 1; });
        CHECK(c.status == PLProbeStatusInFlight && [last.phase isEqualToString:@"inflight"], "狀態為處理中，快照 inflight");
        CHECK([c requestFromSource:PLRequestSourceApp] == PLRequestResultRejectedBusy, "處理中 App 請求被拒");
        CHECK([c handleWidgetTap] == PLRequestResultRejectedBusy, "處理中小工具再點被拒");
        now += 3600 * S;
        CHECK([c requestFromSource:PLRequestSourceApp] == PLRequestResultRejectedBusy, "未返回時過 1 小時仍被拒");
        dispatch_semaphore_signal(backend.hold);
        backend.hold = nil;
        spinUntil(^BOOL { return c.status != PLProbeStatusInFlight; });
        CHECK(backend.calls == 1, "整段只真的呼叫 1 次");
        CHECK(c.status == PLProbeStatusReturned && [c.lastRequestText isEqualToString:@"已返回 YES"], "返回 YES → 請求已返回");

        CHECK([last.phase isEqualToString:@"cooldown"], "快照為 cooldown");
        NSTimeInterval left = [last.cooldownEnd timeIntervalSinceNow];
        CHECK(left > 8.5 && left <= 10.5, "快照倒數期限約為現在＋10 秒（僅供顯示）");
        now += 9 * S;
        CHECK([c requestFromSource:PLRequestSourceApp] == PLRequestResultRejectedBusy, "返回後 9 秒 App 請求被拒");
        CHECK([c handleWidgetTap] == PLRequestResultRejectedBusy, "返回後 9 秒小工具請求被拒");
        now += 1 * S;
        CHECK(c.gate.phase == PLRequestGatePhaseReady, "返回後 10 秒 gate 可送");

        int before = backend.calls;
        CHECK(backend.calls == before && c.gate.phase == PLRequestGatePhaseReady, "取消（未呼叫協調器）→ 不送、不冷卻");

        backend.mode = FakeThrow;
        CHECK([c requestFromSource:PLRequestSourceApp] == PLRequestResultStarted, "10 秒後 App 可再送");
        spinUntil(^BOOL { return c.status != PLProbeStatusInFlight; });
        CHECK(c.status == PLProbeStatusFailed && [c.lastRequestText isEqualToString:@"例外"], "例外 → 未能完成請求，不顯示 YES");
        CHECK(c.gate.phase == PLRequestGatePhaseCoolingDown, "例外後同樣進入冷卻");
        now += 10 * S;

        backend.mode = FakeValidationFails;
        before = backend.calls;
        CHECK([c requestFromSource:PLRequestSourceApp] == PLRequestResultStarted, "送出（將模擬驗證失敗）");
        spinUntil(^BOOL { return c.status != PLProbeStatusInFlight; });
        CHECK(c.status == PLProbeStatusNotSent && backend.calls == before, "驗證失敗 → 請求未送出，假呼叫次數不變");
        CHECK(c.gate.phase == PLRequestGatePhaseReady && !c.interfaceAvailable, "驗證失敗 → 不冷卻、介面停用");
        CHECK([c handleWidgetTap] == PLRequestResultRejectedUnavailable, "停用後小工具請求被拒");
        CHECK([last.phase isEqualToString:@"notsent"], "快照為 notsent");

        PLRequestGate *gate2 = [[PLRequestGate alloc] initWithCooldown:10 clock:^uint64_t { return now; }];
        FakeBackend *bad = [FakeBackend new];
        bad.checkPasses = NO;
        PLRequestCoordinator *c2 = [[PLRequestCoordinator alloc] initWithBackend:bad gate:gate2 defaults:defaults];
        [c2 startWithSystemDescription:@"測試"];
        CHECK(c2.status == PLProbeStatusUnavailable && c2.interfaceCheck == PLInterfaceCheckMissingMethod, "啟動檢查失敗 → 無法使用，原因保留");
        CHECK([c2 requestFromSource:PLRequestSourceApp] == PLRequestResultRejectedUnavailable && bad.calls == 0, "無法使用時請求被拒、未呼叫");

        PLRequestGate *gate3 = [[PLRequestGate alloc] initWithCooldown:10 clock:^uint64_t { return now; }];
        FakeBackend *pb = [FakeBackend new];
        pb.checkPasses = YES;
        PLRequestCoordinator *c3 = [[PLRequestCoordinator alloc] initWithBackend:pb gate:gate3 defaults:defaults];
        c3.previewMode = YES;
        [c3 startWithSystemDescription:@"測試"];
        CHECK([c3 requestFromSource:PLRequestSourceApp] == PLRequestResultRejectedPreview && pb.calls == 0, "預覽模式拒絕送出");

        c.oneTapEnabled = NO;
        CHECK([c handleWidgetTap] == PLRequestResultRejectedOneTapOff, "關閉一鍵送出 → 小工具點擊被拒");

        [defaults removePersistentDomainForName:suite];
    }
    printf(failures ? "\n%d FAILED\n" : "\nALL PASSED\n", failures);
    return failures ? 1 : 0;
}
