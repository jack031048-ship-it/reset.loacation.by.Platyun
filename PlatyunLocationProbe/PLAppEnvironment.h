// Customized by Platyun
#import <Foundation/Foundation.h>
#import "PLRequestCoordinator.h"

NS_ASSUME_NONNULL_BEGIN

@interface PLAppEnvironment : NSObject
+ (PLRequestCoordinator *)coordinator;
+ (BOOL)sharedStateAvailable;
+ (NSArray<NSString *> *)widgetLogLines;
@end

NS_ASSUME_NONNULL_END
