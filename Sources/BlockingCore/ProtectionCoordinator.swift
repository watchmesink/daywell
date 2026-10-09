import Foundation

public protocol ProtectionDriver {
    var registeredNames: Set<String> { get }
    func install(_ monitor: MonitorSpec) throws
    func remove(names: Set<String>)
    func apply(_ decision: ShieldDecision)
}

/// Shared by the app and monitor extension; all mutations pass through the same guards.
public final class ProtectionCoordinator {
    private let repository: StateRepository
    private let driver: ProtectionDriver
    private let clock: () -> Date
    private let calendar: () -> Calendar

    public init(repository: StateRepository, driver: ProtectionDriver,
                clock: @escaping () -> Date = Date.init,
                calendar: @escaping () -> Calendar = { .autoupdatingCurrent }) {
        self.repository = repository
        self.driver = driver
        self.clock = clock
        self.calendar = calendar
    }

    public func reconcile() throws { try update(edit: nil) }
    public func execute(_ edit: RuleEdit) throws { try update(edit: edit) }

    public func handleCallback(activity: String, event: String? = nil) throws {
        let now = clock()
        try repository.update({ document in
            document.lastCallbackAt = now
            if let event {
                document.active.receiveThreshold(activity: activity, event: event, at: now)
                document.staged?.receiveThreshold(activity: activity, event: event, at: now)
            }
        }, afterSave: { self.apply($0.active, at: now) })
        do { try reconcile() } catch RuleError.busy {
            // The installer will merge any threshold delivered during registration.
        }
    }

    private func apply(_ snapshot: ProtectionSnapshot, at now: Date) {
        driver.apply(snapshot.decision(at: now, calendar: calendar()))
    }

    private func update(edit: RuleEdit?) throws {
        try repository.withOperationLock {
            // Recover a process interrupted between registration and commit. The previous
            // active configuration remains authoritative until every new monitor succeeds.
            let saved = try repository.read()
            if let orphan = saved.staged {
                let activeNames = Set(MonitorSpec.plan(for: saved.active).map(\.name))
                driver.remove(names: Set(MonitorSpec.plan(for: orphan).map(\.name)).subtracting(activeNames))
                try repository.update { $0.staged = nil }
            }
            let now = clock()
            let old = try repository.read().active
            var proposed = old
            proposed.advance(to: now, calendar: calendar())
            if let edit { try proposed.apply(edit, at: now, calendar: calendar()) }
            try proposed.policy.validate()
            let oldPlan = MonitorSpec.plan(for: old)
            let prospectivePlan = MonitorSpec.plan(for: proposed)
            let expectedNames = Set(prospectivePlan.map(\.name))

            if oldPlan == prospectivePlan && expectedNames.isSubset(of: driver.registeredNames) {
                try repository.update({ document in
                    // A threshold may have arrived while the operation was being prepared.
                    proposed.reachedCycles.formUnion(document.active.reachedCycles.intersection(Set(proposed.cycles.map(\.id))))
                    document.active = proposed
                    document.lastError = nil
                }, afterSave: { self.apply($0.active, at: self.clock()) })
                cleanup(keeping: expectedNames)
                return
            }

            proposed.generation = UUID()
            let newPlan = MonitorSpec.plan(for: proposed)
            let newNames = Set(newPlan.map(\.name))
            let existingNames = driver.registeredNames
            try repository.update { $0.staged = proposed }
            do {
                for monitor in newPlan where !existingNames.contains(monitor.name) {
                    try driver.install(monitor)
                }
                try repository.update({ document in
                    guard var committed = document.staged else { throw RuleError.busy }
                    if Set(committed.policy.applications).isSuperset(of: Set(document.active.policy.applications)),
                       (committed.policy.dailyLimitMinutes ?? Int.max) <= (document.active.policy.dailyLimitMinutes ?? Int.max) {
                        committed.reachedCycles.formUnion(document.active.reachedCycles.intersection(Set(committed.cycles.map(\.id))))
                    }
                    document.active = committed
                    document.staged = nil
                    document.lastError = nil
                }, afterSave: { self.apply($0.active, at: self.clock()) })
            } catch {
                driver.remove(names: newNames.subtracting(existingNames))
                try? repository.update({ document in
                    document.staged = nil
                    document.lastError = error.localizedDescription
                }, afterSave: { self.apply($0.active, at: self.clock()) })
                throw error
            }
            cleanup(keeping: newNames)
        }
    }

    private func cleanup(keeping names: Set<String>) {
        let owned = driver.registeredNames.filter { $0.hasPrefix(MonitorSpec.prefix) }
        driver.remove(names: owned.subtracting(names))
    }

}
