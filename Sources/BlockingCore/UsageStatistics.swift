import Foundation

/// Usage stays inside the Screen Time report extension. This value only calculates
/// a daily comparison from the durations that Screen Time actually returned.
public struct UsageStatistics: Equatable, Sendable {
    public let todayDuration: TimeInterval?
    public let previousSevenDaysAverage: TimeInterval?

    public init(dailyDurations: [Date: TimeInterval], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        todayDuration = dailyDurations[today]

        let previousDays = (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let previousDurations = previousDays.compactMap { dailyDurations[$0] }
        // An absent daily segment is unknown, rather than a fabricated zero.
        previousSevenDaysAverage = previousDurations.count == 7
            ? previousDurations.reduce(0, +) / 7
            : nil
    }

    /// A zero baseline has no percentage change unless today is also zero.
    public var percentageChange: Double? {
        guard let todayDuration, let previousSevenDaysAverage else { return nil }
        guard previousSevenDaysAverage > 0 else { return todayDuration == 0 ? 0 : nil }
        return (todayDuration / previousSevenDaysAverage - 1) * 100
    }
}
