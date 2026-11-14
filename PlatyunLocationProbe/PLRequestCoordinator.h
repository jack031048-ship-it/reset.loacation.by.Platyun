// Customized by Platyun
#import <Foundation/Foundation.h>
#import "PLRequestGate.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PLProbeStatus) {
    PLProbeStatusChecking,
    PLProbeStatusReady,
    PLProbeStatusUnavailable,
    PLProbeStatusInFlight,
    PLProbeStatusReturned,
    PLProbeStatusNotSent,
    PLProbeStatusFailed
};

typedef NS_ENUM(NSInteger, PLInterfaceCheck) {
    PLInterfaceCheckPending,
    PLInterfaceCheckPassed,
    PLInterfaceCheckMissingMethod,
    PLInterfaceCheckNoSignature,
    PLInterfaceCheckSignatureMismatch,
    PLInterfaceCheckException
};

typedef NS_ENUM(NSInteger, PLRequestSource) {
    PLRequestSourceApp,
    PLRequestSourceWidget
};

typedef NS_ENUM(NSInteger, PLRequestResult) {
    PLRequestResultStarted,
    PLRequestResultRejectedUnavailable,
    PLRequestResultRejectedBusy,
    PLRequestResultRejectedOneTapOff,
    PLRequestResultRejectedPreview
};

FOUNDATION_EXPORT NSString *PLInterfaceCheckText(PLInterfaceCheck check);
FOUNDATION_EXPORT NSString *const PLRequestCoordinatorDidChangeNotification;

@interface PLLogEntry : NSObject
@property(nonatomic, strong) NSDate *date;
@property(nonatomic, copy) NSString *message;
@end

@interface PLProbeLog : NSObject
@property(nonatomic, readonly) NSArray<PLLogEntry *> *entries;
- (void)append:(NSString *)message;
- (NSString *)shareText;
@end

@interface PLRequestOutcome : NSObject
@property(nonatomic) BOOL invoked;
@property(nonatomic) BOOL threw;
@property(nonatomic) unsigned char returnedByte;
@property(nonatomic) PLInterfaceCheck check;
@property(nonatomic, copy) NSString *message;
@end

@protocol PLProbeBackend <NSObject>
- (BOOL)checkInterfaceWithReason:(NSString *_Nullable *_Nullable)reason
                            kind:(PLInterfaceCheck *)kind
                      returnType:(NSString *_Nullable *_Nullable)returnType;
- (PLRequestOutcome *)performRequest;
@end

@interface PLWidgetSnapshot : NSObject
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, strong, nullable) NSDate *cooldownEnd;
@property(nonatomic, copy) NSString *lastResult;
@property(nonatomic) BOOL oneTapEnabled;
@end

@interface PLRequestCoordinator : NSObject

- (instancetype)initWithBackend:(id<PLProbeBackend>)backend
                           gate:(PLRequestGate *)gate
                       defaults:(nullable NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, readonly) PLProbeLog *log;
@property(nonatomic, readonly) PLRequestGate *gate;
@property(nonatomic, readonly) PLProbeStatus status;
@property(nonatomic, readonly) PLInterfaceCheck interfaceCheck;
@property(nonatomic, readonly) BOOL interfaceAvailable;
@property(nonatomic, readonly, copy) NSString *returnTypeText;
@property(nonatomic, readonly, copy) NSString *lastRequestText;
@property(nonatomic) BOOL oneTapEnabled;
@property(nonatomic) BOOL previewMode;

@property(nonatomic, copy, nullable) void (^snapshotHandler)(PLWidgetSnapshot *snapshot);

- (void)startWithSystemDescription:(NSString *)systemDescription;

- (PLRequestResult)requestFromSource:(PLRequestSource)source;

- (PLRequestResult)handleWidgetTap;

- (void)republish;

#if DEBUG
- (void)applyPreviewState:(NSString *)state;
#endif

@end

NS_ASSUME_NONNULL_END
