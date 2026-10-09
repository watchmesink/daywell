import DeviceActivity
import Foundation

final class ActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) { handle(activity) }
    override func intervalDidEnd(for activity: DeviceActivityName) { handle(activity) }
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        handle(activity, event: event)
    }

    private func handle(_ activity: DeviceActivityName, event: DeviceActivityEvent.Name? = nil) {
        do {
            try ProtectionEnvironment.coordinator().handleCallback(activity: activity.rawValue, event: event?.rawValue)
        } catch {
            // Never clear shields on a storage, scheduling, or authorization failure.
            ProtectionEnvironment.logger.error("Monitor callback failed: \(error.localizedDescription, privacy: .public)")
            if let repository = try? ProtectionEnvironment.repository() {
                try? repository.update { $0.lastError = error.localizedDescription }
            }
        }
    }
}
