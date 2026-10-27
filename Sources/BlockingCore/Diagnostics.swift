import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Deliberately contains counts, never Screen Time tokens or app/domain names.
public struct DiagnosticSelection: Codable, Equatable, Sendable {
    public var applications: Int
    public var categories: Int
    public var webDomains: Int

    public init(_ selection: BlockingSelection) {
        applications = selection.applications.count
        categories = selection.categories.count
        webDomains = selection.webDomains.count
    }
}

public struct DiagnosticSnapshot: Codable, Sendable {
    public struct PendingSelection: Codable, Sendable {
        public var selection: DiagnosticSelection
        public var effectiveAfter: Date
    }

    public var generation: UUID
    public var selection: DiagnosticSelection
    public var windows: [BlockWindow]
    public var dailyLimitMinutes: Int?
    public var scheduleTimeZoneIdentifier: String
    public var cycles: [BudgetCycle]
    public var reachedCycles: [UUID]
    public var pendingLimit: PendingLimit?
    public var pendingWindows: PendingWindows?
    public var pendingSelection: PendingSelection?
    public var scheduled: Bool
    public var budgetExhausted: Bool
    public var nextScheduleTransition: Date?
    public var budgetResetsAt: Date?

    public init(_ snapshot: ProtectionSnapshot, at now: Date, calendar: Calendar) {
        generation = snapshot.generation
        selection = DiagnosticSelection(snapshot.policy.selection)
        windows = snapshot.policy.windows
        dailyLimitMinutes = snapshot.policy.dailyLimitMinutes
        scheduleTimeZoneIdentifier = snapshot.scheduleTimeZoneIdentifier
        cycles = snapshot.cycles
        reachedCycles = snapshot.reachedCycles.sorted { $0.uuidString < $1.uuidString }
        pendingLimit = snapshot.pendingLimit
        pendingWindows = snapshot.pendingWindows
        pendingSelection = snapshot.pendingSelection.map {
            PendingSelection(selection: DiagnosticSelection($0.selection), effectiveAfter: $0.effectiveAfter)
        }
        let decision = snapshot.decision(at: now, calendar: calendar)
        scheduled = decision.scheduled
        budgetExhausted = decision.budgetExhausted
        nextScheduleTransition = decision.nextScheduleTransition
        budgetResetsAt = decision.budgetResetsAt
    }
}

public struct DiagnosticState: Codable, Sendable {
    public var schemaVersion: Int
    public var active: DiagnosticSnapshot
    public var staged: DiagnosticSnapshot?
    public var lastCallbackAt: Date?
    public var hasSavedError: Bool

    public init(_ document: ProtectionDocument, at now: Date, calendar: Calendar) {
        schemaVersion = document.schemaVersion
        active = DiagnosticSnapshot(document.active, at: now, calendar: calendar)
        staged = document.staged.map { DiagnosticSnapshot($0, at: now, calendar: calendar) }
        lastCallbackAt = document.lastCallbackAt
        // Arbitrary error descriptions/userInfo can contain file paths or tokens.
        // Error events separately retain the safe domain, code, and error type.
        hasSavedError = document.lastError != nil
    }
}

public struct DiagnosticEvent: Codable, Sendable {
    public var id = UUID()
    public var date: Date
    public var uptimeSeconds: TimeInterval
    public var source: String
    public var name: String
    public var details: [String: String]
    public var snapshot: DiagnosticSnapshot?

    public init(name: String, source: String, date: Date = Date(),
                uptimeSeconds: TimeInterval = ProcessInfo.processInfo.systemUptime,
                details: [String: String] = [:], snapshot: DiagnosticSnapshot? = nil) {
        self.name = name
        self.source = source
        self.date = date
        self.uptimeSeconds = uptimeSeconds
        self.details = details
        self.snapshot = snapshot
    }

    public static func errorDetails(_ error: Error) -> [String: String] {
        let error = error as NSError
        return ["errorDomain": error.domain, "errorCode": String(error.code)]
    }
}

public struct DiagnosticHistory: Codable, Sendable {
    public var events: [DiagnosticEvent]
    public var unreadableRecords: Int
    public var truncatedFiles: Int

    public init(events: [DiagnosticEvent] = [], unreadableRecords: Int = 0, truncatedFiles: Int = 0) {
        self.events = events
        self.unreadableRecords = unreadableRecords
        self.truncatedFiles = truncatedFiles
    }
}

/// Best-effort, rotating JSON-lines journal shared by the app and its extensions.
/// A separate, nonblocking lock avoids waiting for another diagnostic writer or
/// deadlocking a callback delivered while the state/operation lock is held.
public final class DiagnosticLog: @unchecked Sendable {
    public let directory: URL
    public let maximumFileBytes: Int
    public let fileCount: Int

    public init(directory: URL, maximumFileBytes: Int = 128 * 1024, fileCount: Int = 4) throws {
        self.directory = directory
        self.maximumFileBytes = max(1024, maximumFileBytes)
        self.fileCount = max(1, min(8, fileCount))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: directory.path)
        #endif
    }

    @discardableResult
    public func record(_ event: DiagnosticEvent) -> Bool {
        do {
            var bounded = event
            bounded.name = String(event.name.prefix(120))
            bounded.source = String(event.source.prefix(120))
            var data = try Self.encoder().encode(bounded)
            if data.count + 1 > min(16 * 1024, maximumFileBytes) {
                bounded.details = ["detailsOmitted": "Event exceeded the diagnostic size limit."]
                bounded.snapshot = nil
                data = try Self.encoder().encode(bounded)
            }
            data.append(0x0a)
            try withLock {
                let current = fileURL(0)
                let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size + data.count + 1 > maximumFileBytes { try rotate() }
                if !FileManager.default.fileExists(atPath: current.path) {
                    try Data().write(to: current, options: .atomic)
                }
                let file = try FileHandle(forUpdating: current)
                defer { try? file.close() }
                let end = try file.seekToEnd()
                // A killed writer can leave a partial record. Isolate it so the
                // next valid event remains readable instead of being glued to it.
                if end > 0 {
                    try file.seek(toOffset: end - 1)
                    if try file.read(upToCount: 1) != Data([0x0a]) {
                        try file.seekToEnd()
                        try file.write(contentsOf: Data([0x0a]))
                    }
                }
                try file.seekToEnd()
                try file.write(contentsOf: data)
            }
            return true
        } catch {
            // Storage failure, corruption, or contention must never change a rule
            // or prevent a shield/callback from being handled.
            return false
        }
    }

    public func read() throws -> DiagnosticHistory {
        try withLock {
            var history = DiagnosticHistory()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for index in (0..<fileCount).reversed() {
                let url = fileURL(index)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let size = try file.seekToEnd()
                let offset = size > UInt64(maximumFileBytes) ? size - UInt64(maximumFileBytes) : 0
                if offset > 0 { history.truncatedFiles += 1 }
                try file.seek(toOffset: offset)
                let data = try file.read(upToCount: maximumFileBytes) ?? Data()
                for line in data.split(separator: 0x0a) {
                    if let event = try? decoder.decode(DiagnosticEvent.self, from: Data(line)) {
                        history.events.append(event)
                    } else {
                        history.unreadableRecords += 1
                    }
                }
            }
            return history
        }
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func fileURL(_ index: Int) -> URL {
        directory.appendingPathComponent("events-\(index).jsonl")
    }

    private func rotate() throws {
        let manager = FileManager.default
        let oldest = fileURL(fileCount - 1)
        if manager.fileExists(atPath: oldest.path) { try manager.removeItem(at: oldest) }
        if fileCount > 1 {
            for index in (1..<fileCount).reversed() {
                let previous = fileURL(index - 1)
                if manager.fileExists(atPath: previous.path) {
                    try manager.moveItem(at: previous, to: fileURL(index))
                }
            }
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(directory.appendingPathComponent("diagnostics.lock").path,
                              O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw POSIXError(.EWOULDBLOCK) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

public struct DiagnosticProblem: Codable, Sendable {
    public var description: String
    public var occurredAt: Date
    public var selectedUsageShown: String

    public init(description: String, occurredAt: Date, selectedUsageShown: String) {
        self.description = String(description.prefix(4000))
        self.occurredAt = occurredAt
        self.selectedUsageShown = String(selectedUsageShown.prefix(200))
    }
}

public struct DiagnosticReport: Codable, Sendable {
    public var formatVersion = 1
    public var generatedAt: Date
    public var problem: DiagnosticProblem
    public var environment: [String: String]
    public var state: DiagnosticState?
    public var registeredMonitors: [[String: String]] = []
    public var installedShields: [String: String] = [:]
    public var history = DiagnosticHistory()
    public var collectionErrors: [String: [String: String]] = [:]
    public var notes = [
        "History starts when a build with diagnostics is installed; older events cannot be recovered.",
        "History is bounded and best-effort. Old events rotate out; busy or unavailable storage can omit events.",
        "Screen Time usage data stays in Apple's report extension. selectedUsageShown is supplied by the user, not measured by this export.",
        "A threshold callback is an iOS assertion, not independent proof of usage. Compare its uptime with the matching monitor registration.",
        "State and system settings are read separately without changing protection; callbacks may run during collection."
    ]

    public init(generatedAt: Date, problem: DiagnosticProblem, environment: [String: String], state: DiagnosticState?) {
        self.generatedAt = generatedAt
        self.problem = problem
        self.environment = environment
        self.state = state
    }

    public func encoded() throws -> Data {
        let encoder = DiagnosticLog.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        return try encoder.encode(self)
    }
}

extension ProtectionSnapshot {
    /// Explains existing acceptance rules without participating in enforcement.
    public func diagnosticThresholdResult(activity: String, event: String?, at now: Date) -> String {
        guard let event else { return "not_a_threshold" }
        guard event == MonitorSpec.limitEvent else { return "unexpected_event" }
        guard !policy.selection.isEmpty else { return "no_selection" }
        guard policy.dailyLimitMinutes != nil else { return "no_allowance" }
        guard let cycle = cycles.first(where: { activity == MonitorSpec.budgetName(generation: generation, cycle: $0.id) })
        else { return "unrecognized_generation_or_cycle" }
        guard cycle.start <= now, now < cycle.end else { return "outside_cycle" }
        return reachedCycles.contains(cycle.id) ? "already_exhausted" : "accepted"
    }
}

extension MonitorSpec {
    public var diagnosticDetails: [String: String] {
        var fields = ["activity": name]
        switch kind {
        case .midnight(let zone):
            fields["kind"] = "midnight"
            fields["timeZone"] = zone
        case .window(let window, let zone):
            fields["kind"] = "window"
            fields["startMinute"] = String(window.startMinute)
            fields["endMinute"] = String(window.endMinute)
            fields["timeZone"] = zone
        case .budget(let cycle, let selection, let minutes):
            fields["kind"] = "budget"
            fields["cycleID"] = cycle.id.uuidString
            fields["startEpochSeconds"] = String(cycle.start.timeIntervalSince1970)
            fields["endEpochSeconds"] = String(cycle.end.timeIntervalSince1970)
            fields["timeZone"] = cycle.timeZoneIdentifier
            fields["thresholdMinutes"] = String(minutes)
            fields["applications"] = String(selection.applications.count)
            fields["categories"] = String(selection.categories.count)
            fields["webDomains"] = String(selection.webDomains.count)
        }
        return fields
    }
}
