import BlockingCore
import Foundation
import XCTest

private final class FakeDriver: ProtectionDriver {
    var monitors: [String: MonitorSpec] = [:]
    var installedCount = 0
    var failAtInstall: Int?
    var onInstall: ((MonitorSpec) throws -> Void)?
    var lastDecision: ShieldDecision?
    var registeredNames: Set<String> { Set(monitors.keys) }
    func install(_ monitor: MonitorSpec) throws {
        installedCount += 1
        if installedCount == failAtInstall { throw CocoaError(.fileWriteUnknown) }
        monitors[monitor.name] = monitor
        try onInstall?(monitor)
    }
    func remove(names: Set<String>) { names.forEach { monitors.removeValue(forKey: $0) } }
    func apply(_ decision: ShieldDecision) { lastDecision = decision }
}

private final class TestClock {
    var now = date("2026-10-08 14:00:00")
}

final class CoordinatorTests: XCTestCase {
    private var directory: URL!
    private var repository: StateRepository!
    private var driver: FakeDriver!
    private var clock: TestClock!
    private var coordinator: ProtectionCoordinator!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try StateRepository(directory: directory)
        driver = FakeDriver()
        clock = TestClock()
        coordinator = ProtectionCoordinator(repository: repository, driver: driver, clock: { self.clock.now }, calendar: { calendar() })
        try coordinator.execute(.windows(sampleWindows))
        try coordinator.execute(.selection(.init(applications: [selectedApp])))
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func exhaustCurrentAllowance() throws {
        let state = try repository.read().active
        let name = MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[0].id)
        try coordinator.handleCallback(activity: name, event: MonitorSpec.limitEvent)
    }

    func testReopeningDoesNotReregisterOrResetUsage() throws {
        try exhaustCurrentAllowance()
        let count = driver.installedCount
        let before = try repository.read().active
        for _ in 0..<3 { try coordinator.reconcile() }
        XCTAssertEqual(driver.installedCount, count)
        XCTAssertEqual(try repository.read().active, before)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testEndOfScheduleCannotClearDailyLimit() throws {
        try exhaustCurrentAllowance()
        clock.now = date("2026-10-08 22:30:00")
        try coordinator.reconcile()
        XCTAssertTrue(driver.lastDecision!.scheduled)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        clock.now = date("2026-10-09 07:00:00")
        try coordinator.reconcile()
        try exhaustCurrentAllowance()
        clock.now = date("2026-10-09 10:00:00")
        try coordinator.handleCallback(activity: "old-window-ended")
        XCTAssertFalse(driver.lastDecision!.scheduled)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testFailedMonitorReplacementRetainsPreviousConfigurationAndShields() throws {
        try exhaustCurrentAllowance()
        let before = try repository.read().active
        let names = driver.registeredNames
        driver.failAtInstall = driver.installedCount + 2
        XCTAssertThrowsError(try coordinator.execute(.windows(before.policy.windows + [.init(startMinute: 700, endMinute: 1000)])))
        XCTAssertEqual(try repository.read().active, before)
        XCTAssertEqual(driver.registeredNames, names)
        XCTAssertNil(try repository.read().staged)
        XCTAssertNotNil(try repository.read().lastError)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testQueuedRemovalPreservesWindowAcrossBlockStart() throws {
        let before = try repository.read().active
        let installedCount = driver.installedCount
        clock.now = date("2026-10-08 05:59:59")
        try coordinator.execute(.windows([]))
        XCTAssertEqual(driver.installedCount, installedCount)
        clock.now = date("2026-10-08 06:00:00")
        try coordinator.reconcile()
        XCTAssertEqual(try repository.read().active.policy, before.policy)
        XCTAssertNotNil(try repository.read().active.pendingWindows)
        XCTAssertTrue(driver.lastDecision!.scheduled)
    }

    func testThresholdDeliveredDuringInstallationSurvivesCommit() throws {
        driver.onInstall = { [unowned self] spec in
            if case .budget(let cycle, _, _) = spec.kind, cycle.start <= self.clock.now, self.clock.now < cycle.end {
                try self.coordinator.handleCallback(activity: spec.name, event: MonitorSpec.limitEvent)
            }
        }
        try coordinator.execute(.limit(10))
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        XCTAssertEqual(try repository.read().active.reachedCycles.count, 1)
        XCTAssertNil(try repository.read().staged)
    }

    func testThresholdFromOldGenerationDuringInstallIsMergedWhenStillApplicable() throws {
        let old = try repository.read().active
        let name = MonitorSpec.budgetName(generation: old.generation, cycle: old.cycles[0].id)
        driver.onInstall = { [unowned self] _ in
            try self.coordinator.handleCallback(activity: name, event: MonitorSpec.limitEvent)
        }
        try coordinator.execute(.windows(old.policy.windows + [.init(startMinute: 600, endMinute: 700)]))
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testMissingMonitorsAreRepairedWithoutResettingExhaustion() throws {
        try exhaustCurrentAllowance()
        driver.monitors.removeAll()
        try coordinator.reconcile()
        XCTAssertEqual(driver.registeredNames.count, 5)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testDayRolloverWorksThroughExtensionWithoutOpeningMainApp() throws {
        try exhaustCurrentAllowance()
        try coordinator.execute(.limit(60))
        clock.now = date("2026-10-09 00:00:00")
        try coordinator.handleCallback(activity: MonitorSpec.midnightName)
        let state = try repository.read().active
        XCTAssertEqual(state.policy.dailyLimitMinutes, 60)
        XCTAssertFalse(driver.lastDecision!.budgetExhausted)
        XCTAssertNil(state.pendingLimit)
        XCTAssertEqual(driver.registeredNames.count, 5)
        XCTAssertEqual(state.cycles[0].start, clock.now)
    }

    func testFutureMonitorThresholdAlsoRotatesDayIfMidnightCallbackIsLate() throws {
        let state = try repository.read().active
        let tomorrow = state.cycles[1]
        clock.now = date("2026-10-09 01:00:00")
        try coordinator.handleCallback(activity: MonitorSpec.budgetName(generation: state.generation, cycle: tomorrow.id), event: MonitorSpec.limitEvent)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        XCTAssertEqual(try repository.read().active.cycles[0].id, tomorrow.id)
    }

    func testPendingOnlyEditDoesNotReplaceMonitors() throws {
        let count = driver.installedCount
        try coordinator.execute(.limit(60))
        XCTAssertEqual(driver.installedCount, count)
        XCTAssertEqual(try repository.read().active.policy.dailyLimitMinutes, 30)
    }

    func testAddingAppsReplacesBudgetMonitorsImmediately() throws {
        try coordinator.execute(.selection(.init(applications: [selectedApp, anotherApp])))
        XCTAssertEqual(Set(driver.lastDecision!.selection.applications), Set([selectedApp, anotherApp]))
        let budgets = driver.monitors.values.compactMap { spec -> [Data]? in
            if case .budget(_, let selection, _) = spec.kind { return selection.applications }
            return nil
        }
        XCTAssertEqual(budgets.count, 2)
        XCTAssertTrue(budgets.allSatisfy { Set($0) == Set([selectedApp, anotherApp]) })
        XCTAssertNil(try repository.read().active.pendingSelection)
    }

    func testStagedGenerationLeftByCrashIsRemovedOnRecovery() throws {
        let original = try repository.read().active
        var orphan = original
        orphan.generation = UUID()
        orphan.policy.dailyLimitMinutes = 500
        try repository.update { $0.staged = orphan }
        for spec in MonitorSpec.plan(for: orphan) { try driver.install(spec) }
        try coordinator.reconcile()
        XCTAssertEqual(try repository.read().active, original)
        XCTAssertNil(try repository.read().staged)
        XCTAssertEqual(driver.registeredNames, Set(MonitorSpec.plan(for: original).map(\.name)))
    }

    func testRepositorySurvivesRecreationAndRejectsUnknownVersions() throws {
        try exhaustCurrentAllowance()
        let second = try StateRepository(directory: directory)
        XCTAssertEqual(try second.read(), try repository.read())
        try repository.update { $0.schemaVersion = 999 }
        XCTAssertThrowsError(try second.read()) { XCTAssertEqual($0 as? RuleError, .unsupportedSchema) }
        XCTAssertThrowsError(try coordinator.reconcile())
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testLegacySingleAppStateMigratesWithoutLosingPendingSelection() throws {
        var document = try repository.read()
        document.active.pendingSelection = PendingSelection(selection: .init(applications: [anotherApp]),
            effectiveAfter: date("2026-10-09 00:00:00"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        var active = try XCTUnwrap(json["active"] as? [String: Any])
        var policy = try XCTUnwrap(active["policy"] as? [String: Any])
        policy["application"] = try XCTUnwrap((policy["applications"] as? [String])?.first)
        policy.removeValue(forKey: "applications")
        active["policy"] = policy
        var pending = try XCTUnwrap(active["pendingSelection"] as? [String: Any])
        pending["application"] = try XCTUnwrap((pending["applications"] as? [String])?.first)
        pending.removeValue(forKey: "applications")
        active["pendingApplication"] = pending
        active.removeValue(forKey: "pendingSelection")
        json["active"] = active
        json["schemaVersion"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent("protection-v1.json"))

        let restored = try repository.read()
        XCTAssertEqual(restored.active.policy.selection.applications, [selectedApp])
        XCTAssertEqual(restored.active.pendingSelection?.selection.applications, [anotherApp])
        try repository.update { _ in }
        XCTAssertEqual(try repository.read().schemaVersion, 3)
        XCTAssertEqual(try repository.read().active.pendingSelection?.selection.applications, [anotherApp])
    }

    func testCorruptDataNeverBecomesAnEmptyConfiguration() throws {
        try exhaustCurrentAllowance()
        try Data("invalid JSON".utf8).write(to: directory.appendingPathComponent("protection-v1.json"))
        XCTAssertThrowsError(try coordinator.reconcile())
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("protection-v1.json")), "invalid JSON")
    }

    func testFailedTransactionDoesNotPersistPartialChanges() throws {
        let before = try repository.read()
        XCTAssertThrowsError(try repository.update { document in
            document.active.policy.selection.applications = []
            throw CocoaError(.fileWriteUnknown)
        })
        XCTAssertEqual(try repository.read(), before)
    }

    func testConcurrentRepositoryTransactionsDoNotLoseUpdates() throws {
        try repository.update { $0.lastCallbackAt = Date(timeIntervalSince1970: 0) }
        let repository = self.repository!
        let errors = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            do {
                try repository.update { $0.lastCallbackAt = $0.lastCallbackAt!.addingTimeInterval(1) }
            } catch {
                errors.lock(); failures += 1; errors.unlock()
            }
        }
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(try repository.read().lastCallbackAt, Date(timeIntervalSince1970: 40))
    }

    func testMixedSelectionPersistsActiveStagedAndPendingTargets() throws {
        let selection = BlockingSelection(applications: [selectedApp], categories: [selectedCategory], webDomains: [selectedWebsite])
        try coordinator.execute(.selection(selection))
        try coordinator.execute(.selection(.init(webDomains: [selectedWebsite])))
        var saved = try repository.read()
        saved.staged = saved.active
        saved.staged?.generation = UUID()
        try repository.update { $0 = saved }
        let reopened = try StateRepository(directory: directory).read()
        XCTAssertEqual(reopened, saved)
        XCTAssertEqual(reopened.active.policy.selection, selection)
        XCTAssertEqual(reopened.active.pendingSelection?.selection, BlockingSelection(webDomains: [selectedWebsite]))
        XCTAssertEqual(reopened.staged?.policy.selection, selection)
        XCTAssertEqual(reopened.schemaVersion, 3)
    }

    func testFailedWebsiteAdditionRetainsOriginalCategoryShieldsAndBudget() throws {
        try repository.update { $0.active.policy.selection = BlockingSelection(categories: [selectedCategory]) }
        try coordinator.reconcile()
        try exhaustCurrentAllowance()
        let before = try repository.read().active
        let names = driver.registeredNames
        driver.failAtInstall = driver.installedCount + 2
        XCTAssertThrowsError(try coordinator.execute(.selection(.init(categories: [selectedCategory], webDomains: [selectedWebsite]))))
        XCTAssertEqual(try repository.read().active, before)
        XCTAssertEqual(driver.registeredNames, names)
        XCTAssertNil(try repository.read().staged)
        XCTAssertEqual(driver.lastDecision?.selection, before.policy.selection)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }

    func testOldCategoryThresholdDuringWebsiteAdditionSurvivesCommit() throws {
        try repository.update { $0.active.policy.selection = BlockingSelection(categories: [selectedCategory]) }
        try coordinator.reconcile()
        let old = try repository.read().active
        let activity = MonitorSpec.budgetName(generation: old.generation, cycle: old.cycles[0].id)
        driver.onInstall = { [unowned self] _ in
            try self.coordinator.handleCallback(activity: activity, event: MonitorSpec.limitEvent)
        }
        let larger = BlockingSelection(categories: [selectedCategory], webDomains: [selectedWebsite])
        try coordinator.execute(.selection(larger))
        XCTAssertEqual(driver.lastDecision?.selection, larger)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        let budgets = driver.monitors.values.compactMap { spec -> BlockingSelection? in
            if case .budget(_, let selection, _) = spec.kind { return selection }
            return nil
        }
        XCTAssertEqual(budgets, [larger, larger])
    }

    func testVersionTwoMigrationPreservesAppsExhaustionAndPendingRemoval() throws {
        try exhaustCurrentAllowance()
        try coordinator.execute(.selection(.init(applications: [anotherApp])))
        let before = try repository.read()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(before)) as? [String: Any])
        var active = try XCTUnwrap(json["active"] as? [String: Any])
        var policy = try XCTUnwrap(active["policy"] as? [String: Any])
        policy.removeValue(forKey: "categories")
        policy.removeValue(forKey: "webDomains")
        active["policy"] = policy
        var pending = try XCTUnwrap(active.removeValue(forKey: "pendingSelection") as? [String: Any])
        pending.removeValue(forKey: "categories")
        pending.removeValue(forKey: "webDomains")
        active["pendingApplications"] = pending
        json["active"] = active
        json["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent("protection-v1.json"))
        let restored = try repository.read()
        XCTAssertEqual(restored.active, before.active)
        try coordinator.reconcile()
        XCTAssertEqual(try repository.read().schemaVersion, 3)
        XCTAssertEqual(try repository.read().active, before.active)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
    }


    func testFreshInstallStartsWithAllowanceOnlyAndKeepsUserChosenSchedules() throws {
        let freshDirectory = directory.appendingPathComponent("fresh-install")
        let freshRepository = try StateRepository(directory: freshDirectory)
        let freshDriver = FakeDriver()
        let freshCoordinator = ProtectionCoordinator(repository: freshRepository, driver: freshDriver,
            clock: { self.clock.now }, calendar: { calendar() })
        XCTAssertTrue(try freshRepository.read().active.policy.windows.isEmpty)
        XCTAssertEqual(try freshRepository.read().active.policy.dailyLimitMinutes, 30)
        try freshCoordinator.execute(.selection(.init(applications: [selectedApp])))
        try freshCoordinator.reconcile()
        let activated = try freshRepository.read().active
        XCTAssertTrue(activated.policy.windows.isEmpty)
        XCTAssertFalse(activated.decision(at: date("2026-10-08 07:00:00"), calendar: calendar()).scheduled)
        XCTAssertNil(activated.policy.nextScheduleTransition(after: clock.now, calendar: calendar()))
        XCTAssertEqual(freshDriver.registeredNames.count, 3, "Only midnight and two shared-budget monitors")

        let chosen = BlockWindow(startMinute: 8 * 60, endMinute: 9 * 60)
        try freshCoordinator.execute(.windows([chosen]))
        let reopened = try StateRepository(directory: freshDirectory)
        try ProtectionCoordinator(repository: reopened, driver: freshDriver,
            clock: { self.clock.now }, calendar: { calendar() }).reconcile()
        XCTAssertEqual(try reopened.read().active.policy.windows, [chosen])
    }

}
