// Customized by Platyun
#import <Foundation/Foundation.h>
#import "PLRequestGate.h"
#import "PLRequestCoordinator.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PLWidgetSendStatus) {
    PLWidgetSendStatusOneTapOff,
    PLWidgetSendStatusBusy,
    PLWidgetSendStatusGateError,
    PLWidgetSendStatusNotSent,
    PLWidgetSendStatusReturned,
    PLWidgetSendStatusFailed
};

@interface PLWidgetSendResult : NSObject
@property(nonatomic) PLWidgetSendStatus status;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *lastResult;
@property(nonatomic) NSInteger cooldownSeconds;
@property(nonatomic) BOOL inFlight;
@end

@interface PLWidgetSender : NSObject
+ (PLWidgetSendResult *)sendWithOneTapEnabled:(BOOL)oneTapEnabled
                                         gate:(PLRequestGate *)gate
                                      backend:(id<PLProbeBackend>)backend
                                    onStarted:(nullable void (^)(void))onStarted;
@end

NS_ASSUME_NONNULL_END
