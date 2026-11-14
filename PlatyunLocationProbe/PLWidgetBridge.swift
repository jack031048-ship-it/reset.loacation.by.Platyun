// Customized by Platyun
import Foundation
import WidgetKit

@objc(PLWidgetBridge)
final class PLWidgetBridge: NSObject {
    @objc static var sharedStateAvailable: Bool { PLShared.defaults != nil }

    @objc static var settingsDefaults: UserDefaults { PLShared.defaults ?? .standard }

    @objc static var gateStorePath: String? {
        PLShared.defaults == nil ? nil : PLShared.gateStorePath
    }

    @objc static var widgetLogLines: [String] {
        guard let d = PLShared.defaults else { return [] }
        return PLShared.widgetLog(from: d)
    }

    @objc static func publish(_ snapshot: PLWidgetSnapshot) {
        guard let d = PLShared.defaults else { return }
        PLShared.write(phase: snapshot.phase, cooldownEnd: snapshot.cooldownEnd, lastResult: snapshot.lastResult, to: d)
        WidgetCenter.shared.reloadTimelines(ofKind: PLShared.widgetKind)
    }
}
