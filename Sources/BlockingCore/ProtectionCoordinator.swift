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
    private let diagnostics: DiagnosticLog?
    private let diagnosticSource: String

    public init(repository: StateRepository, driver: ProtectionDriver,
                clock: @escaping () -> Date = Date.init,
                calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
                diagnostics: DiagnosticLog? = nil, diagnosticSource: String = "coordinator") {
        self.repository = repository
        self.driver = driver
        self.clock = clock
        self.calendar = calendar
        self.diagnostics = diagnostics
        self.diagnosticSource = diagnosticSource
    }

    public func reconcile() throws {
        do { try update(edit: nil) }
        catch {
            record("reconcile.failed", details: DiagnosticEvent.errorDetails(error))
            throw error
        }
    }

    public func execute(_ edit: RuleEdit) throws {
        let kind: String
        switch edit {
        case .windows: kind = "windows"
        case .limit: kind = "allowance"
        case .selection: kind = "selection"
        case .cancelPending: kind = "cancel_pending"
        }
        record("edit.requested", details: ["kind": kind])
        do {
            try update(edit: edit)
            record("edit.completed", details: ["kind": kind])
        } catch {
            record("edit.failed", details: DiagnosticEvent.errorDetails(error).merging(["kind": kind]) { _, new in new })
            throw error
        }
    }

    public func handleCallback(activity: String, event: String? = nil, kind: String? = nil) throws {
        let now = clock()
        let details = ["activity": activity, "event": event ?? "none",
                       "kind": kind ?? (event == nil ? "interval_unspecified" : "threshold_reached")]
        record("callback.received", details: details, at: now)
        var result = details
        try repository.update({ document in
            result["activeResult"] = document.active.diagnosticThresholdResult(activity: activity, event: event, at: now)
            result["stagedResult"] = document.staged?.diagnosticThresholdResult(activity: activity, event: event, at: now) ?? "no_staged_configuration"
            result["stagedGeneration"] = document.staged?.generation.uuidString ?? "none"
            document.lastCallbackAt = now
            if let event {
                document.active.receiveThreshold(activity: activity, event: event, at: now)
                document.staged?.receiveThreshold(activity: activity, event: event, at: now)
            }
        }, afterSave: {
            self.record("callback.processed", details: result, snapshot: $0.active, at: now)
            self.apply($0.active, at: now)
        })
        do { try reconcile() } catch RuleError.busy {
            // The installer will merge any threshold delivered during registration.
            record("callback.reconcile_deferred", details: details, at: now)
        }
    }

    private func apply(_ snapshot: ProtectionSnapshot, at now: Date) {
        driver.apply(snapshot.decision(at: now, calendar: calendar()))
    }

    private func record(_ name: String, details: [String: String] = [:],
                        snapshot: ProtectionSnapshot? = nil, at date: Date? = nil) {
        guard let diagnostics else { return }
        let now = date ?? clock()
        var fields = details
        fields["timeZone"] = calendar().timeZone.identifier
        diagnostics.record(DiagnosticEvent(name: name, source: diagnosticSource, date: now, details: fields,
            snapshot: snapshot.map { DiagnosticSnapshot($0, at: now, calendar: calendar()) }))
    }

    private func update(edit: RuleEdit?) throws {
        try repository.withOperationLock {
            // Recover a process interrupted between registration and commit. The previous
            // active configuration remains authoritative until every new monitor succeeds.
            let saved = try repository.read()
            if let orphan = saved.staged {
                record("configuration.recovering_staged", snapshot: orphan)
                let activeNames = Set(MonitorSpec.plan(for: saved.active).map(\.name))
                driver.remove(names: Set(MonitorSpec.plan(for: orphan).map(\.name)).subtracting(activeNames))
                try repository.update({ document in
                    if let staged = document.staged { document.active.mergeCompatibleThresholds(from: staged) }
                    document.staged = nil
                }, afterSave: { self.apply($0.active, at: self.clock()) })
            }
            let now = clock()
            let old = try repository.read().active
            // A process can die after commit but before retiring the old monitors.
            // Free only obsolete owned registrations before installing another full
            // generation, otherwise midnight recovery can exceed iOS's activity cap.
            cleanup(keeping: Set(MonitorSpec.plan(for: old).map(\.name)))
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
                }, afterSave: {
                    if old != $0.active { self.record("state.updated", snapshot: $0.active) }
                    self.apply($0.active, at: self.clock())
                })
                cleanup(keeping: expectedNames)
                return
            }

            proposed.generation = UUID()
            let newPlan = MonitorSpec.plan(for: proposed)
            let newNames = Set(newPlan.map(\.name))
            let existingNames = driver.registeredNames
            try repository.update { $0.staged = proposed }
            record("configuration.staged", details: ["previousGeneration": old.generation.uuidString,
                "registeredNames": existingNames.sorted().joined(separator: ","),
                "newMonitorCount": String(newPlan.count)], snapshot: proposed)
            do {
                for monitor in newPlan where !existingNames.contains(monitor.name) {
                    record("monitor.install_requested", details: monitor.diagnosticDetails)
                    do {
                        try driver.install(monitor)
                        record("monitor.install_succeeded", details: monitor.diagnosticDetails)
                    } catch {
                        record("monitor.install_failed", details: monitor.diagnosticDetails.merging(DiagnosticEvent.errorDetails(error)) { _, new in new })
                        throw error
                    }
                }
                try repository.update({ document in
                    guard var committed = document.staged else { throw RuleError.busy }
                    committed.mergeCompatibleThresholds(from: document.active)
                    document.active = committed
                    document.staged = nil
                    document.lastError = nil
                }, afterSave: {
                    self.record("configuration.committed", snapshot: $0.active)
                    self.apply($0.active, at: self.clock())
                })
            } catch {
                driver.remove(names: newNames.subtracting(existingNames))
                try? repository.update({ document in
                    if let staged = document.staged { document.active.mergeCompatibleThresholds(from: staged) }
                    document.staged = nil
                    document.lastError = error.localizedDescription
                }, afterSave: {
                    self.record("configuration.rolled_back", details: DiagnosticEvent.errorDetails(error), snapshot: $0.active)
                    self.apply($0.active, at: self.clock())
                })
                throw error
            }
            cleanup(keeping: newNames)
        }
    }

    private func cleanup(keeping names: Set<String>) {
        let owned = driver.registeredNames.filter { $0.hasPrefix(MonitorSpec.prefix) }
        let removed = owned.subtracting(names)
        if !removed.isEmpty { record("monitor.retired", details: ["activities": removed.sorted().joined(separator: ",")]) }
        driver.remove(names: owned.subtracting(names))
    }

}
