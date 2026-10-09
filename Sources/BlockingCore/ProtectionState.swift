import Foundation

public struct BudgetCycle: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var timeZoneIdentifier: String

    public init(containing date: Date, calendar: Calendar) {
        id = UUID()
        start = calendar.startOfDay(for: date)
        end = calendar.date(byAdding: .day, value: 1, to: start)!
        timeZoneIdentifier = calendar.timeZone.identifier
    }
}

public struct PendingLimit: Codable, Equatable, Sendable {
    public var minutes: Int?
    public var effectiveAfter: Date
}

public struct PendingWindows: Codable, Equatable, Sendable {
    public var windows: [BlockWindow]
    public var effectiveAfter: Date
}

public struct PendingApplications: Codable, Equatable, Sendable {
    public var applications: [Data]
    public var effectiveAfter: Date

    private enum CodingKeys: String, CodingKey { case applications, application, effectiveAfter }

    public init(applications: [Data], effectiveAfter: Date) {
        self.applications = BlockingPolicy.normalized(applications)
        self.effectiveAfter = effectiveAfter
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.applications) {
            applications = try values.decode([Data].self, forKey: .applications)
        } else {
            applications = try values.decodeIfPresent(Data.self, forKey: .application).map { [$0] } ?? []
        }
        applications = BlockingPolicy.normalized(applications)
        effectiveAfter = try values.decode(Date.self, forKey: .effectiveAfter)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(applications, forKey: .applications)
        try values.encode(effectiveAfter, forKey: .effectiveAfter)
    }
}

public struct ProtectionSnapshot: Codable, Equatable, Sendable {
    public var generation: UUID = UUID()
    public var policy: BlockingPolicy = BlockingPolicy()
    public var cycles: [BudgetCycle] = []
    public var reachedCycles: Set<UUID> = []
    public var scheduleTimeZoneIdentifier: String = TimeZone.current.identifier
    public var pendingLimit: PendingLimit?
    public var pendingApplications: PendingApplications?
    public var pendingWindows: PendingWindows?

    public var hasPendingChanges: Bool {
        pendingLimit != nil || pendingApplications != nil || pendingWindows != nil
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case generation, policy, cycles, reachedCycles, scheduleTimeZoneIdentifier
        case pendingLimit, pendingApplications, pendingApplication, pendingWindows
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generation = try values.decode(UUID.self, forKey: .generation)
        policy = try values.decode(BlockingPolicy.self, forKey: .policy)
        cycles = try values.decode([BudgetCycle].self, forKey: .cycles)
        reachedCycles = try values.decode(Set<UUID>.self, forKey: .reachedCycles)
        scheduleTimeZoneIdentifier = try values.decode(String.self, forKey: .scheduleTimeZoneIdentifier)
        pendingLimit = try values.decodeIfPresent(PendingLimit.self, forKey: .pendingLimit)
        pendingWindows = try values.decodeIfPresent(PendingWindows.self, forKey: .pendingWindows)
        pendingApplications = try values.decodeIfPresent(PendingApplications.self, forKey: .pendingApplications)
            ?? values.decodeIfPresent(PendingApplications.self, forKey: .pendingApplication)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(generation, forKey: .generation)
        try values.encode(policy, forKey: .policy)
        try values.encode(cycles, forKey: .cycles)
        try values.encode(reachedCycles, forKey: .reachedCycles)
        try values.encode(scheduleTimeZoneIdentifier, forKey: .scheduleTimeZoneIdentifier)
        try values.encodeIfPresent(pendingLimit, forKey: .pendingLimit)
        try values.encodeIfPresent(pendingWindows, forKey: .pendingWindows)
        try values.encodeIfPresent(pendingApplications, forKey: .pendingApplications)
    }

    public func currentCycle(at now: Date) -> BudgetCycle? {
        // A backward clock change must not erase an already exhausted allowance.
        cycles.first { now < $0.end }
    }

    public mutating func advance(to now: Date, calendar: Calendar) {
        let crossedBoundary = cycles.contains { $0.end <= now }
        scheduleTimeZoneIdentifier = calendar.timeZone.identifier
        cycles.removeAll { $0.end <= now }
        if crossedBoundary, let remaining = cycles.first,
           remaining.timeZoneIdentifier != calendar.timeZone.identifier {
            // Keep the current allowance pinned through its original reset. At that
            // boundary adopt the local calendar and let iOS include local-day past usage.
            cycles.removeAll()
        }
        if cycles.isEmpty { cycles = [BudgetCycle(containing: now, calendar: calendar)] }
        while cycles.count < 2 {
            var pinnedCalendar = calendar
            pinnedCalendar.timeZone = TimeZone(identifier: cycles.last!.timeZoneIdentifier) ?? calendar.timeZone
            cycles.append(BudgetCycle(containing: cycles.last!.end, calendar: pinnedCalendar))
        }
        reachedCycles.formIntersection(Set(cycles.map(\.id)))
        if let pending = pendingLimit, now >= pending.effectiveAfter {
            policy.dailyLimitMinutes = pending.minutes
            reachedCycles.removeAll()
            pendingLimit = nil
        }
        if let pending = pendingApplications, now >= pending.effectiveAfter {
            policy.applications = pending.applications
            reachedCycles.removeAll()
            pendingApplications = nil
        }
        if let pending = pendingWindows, now >= pending.effectiveAfter {
            policy.windows = pending.windows
            pendingWindows = nil
        }
    }

    public mutating func apply(_ edit: RuleEdit, at now: Date, calendar: Calendar) throws {
        advance(to: now, calendar: calendar)
        if case .cancelPending = edit {
            pendingLimit = nil
            pendingApplications = nil
            pendingWindows = nil
            return
        }
        let tomorrow = currentCycle(at: now)!.end
        switch edit {
        case .windows(let windows):
            var candidate = policy
            candidate.windows = windows
            try candidate.validate()
            if policy.applications.isEmpty || candidate.coversSchedule(policy.windows) {
                policy = candidate
                pendingWindows = nil
            } else {
                // Finish any occurrence already spanning the next reset. Unlike a
                // recurring "is active" guard, this fixed date also handles 24h coverage.
                pendingWindows = PendingWindows(windows: windows, effectiveAfter: deferredScheduleDate(after: tomorrow, calendar: calendar))
            }
        case .limit(let minutes):
            var candidate = policy
            candidate.dailyLimitMinutes = minutes
            try candidate.validate()
            if minutes == policy.dailyLimitMinutes {
                pendingLimit = nil
            } else if policy.applications.isEmpty || (minutes ?? Int.max) < (policy.dailyLimitMinutes ?? Int.max) {
                policy.dailyLimitMinutes = minutes
                pendingLimit = nil
            } else {
                pendingLimit = PendingLimit(minutes: minutes, effectiveAfter: tomorrow)
            }
        case .applications(let applications):
            let normalized = BlockingPolicy.normalized(applications)
            guard normalized.allSatisfy({ !$0.isEmpty }) else { throw RuleError.invalidApplications }
            if normalized == policy.applications {
                pendingApplications = nil
            } else if policy.applications.isEmpty {
                policy.applications = normalized
                reachedCycles.removeAll()
            } else if Set(normalized).isSuperset(of: Set(policy.applications)) {
                // Adding apps cannot weaken protection. Keep an exhausted allowance
                // exhausted for the entire enlarged selection, including the new apps.
                policy.applications = normalized
                pendingApplications = nil
            } else {
                // A replacement can add and remove apps at once. Protect additions
                // now; retain all existing apps until the queued removal applies.
                policy.applications = BlockingPolicy.normalized(policy.applications + normalized)
                pendingApplications = PendingApplications(applications: normalized,
                    effectiveAfter: deferredScheduleDate(after: tomorrow, calendar: calendar))
            }
        case .cancelPending: break
        }
    }

    private func deferredScheduleDate(after reset: Date, calendar: Calendar) -> Date {
        // Capture a fixed deadline: a recurring active-schedule guard could defer
        // changes forever when windows cover the entire day.
        var effectiveAfter = reset
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: reset) else { continue }
            for window in policy.windows {
                if let interval = window.interval(startingOn: day, calendar: calendar),
                   interval.start < reset && interval.end > reset {
                    effectiveAfter = max(effectiveAfter, interval.end)
                }
            }
        }
        return effectiveAfter
    }

    public func decision(at now: Date, calendar: Calendar) -> ShieldDecision {
        let cycle = currentCycle(at: now)
        return ShieldDecision(
            applications: policy.applications,
            scheduled: policy.scheduleIsActive(at: now, calendar: calendar),
            budgetExhausted: !policy.applications.isEmpty && policy.dailyLimitMinutes != nil && cycle.map { reachedCycles.contains($0.id) } == true,
            nextScheduleTransition: policy.nextScheduleTransition(after: now, calendar: calendar),
            budgetResetsAt: cycle?.end
        )
    }

    public mutating func receiveThreshold(activity: String, event: String, at now: Date) {
        guard event == MonitorSpec.limitEvent, !policy.applications.isEmpty, policy.dailyLimitMinutes != nil else { return }
        for cycle in cycles where activity == MonitorSpec.budgetName(generation: generation, cycle: cycle.id) {
            guard cycle.start <= now && now < cycle.end else { continue }
            reachedCycles.insert(cycle.id)
        }
    }
}

public enum RuleEdit: Sendable {
    case windows([BlockWindow])
    case limit(Int?)
    case applications([Data])
    case cancelPending
}

public struct ShieldDecision: Equatable, Sendable {
    public var applications: [Data]
    public var scheduled: Bool
    public var budgetExhausted: Bool
    public var nextScheduleTransition: Date?
    public var budgetResetsAt: Date?
    public var isBlocked: Bool { scheduled || budgetExhausted }
}

public struct ProtectionDocument: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var active = ProtectionSnapshot()
    public var staged: ProtectionSnapshot?
    public var lastError: String?
    public var lastCallbackAt: Date?
    public init() {}
}

public struct MonitorSpec: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case midnight(timeZoneIdentifier: String)
        case window(BlockWindow, timeZoneIdentifier: String)
        case budget(BudgetCycle, applications: [Data], minutes: Int)
    }
    public var name: String
    public var kind: Kind
    public static let prefix = "instablock."
    public static let midnightName = prefix + "midnight"
    public static let limitEvent = "daily-limit"

    public static func budgetName(generation: UUID, cycle: UUID) -> String {
        prefix + "budget." + generation.uuidString + "." + cycle.uuidString
    }

    public static func plan(for snapshot: ProtectionSnapshot) -> [MonitorSpec] {
        let applications = snapshot.policy.applications
        guard !applications.isEmpty else { return [] }
        guard !snapshot.policy.windows.isEmpty || snapshot.policy.dailyLimitMinutes != nil
                || snapshot.hasPendingChanges else { return [] }
        var specs = [MonitorSpec(name: midnightName + "." + snapshot.generation.uuidString,
                                 kind: .midnight(timeZoneIdentifier: snapshot.scheduleTimeZoneIdentifier))]
        specs += snapshot.policy.windows.map {
            MonitorSpec(name: prefix + "window." + snapshot.generation.uuidString + "." + $0.id.uuidString,
                        kind: .window($0, timeZoneIdentifier: snapshot.scheduleTimeZoneIdentifier))
        }
        if let minutes = snapshot.policy.dailyLimitMinutes {
            specs += snapshot.cycles.map {
                MonitorSpec(name: budgetName(generation: snapshot.generation, cycle: $0.id),
                            kind: .budget($0, applications: applications, minutes: minutes))
            }
        }
        return specs
    }
}
