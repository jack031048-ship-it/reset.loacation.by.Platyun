// Customized by Platyun
import Foundation

enum PLWidgetRequest {
    static func run() {
        guard let d = PLShared.defaults, let path = PLShared.gateStorePath else { return }
        let gate = PLRequestGate(cooldown: PLShared.cooldownSeconds, clock: nil, storePath: path)
        let result = PLWidgetSender.send(
            withOneTapEnabled: d.bool(forKey: PLShared.Key.oneTap),
            gate: gate,
            backend: PLShutdownBackend(),
            onStarted: {
                PLShared.write(phase: "inflight", cooldownEnd: nil, lastResult: nil, to: d)
            }
        )
        PLShared.appendWidgetLog(result.message, to: d)
        let now = Date()
        let end = result.cooldownSeconds > 0 ? now.addingTimeInterval(TimeInterval(result.cooldownSeconds)) : nil
        switch result.status {
        case .oneTapOff:
            break
        case .busy:
            if !result.inFlight {
                PLShared.write(phase: end == nil ? "ready" : "cooldown", cooldownEnd: end, lastResult: nil, to: d, now: now)
            }
        case .gateError:
            PLShared.write(phase: "unknown", cooldownEnd: nil, lastResult: nil, to: d, now: now)
        case .notSent:
            PLShared.write(phase: "notsent", cooldownEnd: nil, lastResult: result.lastResult, to: d, now: now)
        case .returned, .failed:
            PLShared.write(phase: end == nil ? "ready" : "cooldown", cooldownEnd: end, lastResult: result.lastResult, to: d, now: now)
        @unknown default:
            break
        }
    }
}
