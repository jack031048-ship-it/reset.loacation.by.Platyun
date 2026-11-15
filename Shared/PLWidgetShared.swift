// Customized by Platyun
import Foundation

enum PLShared {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "PLAppGroup") as? String ?? ""
    }
    static let widgetKind = "PlatyunLocationWidget"

    enum Key {
        static let phase = "widget.phase"
        static let cooldownEnd = "widget.cooldownEnd"
        static let lastResult = "widget.lastResult"
        static let updatedAt = "widget.updatedAt"
        static let oneTap = "oneTapEnabled"
    }

    static let cooldownSeconds: TimeInterval = 10
    static let widgetLogKey = "widget.log"
    static let widgetLogLimit = 50

    static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil else { return nil }
        return UserDefaults(suiteName: appGroup)
    }

    static var gateStorePath: String? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("request-gate.plist").path
    }

    static func write(phase: String, cooldownEnd: Date?, lastResult: String?, to d: UserDefaults, now: Date = Date()) {
        d.set(phase, forKey: Key.phase)
        if let end = cooldownEnd {
            d.set(end, forKey: Key.cooldownEnd)
        } else {
            d.removeObject(forKey: Key.cooldownEnd)
        }
        if let result = lastResult, !result.isEmpty, result != "尚未送出" {
            d.set(result, forKey: Key.lastResult)
        }
        d.set(now, forKey: Key.updatedAt)
    }

    static func appendWidgetLog(_ message: String, to d: UserDefaults, now: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: now)
        var lines = d.stringArray(forKey: widgetLogKey) ?? []
        lines.append("[\(stamp)] \(message)")
        if lines.count > widgetLogLimit {
            lines.removeFirst(lines.count - widgetLogLimit)
        }
        d.set(lines, forKey: widgetLogKey)
    }

    static func widgetLog(from d: UserDefaults) -> [String] {
        d.stringArray(forKey: widgetLogKey) ?? []
    }

    struct Snapshot {
        var groupAvailable: Bool
        var phase: String
        var cooldownEnd: Date?
        var lastResult: String
        var oneTap: Bool
        var updatedAt: Date?

        static let unavailable = Snapshot(groupAvailable: false, phase: "unknown", cooldownEnd: nil, lastResult: "", oneTap: false, updatedAt: nil)
    }

    enum Display: Equatable {
        case noGroup
        case ready(returned: Bool)
        case inFlight
        case staleInFlight
        case cooldown(end: Date)
        case unavailable
        case unknown
    }

    static let inFlightTimeout: TimeInterval = 60

    static func plan(_ s: Snapshot, now: Date) -> [(date: Date, display: Display)] {
        guard s.groupAvailable else { return [(now, .noGroup)] }
        let returned = !(s.lastResult.isEmpty || s.lastResult == "尚未送出")
        switch s.phase {
        case "ready":
            return [(now, .ready(returned: returned))]
        case "cooldown":
            guard let end = s.cooldownEnd else { return [(now, .unknown)] }
            if end <= now { return [(now, .ready(returned: returned))] }
            return [(now, .cooldown(end: end)), (end, .ready(returned: returned))]
        case "inflight":
            guard let updated = s.updatedAt else { return [(now, .staleInFlight)] }
            let deadline = updated.addingTimeInterval(inFlightTimeout)
            if deadline <= now { return [(now, .staleInFlight)] }
            return [(now, .inFlight), (deadline, .staleInFlight)]
        case "unavailable", "notsent":
            return [(now, .unavailable)]
        default:
            return [(now, .unknown)]
        }
    }

    static func showsSendButton(_ s: Snapshot, display: Display) -> Bool {
        guard s.groupAvailable, s.oneTap else { return false }
        if case .ready = display { return true }
        return false
    }

    static func read() -> Snapshot {
        guard let d = defaults else { return .unavailable }
        return Snapshot(
            groupAvailable: true,
            phase: d.string(forKey: Key.phase) ?? "unknown",
            cooldownEnd: d.object(forKey: Key.cooldownEnd) as? Date,
            lastResult: d.string(forKey: Key.lastResult) ?? "",
            oneTap: d.bool(forKey: Key.oneTap),
            updatedAt: d.object(forKey: Key.updatedAt) as? Date
        )
    }
}
