// Customized by Platyun
#import "PLRequestCoordinator.h"

NSString *const PLRequestCoordinatorDidChangeNotification = @"PLRequestCoordinatorDidChangeNotification";
static NSString *const PLOneTapDefaultsKey = @"oneTapEnabled";

NSString *PLInterfaceCheckText(PLInterfaceCheck check) {
    switch (check) {
        case PLInterfaceCheckPending: return @"檢查中";
        case PLInterfaceCheckPassed: return @"通過";
        case PLInterfaceCheckMissingMethod: return @"方法不存在";
        case PLInterfaceCheckNoSignature: return @"無法取得簽章";
        case PLInterfaceCheckSignatureMismatch: return @"簽章不符";
        case PLInterfaceCheckException: return @"檢查發生例外";
    }
    return @"未知";
}

@implementation PLLogEntry
@end

@implementation PLProbeLog {
    NSMutableArray<PLLogEntry *> *_entries;
}

- (instancetype)init {
    if ((self = [super init])) _entries = [NSMutableArray array];
    return self;
}

- (NSArray<PLLogEntry *> *)entries { return [_entries copy]; }

- (void)append:(NSString *)message {
    NSAssert(NSThread.isMainThread, @"Log must be updated on the main thread");
    PLLogEntry *entry = [PLLogEntry new];
    entry.date = NSDate.date;
    entry.message = message;
    [_entries addObject:entry];
}

- (NSString *)shareText {
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    NSMutableString *text = [NSMutableString stringWithString:@"Customized by Platyun\n實驗性定位服務介面探測\n"];
    for (PLLogEntry *entry in _entries) {
        [text appendFormat:@"[%@] %@\n", [formatter stringFromDate:entry.date], entry.message];
    }
    return text;
}
@end

@implementation PLRequestOutcome
@end

@implementation PLWidgetSnapshot
@end

@implementation PLRequestCoordinator {
    id<PLProbeBackend> _backend;
    NSUserDefaults *_defaults;
    BOOL _started;
}

- (instancetype)initWithBackend:(id<PLProbeBackend>)backend gate:(PLRequestGate *)gate defaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _backend = backend;
        _gate = gate;
        _defaults = defaults ?: NSUserDefaults.standardUserDefaults;
        _log = [PLProbeLog new];
        _status = PLProbeStatusChecking;
        _interfaceCheck = PLInterfaceCheckPending;
        _returnTypeText = @"—";
        _lastRequestText = @"尚未送出";
    }
    return self;
}

- (BOOL)oneTapEnabled {
    return [_defaults boolForKey:PLOneTapDefaultsKey];
}

- (void)setOneTapEnabled:(BOOL)enabled {
    NSAssert(NSThread.isMainThread, @"main thread only");
    if (enabled == self.oneTapEnabled) return;
    [_defaults setBool:enabled forKey:PLOneTapDefaultsKey];
    [_log append:enabled ? @"使用者開啟「允許小工具一鍵送出」。" : @"使用者關閉「允許小工具一鍵送出」。"];
    [self publish];
}

- (void)setStatus:(PLProbeStatus)status {
    _status = status;
    [self publish];
}

- (void)republish {
    [self publish];
}

- (PLWidgetSnapshot *)snapshot {
    PLWidgetSnapshot *snapshot = [PLWidgetSnapshot new];
    snapshot.oneTapEnabled = self.oneTapEnabled;
    snapshot.lastResult = _lastRequestText;
    PLRequestGatePhase phase = _gate.phase;
    if (_status == PLProbeStatusChecking) snapshot.phase = @"checking";
    else if (_status == PLProbeStatusUnavailable) snapshot.phase = @"unavailable";
    else if (_status == PLProbeStatusNotSent) snapshot.phase = @"notsent";
    else if (phase == PLRequestGatePhaseUnavailable) snapshot.phase = @"unavailable";
    else if (phase == PLRequestGatePhaseInFlight) snapshot.phase = @"inflight";
    else if (phase == PLRequestGatePhaseCoolingDown) {
        snapshot.phase = @"cooldown";
        snapshot.cooldownEnd = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)_gate.remainingCooldownSeconds];
    } else snapshot.phase = @"ready";
    return snapshot;
}

- (void)publish {
    NSAssert(NSThread.isMainThread, @"main thread only");
    if (self.snapshotHandler) self.snapshotHandler([self snapshot]);
    [[NSNotificationCenter defaultCenter] postNotificationName:PLRequestCoordinatorDidChangeNotification object:self];
}

- (void)startWithSystemDescription:(NSString *)systemDescription {
    NSAssert(NSThread.isMainThread, @"main thread only");
    if (_started) return;
    _started = YES;
    [_log append:systemDescription];
    [_log append:@"未要求定位權限，未讀取座標，未自動送出停止請求。"];
    if (_previewMode) return;
    @try {
        NSString *reason = nil;
        NSString *returnType = nil;
        PLInterfaceCheck kind = PLInterfaceCheckPending;
        BOOL ok = [_backend checkInterfaceWithReason:&reason kind:&kind returnType:&returnType];
        _interfaceCheck = kind;
        if (!ok) {
            [_log append:reason ?: @"介面檢查未通過。"];
            self.status = PLProbeStatusUnavailable;
            return;
        }
        _returnTypeText = [returnType copy] ?: @"—";
        [_log append:reason ?: @"介面存在。尚未呼叫。"];
        [_log append:@"是否有權限、是否能重啟服務、是否清除任何快取：均未知。"];
        _interfaceAvailable = YES;
        self.status = PLProbeStatusReady;
    } @catch (NSException *exception) {
        _interfaceCheck = PLInterfaceCheckException;
        [_log append:[NSString stringWithFormat:@"檢查發生例外：%@；%@", exception.name, exception.reason ?: @"無說明"]];
        self.status = PLProbeStatusUnavailable;
    }
}

- (PLRequestResult)handleWidgetTap {
    NSAssert(NSThread.isMainThread, @"main thread only");
    if (!self.oneTapEnabled) {
        [_log append:@"小工具點擊：一鍵送出未開啟，只開啟 App，未送出請求。"];
        [self publish];
        return PLRequestResultRejectedOneTapOff;
    }
    return [self requestFromSource:PLRequestSourceWidget];
}

- (PLRequestResult)requestFromSource:(PLRequestSource)source {
    NSAssert(NSThread.isMainThread, @"main thread only");
    NSString *sourceText = source == PLRequestSourceWidget ? @"小工具" : @"App";
    if (_previewMode) return PLRequestResultRejectedPreview;
    if (!_interfaceAvailable) {
        [_log append:[NSString stringWithFormat:@"%@請求被拒：介面不可用。", sourceText]];
        [self publish];
        return PLRequestResultRejectedUnavailable;
    }
    if (![_gate tryBeginRequest]) {
        if (_gate.lastError.length) {
            [_log append:[NSString stringWithFormat:@"%@請求未送出：%@。", sourceText, _gate.lastError]];
            [self publish];
            return PLRequestResultRejectedUnavailable;
        }
        NSString *why = _gate.phase == PLRequestGatePhaseInFlight ? @"處理中" : [NSString stringWithFormat:@"冷卻中，剩 %ld 秒", (long)_gate.remainingCooldownSeconds];
        [_log append:[NSString stringWithFormat:@"%@請求被拒：%@。", sourceText, why]];
        [self publish];
        return PLRequestResultRejectedBusy;
    }
    [_log append:[NSString stringWithFormat:@"%@送出；送出前重新驗證介面，通過才呼叫一次 shutdownDaemon。若 App 被系統終止，本紀錄無法判定原因。", sourceText]];
    self.status = PLProbeStatusInFlight;

    id<PLProbeBackend> backend = _backend;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        PLRequestOutcome *outcome = [backend performRequest];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithOutcome:outcome];
        });
    });
    return PLRequestResultStarted;
}

- (void)finishWithOutcome:(PLRequestOutcome *)outcome {
    [_log append:outcome.message];
    if (outcome.invoked) {
        [_gate finishRequestStartingCooldown];
        if (_gate.lastError.length) [_log append:[NSString stringWithFormat:@"共用冷卻紀錄：%@。", _gate.lastError]];
        _lastRequestText = outcome.threw ? @"例外" : (outcome.returnedByte ? @"已返回 YES" : @"已返回 NO");
        [_log append:@"開始 10 秒冷卻，期滿後可再手動送出；不會自動重送。請以定位行為或裝置系統日誌驗證效果。"];
        self.status = outcome.threw ? PLProbeStatusFailed : PLProbeStatusReturned;
    } else {
        [_gate abortRequestWithoutCall];
        _interfaceAvailable = NO;
        _interfaceCheck = outcome.check;
        _lastRequestText = @"送出前檢查未通過";
        [_log append:@"介面檢查未通過，本次啟動停用送出按鈕。"];
        self.status = PLProbeStatusNotSent;
    }
}

#if DEBUG
- (void)applyPreviewState:(NSString *)state {
    _previewMode = YES;
    [_log append:@"［預覽模式］以下為示意資料，未檢查也未呼叫任何介面。"];
    _interfaceCheck = PLInterfaceCheckPassed;
    _returnTypeText = @"B（1 byte）";
    _interfaceAvailable = YES;
    if ([state isEqualToString:@"unavailable"]) {
        _interfaceAvailable = NO;
        _interfaceCheck = PLInterfaceCheckSignatureMismatch;
        _returnTypeText = @"—";
        self.status = PLProbeStatusUnavailable;
    } else if ([state isEqualToString:@"inflight"]) {
        [_gate tryBeginRequest];
        self.status = PLProbeStatusInFlight;
    } else if ([state isEqualToString:@"returned"] || [state isEqualToString:@"failed"] || [state isEqualToString:@"detail"]) {
        BOOL failed = [state isEqualToString:@"failed"];
        [_gate tryBeginRequest];
        [_gate finishRequestStartingCooldown];
        _lastRequestText = failed ? @"例外" : @"已返回 YES";
        [_log append:@"［預覽］使用者確認後送出。"];
        [_log append:failed ? @"［預覽］呼叫發生例外。" : @"［預覽］請求已返回：YES／非零（原始值 1）。"];
        self.status = failed ? PLProbeStatusFailed : PLProbeStatusReturned;
    } else if ([state isEqualToString:@"notsent"]) {
        _interfaceAvailable = NO;
        _interfaceCheck = PLInterfaceCheckMissingMethod;
        _lastRequestText = @"送出前檢查未通過";
        self.status = PLProbeStatusNotSent;
    } else {
        self.status = PLProbeStatusReady;
    }
}
#endif

@end
