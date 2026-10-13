import Foundation

public struct BlockWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startMinute: Int
    public var endMinute: Int

    public init(id: UUID = UUID(), startMinute: Int, endMinute: Int) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public var durationMinutes: Int { (endMinute - startMinute + 1440) % 1440 }

    public func interval(startingOn date: Date, calendar: Calendar) -> DateInterval? {
        let day = calendar.startOfDay(for: date)
        guard let endDay = calendar.date(byAdding: .day, value: endMinute <= startMinute ? 1 : 0, to: day),
              let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60,
                                        second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60,
                                      second: 0, of: endDay, matchingPolicy: .nextTime, repeatedTimePolicy: .last),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

public struct BlockingPolicy: Codable, Equatable, Sendable {
    public static let defaultDailyLimitMinutes = 30
    public var selection: BlockingSelection
    public var windows: [BlockWindow]
    public var dailyLimitMinutes: Int?

    public init(applications: [Data] = [], categories: [Data] = [], webDomains: [Data] = [],
                windows: [BlockWindow] = [],
                dailyLimitMinutes: Int? = BlockingPolicy.defaultDailyLimitMinutes) {
        selection = BlockingSelection(applications: applications, categories: categories, webDomains: webDomains)
        self.windows = windows
        self.dailyLimitMinutes = dailyLimitMinutes
    }

    private enum CodingKeys: String, CodingKey { case windows, dailyLimitMinutes }

    public init(from decoder: Decoder) throws {
        selection = try BlockingSelection(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        windows = try values.decode([BlockWindow].self, forKey: .windows)
        dailyLimitMinutes = try values.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
    }

    public func encode(to encoder: Encoder) throws {
        try selection.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(windows, forKey: .windows)
        try values.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
    }

    // Seven windows + two budget monitors, with room to install a replacement generation
    // before removing the previous one (plus a midnight monitor per generation).
    public static let maximumWindows = 7

    /// Compare the union of daily windows, including overlaps and midnight wraps.
    /// More blocked minutes means less available time and can apply immediately.
    public func coversSchedule(_ previous: [BlockWindow]) -> Bool {
        func minutes(in windows: [BlockWindow]) -> Set<Int> {
            Set(windows.flatMap { window in
                (0..<window.durationMinutes).map { (window.startMinute + $0) % 1440 }
            })
        }
        return minutes(in: previous).isSubset(of: minutes(in: windows))
    }

    public func validate() throws {
        try selection.validate()
        guard windows.count <= Self.maximumWindows else { throw RuleError.tooManyWindows }
        guard Set(windows.map(\.id)).count == windows.count else { throw RuleError.invalidWindow }
        for window in windows {
            guard (0..<1440).contains(window.startMinute), (0..<1440).contains(window.endMinute),
                  window.durationMinutes >= 15 else { throw RuleError.invalidWindow }
        }
        if let limit = dailyLimitMinutes, !(1...1440).contains(limit) { throw RuleError.invalidLimit }
    }

    public func scheduleIsActive(at now: Date, calendar: Calendar) -> Bool {
        guard !selection.isEmpty else { return false }
        return windows.contains { window in
            [-1, 0].contains { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      let interval = window.interval(startingOn: day, calendar: calendar) else { return false }
                return interval.start <= now && now < interval.end
            }
        }
    }

    public func nextScheduleTransition(after now: Date, calendar: Calendar) -> Date? {
        guard !selection.isEmpty else { return nil }
        let active = scheduleIsActive(at: now, calendar: calendar)
        var boundaries = Set<Date>()
        for offset in -1...3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for window in windows {
                if let interval = window.interval(startingOn: day, calendar: calendar) {
                    boundaries.insert(interval.start)
                    boundaries.insert(interval.end)
                }
            }
        }
        return boundaries.sorted().first { $0 > now && scheduleIsActive(at: $0, calendar: calendar) != active }
    }
}

public enum RuleError: LocalizedError, Equatable {
    case invalidSelection, tooManySelections, invalidWindow, invalidLimit, tooManyWindows, busy, unsupportedSchema

    public var errorDescription: String? {
        switch self {
        case .invalidSelection: return "Choose valid apps, categories, or websites."
        case .tooManySelections: return "You can protect up to 50 apps, 50 categories, and 50 websites at once. Pending removals still count until they take effect."
        case .invalidWindow: return "Choose different start and end times, at least 15 minutes apart. Overnight blocks are supported."
        case .invalidLimit: return "Choose a daily allowance from 1 to 1,440 minutes."
        case .tooManyWindows: return "You can use up to seven daily windows. This leaves room for iOS to update monitors safely."
        case .busy: return "Protection is being updated. Please try again in a moment."
        case .unsupportedSchema: return "This saved configuration needs a newer version of Daywell. Existing restrictions have been retained."
        }
    }
}
