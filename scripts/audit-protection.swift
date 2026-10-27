// Checks formerly failing protection scenarios without changing app/device state.
// Compile with the core sources; see docs/PROTECTION_AUDIT.md.
import Foundation

private enum AuditFailure: Error { case unexpectedResult(String), monitorCapacity, registrationFailed }

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw AuditFailure.unexpectedResult(message) }
}

private final class AuditClock {
    var now = ISO8601DateFormatter().date(from: "2026-10-26T18:06:00Z")!
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
}

private final class AuditDriver: ProtectionDriver {
    var monitors: [String: MonitorSpec] = [:]
    var onInstall: ((MonitorSpec) throws -> Void)?
    var lastDecision: ShieldDecision?
    var registeredNames: Set<String> { Set(monitors.keys) }
    func install(_ monitor: MonitorSpec) throws {
        guard monitors[monitor.name] != nil || monitors.count < 20 else { throw AuditFailure.monitorCapacity }
        try onInstall?(monitor)
        monitors[monitor.name] = monitor
    }
    func remove(names: Set<String>) { names.forEach { monitors.removeValue(forKey: $0) } }
    func apply(_ decision: ShieldDecision) { lastDecision = decision }
}

@main
private struct ProtectionAudit {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daywell-audit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try interruptedCleanup(directory.appendingPathComponent("capacity"))
        try delayedMidnightCallback(directory.appendingPathComponent("midnight"))
        try timezoneResetCopy()
        try repairRollbackDiscardsThreshold(directory.appendingPathComponent("repair-rollback"))
        try interruptedStageRetainsThreshold(directory.appendingPathComponent("interrupted-stage"))
        print("Verified five protection recovery scenarios using simulated drivers/clocks. No real iOS callbacks or app state were changed.")
    }

    private static func interruptedCleanup(_ directory: URL) throws {
        let clock = AuditClock()
        let repository = try StateRepository(directory: directory)
        let driver = AuditDriver()
        let coordinator = ProtectionCoordinator(repository: repository, driver: driver,
            clock: { clock.now }, calendar: { clock.calendar })
        let windows = (0..<7).map { BlockWindow(startMinute: $0 * 60, endMinute: $0 * 60 + 30) }
        try coordinator.execute(.windows(windows))
        try coordinator.execute(.selection(.init(applications: [Data("test-token".utf8)])))
        let committed = try repository.read().active
        var retired = committed
        retired.generation = UUID()
        // A process killed after committing the new generation but before cleanup
        // leaves both complete generations registered, with no staged document.
        for monitor in MonitorSpec.plan(for: retired) { try driver.install(monitor) }
        try check(driver.monitors.count == 20, "Expected two complete monitor generations")
        clock.now = committed.cycles[0].end.addingTimeInterval(1)
        // Give recovery the benefit of the OS removing yesterday's expired budgets.
        driver.monitors = driver.monitors.filter { _, spec in
            if case .budget(let cycle, _, _) = spec.kind { return cycle.end > clock.now }
            return true
        }
        try coordinator.reconcile()
        let saved = try repository.read()
        try check(saved.active.cycles[0].end > clock.now, "Recovery must commit the new budget day")
        try check(saved.staged == nil, "Recovery must finish its transaction")
        try check(driver.registeredNames == Set(MonitorSpec.plan(for: saved.active).map(\.name)), "Obsolete generations must be removed")
        try check(driver.monitors.count == 10, "One complete configuration should remain")
        print("VERIFIED: interrupted post-commit cleanup + midnight => stale monitors retired before replacement, within the 20-activity cap")
    }

    private static func delayedMidnightCallback(_ directory: URL) throws {
        let clock = AuditClock()
        let repository = try StateRepository(directory: directory)
        let driver = AuditDriver()
        let coordinator = ProtectionCoordinator(repository: repository, driver: driver,
            clock: { clock.now }, calendar: { clock.calendar })
        try coordinator.execute(.selection(.init(applications: [Data("test-token".utf8)])))
        let active = try repository.read().active
        try coordinator.handleCallback(activity: MonitorSpec.budgetName(generation: active.generation, cycle: active.cycles[0].id),
            event: MonitorSpec.limitEvent)
        clock.now = active.cycles[0].end.addingTimeInterval(60)
        // The foreground timer now reconciles rather than only reading storage.
        for _ in 0..<4 {
            try coordinator.reconcile()
            let displayed = try repository.read().active.decision(at: clock.now, calendar: clock.calendar)
            try check(!displayed.isBlocked, "The dashboard should compute a fresh day's allowance")
            try check(driver.lastDecision?.isBlocked == false, "Foreground recovery must clear yesterday's budget shield")
        }
        print("VERIFIED: delayed midnight callbacks + foreground reconciliation => dashboard and applied shield both show time available")
    }

    private static func timezoneResetCopy() throws {
        let clock = AuditClock()
        var snapshot = ProtectionSnapshot()
        try snapshot.apply(.selection(.init(applications: [Data("test-token".utf8)])), at: clock.now, calendar: clock.calendar)
        let cycle = snapshot.cycles[0]
        snapshot.receiveThreshold(activity: MonitorSpec.budgetName(generation: snapshot.generation, cycle: cycle.id),
            event: MonitorSpec.limitEvent, at: clock.now)
        clock.calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        snapshot.advance(to: clock.now, calendar: clock.calendar)
        let decision = snapshot.decision(at: clock.now, calendar: clock.calendar)
        try check(decision.budgetExhausted, "The existing exhausted cycle remains pinned")
        try check(clock.calendar.component(.hour, from: decision.budgetResetsAt!) == 8, "Berlin midnight is 08:00 in Tokyo on this date")
        let message = ProtectionCopy.allowanceUsed(resetsAt: decision.budgetResetsAt, now: clock.now,
            calendar: clock.calendar, locale: Locale(identifier: "en_US_POSIX"))
        try check(message.contains("8:00") && !message.contains("midnight"), "Copy must display the actual local reset")
        print("VERIFIED: Berlin-to-Tokyo timezone change => the reset message shows the pinned 08:00 local reset")
    }

    private static func repairRollbackDiscardsThreshold(_ directory: URL) throws {
        let clock = AuditClock()
        let repository = try StateRepository(directory: directory)
        let driver = AuditDriver()
        let log = try DiagnosticLog(directory: directory.appendingPathComponent("diagnostics"))
        let coordinator = ProtectionCoordinator(repository: repository, driver: driver,
            clock: { clock.now }, calendar: { clock.calendar }, diagnostics: log)
        try coordinator.execute(.selection(.init(applications: [Data("test-token".utf8)])))
        let original = try repository.read().active
        clock.now = clock.now.addingTimeInterval(31 * 60)
        // Simulate iOS losing the registrations. Repair uses the same selection
        // and allowance, so a reached threshold remains relevant to the old policy.
        driver.monitors.removeAll()
        driver.onInstall = { monitor in
            if case .budget(let cycle, _, _) = monitor.kind {
                if cycle.start <= clock.now && clock.now < cycle.end {
                    try coordinator.handleCallback(activity: monitor.name, event: MonitorSpec.limitEvent)
                } else {
                    throw AuditFailure.registrationFailed
                }
            }
        }
        do {
            try coordinator.reconcile()
            throw AuditFailure.unexpectedResult("Expected tomorrow's registration to fail")
        } catch AuditFailure.registrationFailed {}
        let saved = try repository.read()
        let events = try log.read().events
        try check(saved.active.policy == original.policy, "Repair did not change the rules")
        try check(saved.staged == nil && saved.active.reachedCycles.contains(original.cycles[0].id), "Rollback must retain a compatible threshold")
        try check(driver.lastDecision?.isBlocked == true, "The accepted threshold must apply to the retained policy")
        try check(events.contains { $0.name == "callback.processed" && $0.details["stagedResult"] == "accepted" },
                  "The diagnostic trail must confirm that the threshold was accepted")
        try check(events.contains { $0.name == "configuration.rolled_back" }, "The diagnostic trail must retain the rollback")

        driver.onInstall = nil
        try coordinator.reconcile()
        try check(driver.lastDecision?.budgetExhausted == true, "Repair must not need a second threshold callback")
        print("VERIFIED: failed repair retains an accepted current-day threshold through rollback and later repair")
    }

    private static func interruptedStageRetainsThreshold(_ directory: URL) throws {
        let clock = AuditClock()
        let repository = try StateRepository(directory: directory)
        let driver = AuditDriver()
        let coordinator = ProtectionCoordinator(repository: repository, driver: driver,
            clock: { clock.now }, calendar: { clock.calendar })
        try coordinator.execute(.selection(.init(applications: [Data("test-token".utf8)])))
        let active = try repository.read().active
        var staged = active
        staged.generation = UUID()
        staged.reachedCycles.insert(active.cycles[0].id)
        try repository.update { $0.staged = staged }
        for monitor in MonitorSpec.plan(for: staged) { try driver.install(monitor) }
        try coordinator.reconcile()
        let recovered = try repository.read()
        try check(recovered.staged == nil, "The interrupted configuration must be retired")
        try check(recovered.active.generation == active.generation, "The active rules remain authoritative")
        try check(driver.lastDecision?.budgetExhausted == true, "Crash recovery must retain compatible threshold evidence")
        print("VERIFIED: interrupted staged update retains a compatible threshold while recovering the previous configuration")
    }
}
