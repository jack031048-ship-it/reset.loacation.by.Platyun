// Customized by Platyun
#import <Foundation/Foundation.h>
#import "PLRequestGate.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) { printf("PASS  %s\n", msg); } else { printf("FAIL  %s  (%s:%d)\n", msg, __FILE__, __LINE__); failures++; } } while (0)

static const uint64_t S = NSEC_PER_SEC;

int main(void) {
    @autoreleasepool {
        __block uint64_t now = 1000 * S;
        PLRequestGate *gate = [[PLRequestGate alloc] initWithCooldown:10 clock:^uint64_t { return now; }];
        __block int fakeCalls = 0;
        BOOL (^press)(void) = ^BOOL {
            if (![gate tryBeginRequest]) return NO;
            fakeCalls++;
            return YES;
        };

        CHECK(gate.phase == PLRequestGatePhaseReady, "初始可送出");

        CHECK(gate.phase == PLRequestGatePhaseReady && gate.remainingCooldownSeconds == 0, "取消（未開始）不改變狀態、不產生冷卻");

        CHECK(press(), "第一次按下成功進入處理中");
        CHECK(gate.phase == PLRequestGatePhaseInFlight, "狀態為處理中");
        CHECK(!press() && !press() && fakeCalls == 1, "處理中連按不重入，假呼叫只發生一次");

        now += 3600 * S;
        CHECK(gate.phase == PLRequestGatePhaseInFlight && !press(), "未返回時即使過 1 小時也不解鎖");

        [gate finishRequestStartingCooldown];
        CHECK(gate.phase == PLRequestGatePhaseCoolingDown, "返回後進入冷卻");
        CHECK(gate.remainingCooldownSeconds == 10, "剛返回剩 10 秒");

        now += 9 * S;
        CHECK(gate.phase == PLRequestGatePhaseCoolingDown && !press(), "返回後 9 秒不可送");
        CHECK(gate.remainingCooldownSeconds == 1, "9 秒時顯示剩 1 秒");

        now += S / 2;
        CHECK(gate.remainingCooldownSeconds == 1, "9.5 秒時無條件進位仍顯示 1 秒");

        now += S / 2;
        CHECK(gate.phase == PLRequestGatePhaseReady, "返回後 10 秒可送");
        CHECK(press() && fakeCalls == 2, "10 秒後可再送出第二次");

        [gate finishRequestStartingCooldown];
        now += 3 * S;
        CHECK(gate.remainingCooldownSeconds == 7, "背景 3 秒回前景，剩 7 秒（依期限重算）");
        now += 120 * S;
        CHECK(gate.phase == PLRequestGatePhaseReady && gate.remainingCooldownSeconds == 0, "背景超過期限回前景即可送");

        CHECK([gate tryBeginRequest], "開始一次請求（將模擬驗證失敗）");
        [gate abortRequestWithoutCall];
        CHECK(gate.phase == PLRequestGatePhaseReady && gate.remainingCooldownSeconds == 0, "驗證失敗後離開處理中，且未開始冷卻");

        [gate finishRequestStartingCooldown];
        CHECK(gate.phase == PLRequestGatePhaseReady, "非處理中的 finish 被忽略");

        PLMonotonicClock sys = [PLRequestGate systemMonotonicClock];
        uint64_t a = sys(), b = sys();
        CHECK(b >= a, "系統單調時鐘不倒退");
    }
    printf(failures ? "\n%d FAILED\n" : "\nALL PASSED\n", failures);
    return failures ? 1 : 0;
}
