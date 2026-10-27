import BlockingCore
import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private final class DiagnosticTestDriver: ProtectionDriver {
    var monitors: [String: MonitorSpec] = [:]
    var onInstall: ((MonitorSpec) throws -> Void)?
    var lastDecision: ShieldDecision?
    var registeredNames: Set<String> { Set(monitors.keys) }
    func install(_ monitor: MonitorSpec) throws {
        monitors[monitor.name] = monitor
        try onInstall?(monitor)
    }
    func remove(names: Set<String>) { names.forEach { monitors.removeValue(forKey: $0) } }
    func apply(_ decision: ShieldDecision) { lastDecision = decision }
}

final class DiagnosticsTests: XCTestCase {
    private var directory: URL!
    private let now = ISO8601DateFormatter().date(from: "2026-10-26T18:06:00Z")!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func journal(maximumFileBytes: Int = 128 * 1024, fileCount: Int = 4) throws -> DiagnosticLog {
        try DiagnosticLog(directory: directory.appendingPathComponent("diagnostics"),
                          maximumFileBytes: maximumFileBytes, fileCount: fileCount)
    }

    func testRotationBoundsStorageAndRetainsNewestEventsAcrossInstances() throws {
        let log = try journal(maximumFileBytes: 4096, fileCount: 3)
        for index in 0..<100 {
            XCTAssertTrue(log.record(.init(name: "callback.received", source: "monitor", date: now,
                details: ["sequence": String(index), "padding": String(repeating: "a", count: 80)])))
        }
        let reopened = try journal(maximumFileBytes: 4096, fileCount: 3)
        let history = try reopened.read()
        let sequence = history.events.compactMap { Int($0.details["sequence"] ?? "") }
        XCTAssertEqual(sequence.last, 99)
        XCTAssertGreaterThan(try XCTUnwrap(sequence.first), 0)
        XCTAssertEqual(sequence, Array(sequence.first!...99))
        XCTAssertEqual(history.unreadableRecords, 0)
        let files = try FileManager.default.contentsOfDirectory(at: log.directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(files.count, 3)
        for file in files { XCTAssertLessThanOrEqual(try XCTUnwrap(file.resourceValues(forKeys: [.fileSizeKey]).fileSize), 4096) }
    }

    func testInterruptedRecordDoesNotHideTheFollowingCallback() throws {
        let log = try journal()
        XCTAssertTrue(log.record(.init(name: "before", source: "app", date: now)))
        let file = try FileHandle(forWritingTo: log.directory.appendingPathComponent("events-0.jsonl"))
        try file.seekToEnd()
        try file.write(contentsOf: Data("{interrupted".utf8))
        try file.close()
        XCTAssertTrue(log.record(.init(name: "after", source: "monitor", date: now)))
        let history = try log.read()
        XCTAssertEqual(history.events.map(\.name), ["before", "after"])
        XCTAssertEqual(history.unreadableRecords, 1)
    }

    func testConcurrentWritersPreserveEverySuccessfulRecordWithoutInterleaving() throws {
        let logs = try (0..<4).map { _ in try journal() }
        let lock = NSLock()
        var accepted: Set<UUID> = []
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let event = DiagnosticEvent(name: "callback", source: "process-\(index % 4)", date: now)
            if logs[index % 4].record(event) {
                lock.lock()
                accepted.insert(event.id)
                lock.unlock()
            }
        }
        let history = try logs[0].read()
        XCTAssertFalse(accepted.isEmpty)
        XCTAssertEqual(Set(history.events.map(\.id)), accepted)
        XCTAssertEqual(history.unreadableRecords, 0)
    }

    func testBusyDiagnosticLockNeverBlocksProtection() throws {
        let log = try journal()
        let descriptor = open(log.directory.appendingPathComponent("diagnostics.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertFalse(log.record(.init(name: "dropped", source: "test")))

        let repo = try StateRepository(directory: directory.appendingPathComponent("state"))
        let driver = DiagnosticTestDriver()
        let coordinator = ProtectionCoordinator(repository: repo, driver: driver,
            clock: { self.now }, calendar: { self.calendar }, diagnostics: log)
        try coordinator.execute(.selection(.init(applications: [Data("token".utf8)])))
        let state = try repo.read().active
        try coordinator.handleCallback(activity: MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[0].id),
                                       event: MonitorSpec.limitEvent)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted)
        XCTAssertEqual(try repo.read().active.reachedCycles.count, 1)
    }

    func testUnavailableDiagnosticDirectoryDoesNotChangeEnforcement() throws {
        let log = try journal()
        try FileManager.default.removeItem(at: log.directory)
        XCTAssertFalse(log.record(.init(name: "unavailable", source: "test")))
        let repo = try StateRepository(directory: directory.appendingPathComponent("state"))
        let driver = DiagnosticTestDriver()
        let coordinator = ProtectionCoordinator(repository: repo, driver: driver,
            clock: { self.now }, calendar: { self.calendar }, diagnostics: log)
        try coordinator.execute(.selection(.init(applications: [Data("token".utf8)])))
        XCTAssertFalse(driver.lastDecision!.isBlocked)
        XCTAssertEqual(try repo.read().active.policy.dailyLimitMinutes, 30)
    }

    func testExportOmitsActiveStagedAndPendingTokensAndArbitraryErrors() throws {
        let token = Data("private-selected-application".utf8)
        let category = Data("private-category".utf8)
        let domain = Data("private.example.com".utf8)
        var document = ProtectionDocument()
        document.active.policy.selection = .init(applications: [token], categories: [category], webDomains: [domain])
        document.active.advance(to: now, calendar: calendar)
        document.active.pendingSelection = PendingSelection(selection: .init(webDomains: [domain]), effectiveAfter: now)
        document.staged = document.active
        document.lastError = "An error containing private-selected-application"
        let problem = DiagnosticProblem(description: "Blocked too early", occurredAt: now, selectedUsageShown: "0 min")
        var report = DiagnosticReport(generatedAt: now, problem: problem, environment: ["appBuild": "test"],
            state: DiagnosticState(document, at: now, calendar: calendar))
        report.history.events = [.init(name: "configuration.staged", source: "test", date: now,
            snapshot: DiagnosticSnapshot(document.active, at: now, calendar: calendar))]
        let json = String(decoding: try report.encoded(), as: UTF8.self)
        for secret in [token, category, domain] {
            XCTAssertFalse(json.contains(String(decoding: secret, as: UTF8.self)))
            XCTAssertFalse(json.contains(secret.base64EncodedString()))
        }
        XCTAssertTrue(json.contains("Blocked too early"))
        XCTAssertTrue(json.contains("0 min"))
        XCTAssertEqual(report.state?.active.selection.applications, 1)
        XCTAssertEqual(report.state?.staged?.pendingSelection?.selection.webDomains, 1)
        XCTAssertEqual(report.state?.hasSavedError, true)
    }

    func testImmediateCallbackDuringActivationHasAnOrderedDiagnosticTrail() throws {
        let log = try journal()
        let repo = try StateRepository(directory: directory.appendingPathComponent("state"))
        let driver = DiagnosticTestDriver()
        let coordinator = ProtectionCoordinator(repository: repo, driver: driver,
            clock: { self.now }, calendar: { self.calendar }, diagnostics: log, diagnosticSource: "test-app")
        driver.onInstall = { spec in
            if case .budget(let cycle, _, _) = spec.kind, cycle.start <= self.now, self.now < cycle.end {
                try coordinator.handleCallback(activity: spec.name, event: MonitorSpec.limitEvent, kind: "threshold_reached")
            }
        }
        try coordinator.execute(.selection(.init(applications: [Data("private-token".utf8)])))
        let history = try log.read()
        let received = try XCTUnwrap(history.events.firstIndex { $0.name == "callback.received" })
        let processed = try XCTUnwrap(history.events.firstIndex { $0.name == "callback.processed" })
        let committed = try XCTUnwrap(history.events.firstIndex { $0.name == "configuration.committed" })
        let activity = try XCTUnwrap(history.events[received].details["activity"])
        let requested = try XCTUnwrap(history.events.firstIndex {
            $0.name == "monitor.install_requested" && $0.details["activity"] == activity
        })
        XCTAssertLessThan(requested, received)
        XCTAssertLessThan(received, processed)
        XCTAssertLessThan(processed, committed)
        XCTAssertEqual(history.events[processed].details["activeResult"], "no_selection")
        XCTAssertEqual(history.events[processed].details["stagedResult"], "accepted")
        XCTAssertEqual(history.events[received].details["kind"], "threshold_reached")
        XCTAssertTrue(history.events[committed].snapshot!.budgetExhausted)
        XCTAssertTrue(driver.lastDecision!.budgetExhausted, "Instrumentation must preserve the existing behavior, including this known failure path.")
    }

    func testRejectedCallbacksExplainWhyTheyDidNotExhaustTheAllowance() throws {
        var snapshot = ProtectionSnapshot()
        try snapshot.apply(.selection(.init(applications: [Data("token".utf8)])), at: now, calendar: calendar)
        let current = MonitorSpec.budgetName(generation: snapshot.generation, cycle: snapshot.cycles[0].id)
        let future = MonitorSpec.budgetName(generation: snapshot.generation, cycle: snapshot.cycles[1].id)
        XCTAssertEqual(snapshot.diagnosticThresholdResult(activity: current, event: nil, at: now), "not_a_threshold")
        XCTAssertEqual(snapshot.diagnosticThresholdResult(activity: "stale", event: MonitorSpec.limitEvent, at: now), "unrecognized_generation_or_cycle")
        XCTAssertEqual(snapshot.diagnosticThresholdResult(activity: future, event: MonitorSpec.limitEvent, at: now), "outside_cycle")
        XCTAssertEqual(snapshot.diagnosticThresholdResult(activity: current, event: MonitorSpec.limitEvent, at: now), "accepted")
        snapshot.receiveThreshold(activity: current, event: MonitorSpec.limitEvent, at: now)
        XCTAssertEqual(snapshot.diagnosticThresholdResult(activity: current, event: MonitorSpec.limitEvent, at: now), "already_exhausted")
    }

    func testFailedRegistrationIsRecordedWithoutLeakingErrorUserInfo() throws {
        let log = try journal()
        let repo = try StateRepository(directory: directory.appendingPathComponent("state"))
        let driver = DiagnosticTestDriver()
        let coordinator = ProtectionCoordinator(repository: repo, driver: driver,
            clock: { self.now }, calendar: { self.calendar }, diagnostics: log)
        driver.onInstall = { _ in throw NSError(domain: "RegistrationTest", code: 42,
            userInfo: [NSLocalizedDescriptionKey: "private error content"]) }
        XCTAssertThrowsError(try coordinator.execute(.selection(.init(applications: [Data("token".utf8)]))))
        let history = try log.read()
        let failure = try XCTUnwrap(history.events.first { $0.name == "monitor.install_failed" })
        XCTAssertEqual(failure.details["errorDomain"], "RegistrationTest")
        XCTAssertEqual(failure.details["errorCode"], "42")
        XCTAssertTrue(history.events.contains { $0.name == "configuration.rolled_back" })
        XCTAssertFalse(String(decoding: try DiagnosticLog.encoder().encode(history), as: UTF8.self).contains("private error content"))
        XCTAssertTrue(try repo.read().active.policy.selection.isEmpty)
    }

    func testOversizedEventCannotGrowTheJournalWithoutBound() throws {
        let log = try journal(maximumFileBytes: 4096, fileCount: 1)
        XCTAssertTrue(log.record(.init(name: "oversized", source: "test",
            details: ["payload": String(repeating: "x", count: 100_000)])))
        let history = try log.read()
        XCTAssertEqual(history.events.count, 1)
        XCTAssertNotNil(history.events[0].details["detailsOmitted"])
        XCTAssertLessThanOrEqual(try Data(contentsOf: log.directory.appendingPathComponent("events-0.jsonl")).count, 4096)
    }
}
