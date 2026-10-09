import BlockingCore
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog

enum ProtectionEnvironment {
    static let logger = Logger(subsystem: "Daywell", category: "Protection")

    static func repository() throws -> StateRepository {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "DaywellAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw EnvironmentError.appGroupUnavailable
        }
        return try StateRepository(directory: container.appendingPathComponent("Protection", isDirectory: true))
    }

    static func coordinator() throws -> ProtectionCoordinator {
        ProtectionCoordinator(repository: try repository(), driver: ScreenTimeDriver())
    }

    static func applications(from data: [Data]) -> [ApplicationToken]? {
        let decoder = JSONDecoder()
        return try? data.map { try decoder.decode(ApplicationToken.self, from: $0) }
    }

    enum EnvironmentError: LocalizedError {
        case appGroupUnavailable, invalidApplications
        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: return "Shared storage is unavailable. Check that the app and all extensions use the same App Group in Signing & Capabilities."
            case .invalidApplications: return "The selected apps could not be read. Existing protection has been retained."
            }
        }
    }
}

final class ScreenTimeDriver: ProtectionDriver {
    private let center = DeviceActivityCenter()
    private let scheduleStore = ManagedSettingsStore(named: .init("instablock.schedule"))
    private let budgetStore = ManagedSettingsStore(named: .init("instablock.budget"))

    var registeredNames: Set<String> { Set(center.activities.map(\.rawValue)) }

    func install(_ monitor: MonitorSpec) throws {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let schedule: DeviceActivitySchedule
        switch monitor.kind {
        case .midnight(let zone):
            schedule = DeviceActivitySchedule(intervalStart: wallTime(0, zone: zone),
                                              intervalEnd: wallTime(0, zone: zone), repeats: true)
        case .window(let window, let zone):
            schedule = DeviceActivitySchedule(
                intervalStart: wallTime(window.startMinute, zone: zone),
                intervalEnd: wallTime(window.endMinute, zone: zone), repeats: true)
        case .budget(let cycle, let data, let minutes):
            guard let tokens = ProtectionEnvironment.applications(from: data), !tokens.isEmpty else {
                throw ProtectionEnvironment.EnvironmentError.invalidApplications
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: cycle.timeZoneIdentifier) ?? .current
            let components: Set<Calendar.Component> = [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second]
            schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(components, from: cycle.start),
                                              intervalEnd: calendar.dateComponents(components, from: cycle.end), repeats: false)
            events[.init(MonitorSpec.limitEvent)] = DeviceActivityEvent(
                applications: Set(tokens), threshold: DateComponents(minute: minutes), includesPastActivity: true)
        }
        try center.startMonitoring(.init(monitor.name), during: schedule, events: events)
    }

    private func wallTime(_ minute: Int, zone: String) -> DateComponents {
        DateComponents(timeZone: TimeZone(identifier: zone), hour: minute / 60, minute: minute % 60)
    }

    func remove(names: Set<String>) {
        // stopMonitoring([]) means stop EVERYTHING in Apple's API.
        guard !names.isEmpty else { return }
        center.stopMonitoring(names.map { .init($0) })
    }

    func apply(_ decision: ShieldDecision) {
        // Clearing restrictions must also work if a saved token is no longer readable.
        if !decision.isBlocked {
            scheduleStore.shield.applications = nil
            budgetStore.shield.applications = nil
            return
        }
        if !decision.applications.isEmpty {
            guard let tokens = ProtectionEnvironment.applications(from: decision.applications), !tokens.isEmpty else {
                ProtectionEnvironment.logger.error("Cannot decode selected tokens; retaining existing shields.")
                return
            }
            let selection = Set(tokens)
            // Set the restrictive layer first, avoiding a gap during transitions.
            if decision.scheduled { scheduleStore.shield.applications = selection }
            if decision.budgetExhausted { budgetStore.shield.applications = selection }
            if !decision.scheduled { scheduleStore.shield.applications = nil }
            if !decision.budgetExhausted { budgetStore.shield.applications = nil }
        } else {
            scheduleStore.shield.applications = nil
            budgetStore.shield.applications = nil
        }
    }
}
