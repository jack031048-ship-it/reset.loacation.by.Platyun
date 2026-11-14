// Customized by Platyun
#import <UIKit/UIKit.h>
#import "PLAppEnvironment.h"

static NSString *const PLPrimaryTitle = @"重新套用定位";

@interface PLIntroHeaderView : UITableViewHeaderFooterView
@end

@implementation PLIntroHeaderView
- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithReuseIdentifier:reuseIdentifier])) {
        UILabel *purpose = [UILabel new];
        purpose.text = @"嘗試重新整理定位服務，協助原本的定位工具再次套用位置。";
        purpose.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        purpose.adjustsFontForContentSizeCategory = YES;
        purpose.textColor = UIColor.secondaryLabelColor;
        purpose.numberOfLines = 0;

        UILabel *experimental = [UILabel new];
        experimental.text = @"實驗功能，效果需回原定位工具確認。";
        experimental.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        experimental.adjustsFontForContentSizeCategory = YES;
        experimental.textColor = UIColor.secondaryLabelColor;
        experimental.numberOfLines = 0;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[purpose, experimental]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        NSLayoutConstraint *bottom = [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor];
        bottom.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            bottom
        ]];
    }
    return self;
}
@end

typedef NS_ENUM(NSInteger, PLDetailSection) { PLDetailSectionDevice, PLDetailSectionTimeline, PLDetailSectionWidget, PLDetailSectionCount };

@interface PLDetailViewController : UITableViewController
@end

@implementation PLDetailViewController {
    PLRequestCoordinator *_coordinator;
    NSDateFormatter *_timeFormatter;
    NSArray<NSString *> *_widgetLines;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _coordinator = [PLAppEnvironment coordinator];
        _timeFormatter = [NSDateFormatter new];
        _timeFormatter.dateFormat = @"HH:mm:ss";
        self.title = @"詳細紀錄";
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share:)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"分享紀錄";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    self.tableView.allowsSelection = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(coordinatorChanged:) name:PLRequestCoordinatorDidChangeNotification object:_coordinator];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)coordinatorChanged:(NSNotification *)note {
    _widgetLines = [PLAppEnvironment widgetLogLines];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _widgetLines = [PLAppEnvironment widgetLogLines];
    [self.tableView reloadData];
}

- (void)share:(UIBarButtonItem *)sender {
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[self shareText]] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:activity animated:YES completion:nil];
}

- (NSString *)shareText {
    NSString *base = [_coordinator.log shareText];
    NSArray<NSString *> *lines = [PLAppEnvironment widgetLogLines];
    if (lines.count == 0) return base;
    return [base stringByAppendingFormat:@"\n小工具紀錄\n%@\n", [lines componentsJoinedByString:@"\n"]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return PLDetailSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == PLDetailSectionDevice) return 5;
    if (section == PLDetailSectionWidget) return MAX((NSInteger)_widgetLines.count, 1);
    return (NSInteger)_coordinator.log.entries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == PLDetailSectionDevice) return @"這台裝置";
    if (section == PLDetailSectionWidget) return @"小工具紀錄";
    return @"時間軸";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != PLDetailSectionTimeline) return nil;
    return @"本 App 未要求定位權限，不讀取座標，也不會自動送出請求。回傳 YES 不代表服務已重新啟動或快取已清除。若 App 在送出後被系統關閉，本次結果無法記錄。冷卻記在 App 與小工具共用的檔案，強制結束 App 不會重置，手機重開機後才重置。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    if (indexPath.section == PLDetailSectionDevice) {
        UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
        UIDevice *device = UIDevice.currentDevice;
        switch (indexPath.row) {
            case 0: content.text = @"系統版本"; content.secondaryText = [NSString stringWithFormat:@"%@ %@", device.systemName, device.systemVersion]; break;
            case 1: content.text = @"裝置類別"; content.secondaryText = device.model; break;
            case 2: content.text = @"介面檢查"; content.secondaryText = PLInterfaceCheckText(_coordinator.interfaceCheck); break;
            case 3:
                content.text = @"回傳型別";
                content.secondaryText = _coordinator.returnTypeText;
                content.secondaryTextProperties.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular]];
                break;
            default: content.text = @"最近一次請求"; content.secondaryText = _coordinator.lastRequestText; break;
        }
        cell.contentConfiguration = content;
    } else if (indexPath.section == PLDetailSectionWidget) {
        UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
        content.text = _widgetLines.count ? _widgetLines[_widgetLines.count - 1 - (NSUInteger)indexPath.row] : @"尚無小工具紀錄";
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        content.textProperties.color = _widgetLines.count ? UIColor.labelColor : UIColor.secondaryLabelColor;
        cell.contentConfiguration = content;
    } else {
        PLLogEntry *entry = _coordinator.log.entries[(NSUInteger)indexPath.row];
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = entry.message;
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        content.secondaryText = [_timeFormatter stringFromDate:entry.date];
        content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        cell.contentConfiguration = content;
    }
    return cell;
}
@end

typedef NS_ENUM(NSInteger, PLHomeSection) { PLHomeSectionStatus, PLHomeSectionAction, PLHomeSectionDetail, PLHomeSectionWidget, PLHomeSectionCount };

@interface ProbeViewController : UITableViewController
@property(nonatomic, strong) PLRequestCoordinator *coordinator;
@property(nonatomic, strong) NSTimer *cooldownTimer;
@property(nonatomic, strong) UIButton *primaryButton;
@property(nonatomic, strong) UISwitch *oneTapSwitch;
@property(nonatomic) PLProbeStatus shownStatus;
@end

@implementation ProbeViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"定位服務";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationItem.backButtonTitle = @"定位服務";

    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"button"];
    [self.tableView registerClass:PLIntroHeaderView.class forHeaderFooterViewReuseIdentifier:@"intro"];
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 80;

    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.buttonSize = UIButtonConfigurationSizeLarge;
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.title = PLPrimaryTitle;
    config.titleLineBreakMode = NSLineBreakByWordWrapping;
    self.primaryButton = [UIButton buttonWithConfiguration:config primaryAction:nil];
    self.primaryButton.enabled = NO;
    self.primaryButton.accessibilityHint = @"送出一個定位服務請求，送出前會再確認";
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.primaryButton addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];

    self.oneTapSwitch = [UISwitch new];
    [self.oneTapSwitch addTarget:self action:@selector(oneTapSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    self.coordinator = [PLAppEnvironment coordinator];
    self.shownStatus = self.coordinator.status;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(coordinatorChanged:) name:PLRequestCoordinatorDidChangeNotification object:self.coordinator];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sceneWillEnterForeground:) name:UISceneWillEnterForegroundNotification object:nil];
    [self refreshButton];

#if DEBUG
    NSString *preview = [NSUserDefaults.standardUserDefaults stringForKey:@"PLPreviewState"];
    if ([preview isEqualToString:@"confirm"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self presentConfirmation];
        });
    } else if ([preview isEqualToString:@"detail"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController pushViewController:[PLDetailViewController new] animated:NO];
        });
    }
#endif
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_cooldownTimer invalidate];
}

- (void)coordinatorChanged:(NSNotification *)note {
    PLProbeStatus status = self.coordinator.status;
    BOOL changed = status != self.shownStatus;
    self.shownStatus = status;
    [self.tableView reloadData];
    [self refreshButton];
    if (changed) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [self statusTitle]);
}

- (void)sceneWillEnterForeground:(NSNotification *)note {
    [self.coordinator republish];
}

- (NSString *)statusTitle {
    switch (self.coordinator.status) {
        case PLProbeStatusChecking: return @"正在檢查…";
        case PLProbeStatusReady: return @"可以送出請求";
        case PLProbeStatusUnavailable: return @"目前無法使用此功能";
        case PLProbeStatusInFlight: return @"正在送出請求…";
        case PLProbeStatusReturned: return @"請求已返回";
        case PLProbeStatusNotSent: return @"請求未送出";
        case PLProbeStatusFailed: return @"未能完成請求";
    }
    return @"";
}

- (NSString *)statusSubtitle {
    switch (self.coordinator.status) {
        case PLProbeStatusUnavailable: return @"介面檢查未通過，請查看詳細紀錄。";
        case PLProbeStatusReturned: return @"請回到定位工具重新選擇位置，再確認是否套用。";
        case PLProbeStatusNotSent: return @"送出前的介面檢查未通過，請查看詳細紀錄。";
        case PLProbeStatusFailed: return @"請查看詳細紀錄。";
        default: return nil;
    }
}

- (NSString *)statusSymbol {
    switch (self.coordinator.status) {
        case PLProbeStatusChecking: return @"hourglass";
        case PLProbeStatusReady: return @"checkmark.circle";
        case PLProbeStatusUnavailable: return @"xmark.circle";
        case PLProbeStatusInFlight: return nil;
        case PLProbeStatusReturned: return @"arrow.uturn.backward.circle";
        case PLProbeStatusNotSent: return @"xmark.circle";
        case PLProbeStatusFailed: return @"exclamationmark.circle";
    }
    return nil;
}

- (UIColor *)statusColor {
    switch (self.coordinator.status) {
        case PLProbeStatusReady: return UIColor.systemGreenColor;
        case PLProbeStatusReturned: return UIColor.systemBlueColor;
        case PLProbeStatusFailed: return UIColor.systemOrangeColor;
        default: return UIColor.secondaryLabelColor;
    }
}

- (BOOL)showsActionSection {
    PLProbeStatus s = self.coordinator.status;
    return s != PLProbeStatusUnavailable && s != PLProbeStatusChecking;
}

- (void)refreshButton {
    NSAssert(NSThread.isMainThread, @"UI must update on the main thread");
    PLRequestCoordinator *c = self.coordinator;
    NSString *title = PLPrimaryTitle;
    BOOL enabled = NO;
    PLRequestGatePhase phase = c.gate.phase;
    if (c.status == PLProbeStatusNotSent || !c.interfaceAvailable) {
        title = c.status == PLProbeStatusNotSent ? @"本次無法送出" : PLPrimaryTitle;
        [self stopCooldownTimer];
    } else if (phase == PLRequestGatePhaseUnavailable) {
        title = @"冷卻紀錄無法使用";
        [self stopCooldownTimer];
    } else if (phase == PLRequestGatePhaseInFlight) {
        title = @"處理中…";
        [self stopCooldownTimer];
    } else if (phase == PLRequestGatePhaseCoolingDown) {
        title = [NSString stringWithFormat:@"請稍候 %ld 秒", (long)c.gate.remainingCooldownSeconds];
        [self startCooldownTimerIfNeeded];
    } else {
        enabled = YES;
        if (self.cooldownTimer) {
            [self stopCooldownTimer];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"可以再次重新套用定位");
            [c republish];
        }
    }
    UIButtonConfiguration *config = self.primaryButton.configuration;
    if (![config.title isEqualToString:title]) {
        config.title = title;
        self.primaryButton.configuration = config;
    }
    self.primaryButton.enabled = enabled;
}

- (void)startCooldownTimerIfNeeded {
    if (self.cooldownTimer.isValid) return;
    __weak typeof(self) weakSelf = self;
    self.cooldownTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { [timer invalidate]; return; }
        [strongSelf refreshButton];
    }];
}

- (void)stopCooldownTimer {
    [self.cooldownTimer invalidate];
    self.cooldownTimer = nil;
}

- (void)primaryTapped {
    if (self.coordinator.gate.phase != PLRequestGatePhaseReady || !self.coordinator.interfaceAvailable) {
        [self refreshButton];
        return;
    }
    [self presentConfirmation];
}

- (void)presentConfirmation {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"送出定位服務請求？"
                                                                   message:@"這會請求 iPhone 停止定位服務，系統可能會自行重新啟動它。實際效果仍需你回到定位工具確認。請求返回後需等 10 秒才能再送。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"送出請求" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf.coordinator requestFromSource:PLRequestSourceApp];
        [weakSelf refreshButton];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)oneTapSwitchChanged:(UISwitch *)sender {
    if (!sender.isOn) {
        self.coordinator.oneTapEnabled = NO;
        return;
    }
    [sender setOn:NO animated:NO];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"允許小工具一鍵送出？"
                                                                   message:@"開啟後，點主畫面小工具的「重新套用定位」會直接在背景送出一個定位服務請求，不開啟 App，也不再顯示確認框。請求返回後需等 10 秒才能再送，App 與小工具共用同一個冷卻。效果仍需回原定位工具確認。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"開啟" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        weakSelf.coordinator.oneTapEnabled = YES;
        [weakSelf.oneTapSwitch setOn:YES animated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return PLHomeSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == PLHomeSectionAction) return [self showsActionSection] ? 1 : 0;
    return 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != PLHomeSectionStatus) return nil;
    return [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"intro"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == PLHomeSectionStatus) return UITableViewAutomaticDimension;
    if (section == PLHomeSectionAction && ![self showsActionSection]) return CGFLOAT_MIN;
    return section == PLHomeSectionWidget ? UITableViewAutomaticDimension : 8;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == PLHomeSectionWidget ? @"主畫面小工具" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == PLHomeSectionAction && [self showsActionSection]) {
        return @"每次送出一個服務請求，返回後需等 10 秒才能再送。之後請回到原本的定位工具重新選擇位置。";
    }
    if (section == PLHomeSectionWidget) {
        NSString *base = @"預設關閉。關閉時點小工具只會開啟 App，不會送出請求。開啟後點小工具的按鈕會直接在背景送出，不開啟 App，同樣受 10 秒冷卻限制。結果記在「詳細紀錄 → 小工具紀錄」。";
        if (![PLAppEnvironment sharedStateAvailable]) {
            base = [base stringByAppendingString:@"\n目前無法與小工具共用狀態（App Group 未生效），小工具只會顯示「開啟 App」。"];
        }
        return [base stringByAppendingString:@"\n\nCustomized by Platyun"];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == PLHomeSectionAction) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"button" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
        if (self.primaryButton.superview != cell.contentView) {
            [self.primaryButton removeFromSuperview];
            [cell.contentView addSubview:self.primaryButton];
            [NSLayoutConstraint activateConstraints:@[
                [self.primaryButton.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
                [self.primaryButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
                [self.primaryButton.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [self.primaryButton.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [self.primaryButton.heightAnchor constraintGreaterThanOrEqualToConstant:50]
            ]];
        }
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.isAccessibilityElement = NO;
    cell.accessibilityLabel = nil;
    cell.accessibilityTraits = UIAccessibilityTraitNone;

    if (indexPath.section == PLHomeSectionStatus) {
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = [self statusTitle];
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        content.secondaryText = [self statusSubtitle];
        content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        NSString *symbol = [self statusSymbol];
        if (symbol) {
            content.image = [UIImage systemImageNamed:symbol];
            content.imageProperties.tintColor = [self statusColor];
        } else {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        }
        cell.contentConfiguration = content;
        cell.isAccessibilityElement = YES;
        NSString *subtitle = [self statusSubtitle];
        cell.accessibilityLabel = subtitle ? [NSString stringWithFormat:@"狀態，%@。%@", [self statusTitle], subtitle] : [NSString stringWithFormat:@"狀態，%@", [self statusTitle]];
        cell.accessibilityTraits = UIAccessibilityTraitStaticText;
    } else if (indexPath.section == PLHomeSectionWidget) {
        UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
        content.text = @"允許小工具一鍵送出";
        content.textProperties.numberOfLines = 0;
        cell.contentConfiguration = content;
        [self.oneTapSwitch setOn:self.coordinator.oneTapEnabled animated:NO];
        self.oneTapSwitch.accessibilityLabel = @"允許小工具一鍵送出";
        cell.accessoryView = self.oneTapSwitch;
    } else {
        UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
        content.text = @"詳細紀錄";
        cell.contentConfiguration = content;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PLHomeSectionDetail;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == PLHomeSectionDetail) {
        [self.navigationController pushViewController:[PLDetailViewController new] animated:YES];
    }
}

@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[ProbeViewController new]];
    navigation.navigationBar.prefersLargeTitles = YES;
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    configuration.delegateClass = SceneDelegate.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
