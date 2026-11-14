// Customized by Platyun
#import "PLWidgetSender.h"

@implementation PLWidgetSendResult
@end

@implementation PLWidgetSender

+ (PLWidgetSendResult *)sendWithOneTapEnabled:(BOOL)oneTapEnabled gate:(PLRequestGate *)gate backend:(id<PLProbeBackend>)backend onStarted:(void (^)(void))onStarted {
    PLWidgetSendResult *result = [PLWidgetSendResult new];
    result.lastResult = @"";
    if (!oneTapEnabled) {
        result.status = PLWidgetSendStatusOneTapOff;
        result.message = @"小工具點擊：一鍵送出未開啟，未送出請求。";
        return result;
    }
    if (![gate tryBeginRequest]) {
        if (gate.lastError.length) {
            result.status = PLWidgetSendStatusGateError;
            result.message = [NSString stringWithFormat:@"小工具請求未送出：%@。", gate.lastError];
            return result;
        }
        PLRequestGatePhase phase = gate.phase;
        if (phase == PLRequestGatePhaseUnavailable) {
            result.status = PLWidgetSendStatusGateError;
            result.message = [NSString stringWithFormat:@"小工具請求未送出：%@。", gate.lastError ?: @"共用冷卻紀錄無法使用"];
            return result;
        }
        result.status = PLWidgetSendStatusBusy;
        result.inFlight = phase == PLRequestGatePhaseInFlight;
        result.cooldownSeconds = gate.remainingCooldownSeconds;
        result.message = result.inFlight
            ? @"小工具請求被拒：處理中。"
            : [NSString stringWithFormat:@"小工具請求被拒：冷卻中，剩 %ld 秒。", (long)result.cooldownSeconds];
        return result;
    }
    if (onStarted) onStarted();
    PLRequestOutcome *outcome = [backend performRequest];
    if (outcome.invoked) {
        [gate finishRequestStartingCooldown];
        result.status = outcome.threw ? PLWidgetSendStatusFailed : PLWidgetSendStatusReturned;
        result.lastResult = outcome.threw ? @"例外" : (outcome.returnedByte ? @"已返回 YES" : @"已返回 NO");
    } else {
        [gate abortRequestWithoutCall];
        result.status = PLWidgetSendStatusNotSent;
        result.lastResult = @"送出前檢查未通過";
    }
    result.cooldownSeconds = gate.remainingCooldownSeconds;
    NSString *gateNote = gate.lastError.length ? [NSString stringWithFormat:@"（%@）", gate.lastError] : @"";
    result.message = [NSString stringWithFormat:@"小工具背景送出：%@%@", outcome.message ?: @"無結果", gateNote];
    return result;
}

@end
