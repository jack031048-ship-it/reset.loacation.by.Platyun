// Customized by Platyun
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef uint64_t (^PLMonotonicClock)(void);

typedef NS_ENUM(NSInteger, PLRequestGatePhase) {
    PLRequestGatePhaseReady,
    PLRequestGatePhaseInFlight,
    PLRequestGatePhaseCoolingDown,
    PLRequestGatePhaseUnavailable
};

FOUNDATION_EXPORT NSString *_Nullable PLRequestGateProcessIdentity(pid_t pid);

@interface PLRequestGate : NSObject

- (instancetype)initWithCooldown:(NSTimeInterval)cooldownSeconds clock:(nullable PLMonotonicClock)clock;
- (instancetype)initWithCooldown:(NSTimeInterval)cooldownSeconds clock:(nullable PLMonotonicClock)clock storePath:(nullable NSString *)storePath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, readonly) BOOL isShared;
@property(nonatomic, readonly, copy, nullable) NSString *lastError;

+ (PLMonotonicClock)systemMonotonicClock;

@property(nonatomic, readonly) PLRequestGatePhase phase;

@property(nonatomic, readonly) NSInteger remainingCooldownSeconds;

- (BOOL)tryBeginRequest;

- (void)finishRequestStartingCooldown;

- (void)abortRequestWithoutCall;

@end

NS_ASSUME_NONNULL_END
