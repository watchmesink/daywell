import BlockingCore
import DeviceActivity
import Foundation

final class ActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) { handle(activity, kind: "interval_started") }
    override func intervalDidEnd(for activity: DeviceActivityName) { handle(activity, kind: "interval_ended") }
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        handle(activity, event: event, kind: "threshold_reached")
    }

    private func handle(_ activity: DeviceActivityName, event: DeviceActivityEvent.Name? = nil, kind: String) {
        do {
            try ProtectionEnvironment.coordinator().handleCallback(activity: activity.rawValue, event: event?.rawValue, kind: kind)
        } catch {
            // Never clear shields on a storage, scheduling, or authorization failure.
            ProtectionEnvironment.logger.error("Monitor callback failed: \(error.localizedDescription, privacy: .public)")
            var details = DiagnosticEvent.errorDetails(error)
            details["activity"] = activity.rawValue
            details["event"] = event?.rawValue ?? "none"
            details["kind"] = kind
            ProtectionEnvironment.record("callback.failed", details: details)
            if let repository = try? ProtectionEnvironment.repository() {
                try? repository.update { $0.lastError = error.localizedDescription }
            }
        }
    }
}
