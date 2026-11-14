// Customized by Platyun
#import <UIKit/UIKit.h>
#import "PLAppEnvironment.h"
#import "PLShutdownBackend.h"
#import "PlatyunLocationProbe-Swift.h"

static const NSTimeInterval PLRequestCooldownSeconds = 10;

@implementation PLAppEnvironment

+ (PLRequestCoordinator *)coordinator {
    NSAssert(NSThread.isMainThread, @"main thread only");
    static PLRequestCoordinator *coordinator;
    if (coordinator) return coordinator;

    NSString *preview = nil;
#if DEBUG
    preview = [NSUserDefaults.standardUserDefaults stringForKey:@"PLPreviewState"];
#endif
    NSString *storePath = preview.length ? nil : PLWidgetBridge.gateStorePath;
    PLRequestGate *gate = [[PLRequestGate alloc] initWithCooldown:PLRequestCooldownSeconds clock:nil storePath:storePath];
    coordinator = [[PLRequestCoordinator alloc] initWithBackend:[PLShutdownBackend new]
                                                           gate:gate
                                                       defaults:PLWidgetBridge.settingsDefaults];
    coordinator.snapshotHandler = ^(PLWidgetSnapshot *snapshot) {
        [PLWidgetBridge publish:snapshot];
    };
    UIDevice *device = UIDevice.currentDevice;
    NSString *system = [NSString stringWithFormat:@"系統：%@ %@；裝置類別：%@", device.systemName, device.systemVersion, device.model];

#if DEBUG
    if (preview.length) {
        coordinator.previewMode = YES;
        [coordinator startWithSystemDescription:system];
        [coordinator applyPreviewState:preview];
        return coordinator;
    }
#endif
    [coordinator startWithSystemDescription:system];
    return coordinator;
}

+ (BOOL)sharedStateAvailable {
    return PLWidgetBridge.sharedStateAvailable;
}

+ (NSArray<NSString *> *)widgetLogLines {
    return PLWidgetBridge.widgetLogLines;
}

@end
