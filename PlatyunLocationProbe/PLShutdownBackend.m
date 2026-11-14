// Customized by Platyun
#import "PLShutdownBackend.h"
#import <CoreLocation/CoreLocation.h>
#include <string.h>

@implementation PLShutdownBackend

- (NSMethodSignature *)validatedSignature:(NSString **)reason kind:(PLInterfaceCheck *)kind {
    Class managerClass = [CLLocationManager class];
    SEL selector = NSSelectorFromString(@"shutdownDaemon");
    if (![managerClass respondsToSelector:selector]) {
        if (reason) *reason = @"shutdownDaemon 類別方法不存在／無法回應，停止測試。";
        if (kind) *kind = PLInterfaceCheckMissingMethod;
        return nil;
    }
    NSMethodSignature *signature = [managerClass methodSignatureForSelector:selector];
    if (!signature) {
        if (reason) *reason = @"無法取得方法簽章，停止測試。";
        if (kind) *kind = PLInterfaceCheckNoSignature;
        return nil;
    }
    const char *type = signature.methodReturnType;
    while (*type && strchr("rnNoORV", *type)) type++;
    BOOL booleanReturn = (strcmp(type, "B") == 0 || strcmp(type, "c") == 0 || strcmp(type, "C") == 0);
    if (signature.numberOfArguments != 2 || signature.methodReturnLength != 1 || !booleanReturn) {
        if (reason) *reason = [NSString stringWithFormat:@"方法簽章與舊版記錄不符（參數數量 %lu，回傳型別 %s，大小 %lu），停止測試。", (unsigned long)signature.numberOfArguments, type, (unsigned long)signature.methodReturnLength];
        if (kind) *kind = PLInterfaceCheckSignatureMismatch;
        return nil;
    }
    if (kind) *kind = PLInterfaceCheckPassed;
    return signature;
}

- (BOOL)checkInterfaceWithReason:(NSString **)reason kind:(PLInterfaceCheck *)kind returnType:(NSString **)returnType {
    NSMethodSignature *signature = [self validatedSignature:reason kind:kind];
    if (!signature) return NO;
    if (reason) *reason = [NSString stringWithFormat:@"介面存在。回傳型別：%s；大小：%lu。尚未呼叫。", signature.methodReturnType, (unsigned long)signature.methodReturnLength];
    if (returnType) *returnType = [NSString stringWithFormat:@"%s（%lu byte）", signature.methodReturnType, (unsigned long)signature.methodReturnLength];
    return YES;
}

- (PLRequestOutcome *)performRequest {
    PLRequestOutcome *outcome = [PLRequestOutcome new];
    @autoreleasepool {
        NSString *result;
        BOOL invoked = NO;
        BOOL threw = NO;
        unsigned char returnedByte = 0;
        PLInterfaceCheck kind = PLInterfaceCheckPending;
        @try {
            NSString *reason = nil;
            NSMethodSignature *signature = [self validatedSignature:&reason kind:&kind];
            if (!signature) {
                result = [NSString stringWithFormat:@"送出前驗證未通過，未呼叫：%@", reason];
            } else {
                invoked = YES;
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                invocation.target = [CLLocationManager class];
                invocation.selector = NSSelectorFromString(@"shutdownDaemon");
                [invocation invoke];
                [invocation getReturnValue:&returnedByte];
                result = [NSString stringWithFormat:@"請求已返回：%@（原始值 %u）。這不是服務重啟或快取清除的證明。", returnedByte ? @"YES／非零" : @"NO／零", (unsigned int)returnedByte];
            }
        } @catch (NSException *exception) {
            threw = YES;
            if (!invoked) kind = PLInterfaceCheckException;
            result = [NSString stringWithFormat:@"呼叫發生例外：%@；%@", exception.name, exception.reason ?: @"無說明"];
        }
        outcome.invoked = invoked;
        outcome.threw = threw;
        outcome.returnedByte = returnedByte;
        outcome.check = kind;
        outcome.message = result;
    }
    return outcome;
}

@end
