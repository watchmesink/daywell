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

    static func selection(from data: BlockingSelection) -> FamilyActivitySelection? {
        let decoder = JSONDecoder()
        // Decode every kind before touching any shields; a partially decoded selection
        // must never silently remove a restriction.
        guard let applications = try? data.applications.map({ try decoder.decode(ApplicationToken.self, from: $0) }),
              let categories = try? data.categories.map({ try decoder.decode(ActivityCategoryToken.self, from: $0) }),
              let websites = try? data.webDomains.map({ try decoder.decode(WebDomainToken.self, from: $0) }) else { return nil }
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = Set(applications)
        selection.categoryTokens = Set(categories)
        selection.webDomainTokens = Set(websites)
        return selection
    }

    static func encodedSelection(_ selection: FamilyActivitySelection) throws -> BlockingSelection {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try BlockingSelection(
            applications: selection.applicationTokens.map { try encoder.encode($0) },
            categories: selection.categoryTokens.map { try encoder.encode($0) },
            webDomains: selection.webDomainTokens.map { try encoder.encode($0) })
    }

    enum EnvironmentError: LocalizedError {
        case appGroupUnavailable, invalidSelection
        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: return "Shared storage is unavailable. Check that the app and all extensions use the same App Group in Signing & Capabilities."
            case .invalidSelection: return "The selected apps, categories, or websites could not be read. Existing protection has been retained."
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
            guard let selection = ProtectionEnvironment.selection(from: data), !selection.isEmpty else {
                throw ProtectionEnvironment.EnvironmentError.invalidSelection
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: cycle.timeZoneIdentifier) ?? .current
            let components: Set<Calendar.Component> = [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second]
            schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(components, from: cycle.start),
                                              intervalEnd: calendar.dateComponents(components, from: cycle.end), repeats: false)
            events[.init(MonitorSpec.limitEvent)] = DeviceActivityEvent(
                applications: selection.applicationTokens, categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minutes), includesPastActivity: true)
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
        guard decision.isBlocked, !decision.selection.isEmpty else {
            setShields(nil, in: scheduleStore)
            setShields(nil, in: budgetStore)
            return
        }
        guard let selection = ProtectionEnvironment.selection(from: decision.selection), !selection.isEmpty else {
            ProtectionEnvironment.logger.error("Cannot decode selected tokens; retaining existing shields.")
            return
        }
        // Set every restrictive layer before clearing an inactive layer.
        if decision.scheduled { setShields(selection, in: scheduleStore) }
        if decision.budgetExhausted { setShields(selection, in: budgetStore) }
        if !decision.scheduled { setShields(nil, in: scheduleStore) }
        if !decision.budgetExhausted { setShields(nil, in: budgetStore) }
    }

    private func setShields(_ selection: FamilyActivitySelection?, in store: ManagedSettingsStore) {
        let apps = selection?.applicationTokens ?? []
        let categories = selection?.categoryTokens ?? []
        let websites = selection?.webDomainTokens ?? []
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = websites.isEmpty ? nil : websites
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
    }
}

extension FamilyActivitySelection {
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    func isSuperset(of other: FamilyActivitySelection) -> Bool {
        applicationTokens.isSuperset(of: other.applicationTokens)
            && categoryTokens.isSuperset(of: other.categoryTokens)
            && webDomainTokens.isSuperset(of: other.webDomainTokens)
    }
}
