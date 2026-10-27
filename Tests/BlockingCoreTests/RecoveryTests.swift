import BlockingCore
import Foundation
import XCTest

private enum RecoveryFailure: Error { case capacity, registration }

private final class RecoveryClock {
    var now = date("2026-10-08 14:00:00")
}

private final class RecoveryDriver: ProtectionDriver {
    var monitors: [String: MonitorSpec] = [:]
    var onInstall: ((MonitorSpec) throws -> Void)?
    var lastDecision: ShieldDecision?
    var installedCount = 0
    var registeredNames: Set<String> { Set(monitors.keys) }

    func install(_ monitor: MonitorSpec) throws {
        guard monitors[monitor.name] != nil || monitors.count < 20 else { throw RecoveryFailure.capacity }
        try onInstall?(monitor)
        monitors[monitor.name] = monitor
        installedCount += 1
    }

    func remove(names: Set<String>) { names.forEach { monitors.removeValue(forKey: $0) } }
    func apply(_ decision: ShieldDecision) { lastDecision = decision }
}

final class RecoveryTests: XCTestCase {
    private var directory: URL!
    private var repository: StateRepository!
    private var driver: RecoveryDriver!
    private var clock: RecoveryClock!
    private var coordinator: ProtectionCoordinator!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try StateRepository(directory: directory)
        driver = RecoveryDriver()
        clock = RecoveryClock()
        coordinator = ProtectionCoordinator(repository: repository, driver: driver,
            clock: { self.clock.now }, calendar: { calendar() })
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func activate(windows: [BlockWindow] = []) throws {
        try coordinator.execute(.windows(windows))
        try coordinator.execute(.selection(.init(applications: [selectedApp])))
    }

    private func thresholdForCurrentCycle() throws {
        let snapshot = try repository.read().active
        let cycle = try XCTUnwrap(snapshot.currentCycle(at: clock.now))
        try coordinator.handleCallback(activity: MonitorSpec.budgetName(generation: snapshot.generation, cycle: cycle.id),
            event: MonitorSpec.limitEvent)
    }

    func testRetiresCommittedGenerationLeftByCrashBeforeMidnightReplacement() throws {
        let windows = (0..<7).map { BlockWindow(startMinute: $0 * 60, endMinute: $0 * 60 + 30) }
        try activate(windows: windows)
        let active = try repository.read().active
        var retired = active
        retired.generation = UUID()
        for spec in MonitorSpec.plan(for: retired) { try driver.install(spec) }
        XCTAssertEqual(driver.monitors.count, 20)

        clock.now = active.cycles[0].end.addingTimeInterval(1)
        driver.monitors = driver.monitors.filter { _, spec in
            if case .budget(let cycle, _, _) = spec.kind { return cycle.end > clock.now }
            return true
        }
        try coordinator.reconcile()
        let recovered = try repository.read().active
        XCTAssertGreaterThan(recovered.cycles[0].end, clock.now)
        XCTAssertEqual(driver.registeredNames, Set(MonitorSpec.plan(for: recovered).map(\.name)))
        XCTAssertEqual(driver.monitors.count, 10)
    }

    func testRepairRollbackPreservesAcceptedCompatibleThreshold() throws {
        try activate()
        let original = try repository.read().active
        driver.monitors.removeAll()
        clock.now = clock.now.addingTimeInterval(31 * 60)
        driver.onInstall = { spec in
            if case .budget(let cycle, _, _) = spec.kind {
                if cycle.start <= self.clock.now, self.clock.now < cycle.end {
                    try self.coordinator.handleCallback(activity: spec.name, event: MonitorSpec.limitEvent)
                } else {
                    throw RecoveryFailure.registration
                }
            }
        }
        XCTAssertThrowsError(try coordinator.reconcile())
        let saved = try repository.read()
        XCTAssertEqual(saved.active.policy, original.policy)
        XCTAssertEqual(saved.active.generation, original.generation)
        XCTAssertEqual(saved.active.reachedCycles, [original.cycles[0].id])
        XCTAssertNil(saved.staged)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)

        driver.onInstall = nil
        try coordinator.reconcile()
        XCTAssertTrue(driver.lastDecision!.budgetExhausted, "Repair must not need a second iOS threshold callback")
    }

    func testRollbackDoesNotTransferThresholdForStricterUncommittedAllowance() throws {
        try activate()
        driver.onInstall = { spec in
            if case .budget(let cycle, _, _) = spec.kind {
                if cycle.start <= self.clock.now, self.clock.now < cycle.end {
                    try self.coordinator.handleCallback(activity: spec.name, event: MonitorSpec.limitEvent)
                } else {
                    throw RecoveryFailure.registration
                }
            }
        }
        XCTAssertThrowsError(try coordinator.execute(.limit(10)))
        XCTAssertEqual(try repository.read().active.policy.dailyLimitMinutes, 30)
        XCTAssertFalse(driver.lastDecision!.budgetExhausted, "Ten minutes does not prove the old 30-minute allowance is used")
    }

    func testRollbackDoesNotTransferThresholdFromAddedTargets() throws {
        try activate()
        driver.onInstall = { spec in
            if case .budget(let cycle, _, _) = spec.kind {
                if cycle.start <= self.clock.now, self.clock.now < cycle.end {
                    try self.coordinator.handleCallback(activity: spec.name, event: MonitorSpec.limitEvent)
                } else {
                    throw RecoveryFailure.registration
                }
            }
        }
        XCTAssertThrowsError(try coordinator.execute(.selection(.init(applications: [selectedApp, anotherApp]))))
        XCTAssertEqual(try repository.read().active.policy.selection.applications, [selectedApp])
        XCTAssertFalse(driver.lastDecision!.budgetExhausted, "Usage of an uncommitted new app cannot exhaust the retained selection")
    }

    func testCrashRecoveryRetainsCompatibleStagedThreshold() throws {
        try activate()
        let active = try repository.read().active
        var staged = active
        staged.generation = UUID()
        staged.reachedCycles.insert(active.cycles[0].id)
        try repository.update { $0.staged = staged }
        for spec in MonitorSpec.plan(for: staged) { try driver.install(spec) }

        try coordinator.reconcile()
        let saved = try repository.read()
        XCTAssertEqual(saved.active.generation, active.generation)
        XCTAssertNil(saved.staged)
        XCTAssertTrue(saved.active.reachedCycles.contains(active.cycles[0].id))
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        XCTAssertEqual(driver.registeredNames, Set(MonitorSpec.plan(for: saved.active).map(\.name)))
    }

    func testCrashRecoveryDoesNotTransferIncompatibleStagedThreshold() throws {
        try activate()
        let active = try repository.read().active
        var staged = active
        staged.generation = UUID()
        staged.policy.dailyLimitMinutes = 1
        staged.reachedCycles.insert(active.cycles[0].id)
        try repository.update { $0.staged = staged }

        try coordinator.reconcile()
        XCTAssertEqual(try repository.read().active.policy.dailyLimitMinutes, 30)
        XCTAssertFalse(driver.lastDecision!.budgetExhausted)
    }

    func testCrashRecoverySavesThresholdEvenIfTheNextRepairAlsoFails() throws {
        try activate()
        let active = try repository.read().active
        var staged = active
        staged.generation = UUID()
        staged.reachedCycles.insert(active.cycles[0].id)
        try repository.update { $0.staged = staged }
        driver.monitors.removeAll()
        driver.onInstall = { _ in throw RecoveryFailure.registration }

        XCTAssertThrowsError(try coordinator.reconcile())
        XCTAssertTrue(try repository.read().active.reachedCycles.contains(active.cycles[0].id))
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testYesterdaysStagedThresholdCannotExhaustTheNewDay() throws {
        try activate()
        let active = try repository.read().active
        var staged = active
        staged.generation = UUID()
        staged.reachedCycles.insert(active.cycles[0].id)
        try repository.update { $0.staged = staged }
        clock.now = active.cycles[0].end.addingTimeInterval(1)

        try coordinator.reconcile()
        XCTAssertTrue(try repository.read().active.reachedCycles.isEmpty)
        XCTAssertFalse(driver.lastDecision!.budgetExhausted)
    }

    func testCleanupKeepsActiveAndForeignMonitorsOnFailedReplacement() throws {
        try activate()
        let active = try repository.read().active
        var retired = active
        retired.generation = UUID()
        for spec in MonitorSpec.plan(for: retired) { try driver.install(spec) }
        var foreign = try XCTUnwrap(MonitorSpec.plan(for: active).first)
        foreign.name = "unrelated.monitor"
        try driver.install(foreign)
        driver.onInstall = { _ in throw RecoveryFailure.registration }

        XCTAssertThrowsError(try coordinator.execute(.limit(10)))
        let expected = Set(MonitorSpec.plan(for: active).map(\.name)).union([foreign.name])
        XCTAssertEqual(driver.registeredNames, expected)
        XCTAssertEqual(try repository.read().active, active)
    }

    func testForegroundReconciliationClearsExpiredBudgetWithoutCallback() throws {
        try activate()
        try thresholdForCurrentCycle()
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        clock.now = try repository.read().active.cycles[0].end.addingTimeInterval(1)
        try coordinator.reconcile()
        XCTAssertFalse(driver.lastDecision!.isBlocked)
        let count = driver.installedCount
        let snapshot = try repository.read().active
        for _ in 0..<4 { try coordinator.reconcile() }
        XCTAssertEqual(driver.installedCount, count)
        XCTAssertEqual(try repository.read().active, snapshot)
    }

    func testForegroundReconciliationUpdatesScheduleWithoutCallback() throws {
        try activate(windows: [BlockWindow(startMinute: 15 * 60, endMinute: 16 * 60)])
        let count = driver.installedCount
        clock.now = date("2026-10-08 15:00:01")
        try coordinator.reconcile()
        XCTAssertTrue(driver.lastDecision!.scheduled)
        clock.now = date("2026-10-08 16:00:01")
        try coordinator.reconcile()
        XCTAssertFalse(driver.lastDecision!.isBlocked)
        XCTAssertEqual(driver.installedCount, count)
    }
}
