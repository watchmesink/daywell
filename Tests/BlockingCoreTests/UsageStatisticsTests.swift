import BlockingCore
import Foundation
import XCTest

final class UsageStatisticsTests: XCTestCase {
    private let now = date("2026-10-18 16:00:00")

    func testComparesTodayWithSevenCompleteDaysAndExcludesTodayFromAverage() throws {
        var days = previousDays(duration: 60 * 60)
        days[calendar().startOfDay(for: now)] = 30 * 60
        days[date("2026-10-10 00:00:00")] = 99 * 60 * 60

        let summary = UsageStatistics(dailyDurations: days, now: now, calendar: calendar())

        XCTAssertEqual(summary.todayDuration, 30 * 60)
        XCTAssertEqual(summary.previousSevenDaysAverage, 60 * 60)
        XCTAssertEqual(try XCTUnwrap(summary.percentageChange), -50, accuracy: 0.001)
    }

    func testIncreaseProducesPositivePercentage() throws {
        var days = previousDays(duration: 60 * 60)
        days[calendar().startOfDay(for: now)] = 90 * 60
        let summary = UsageStatistics(dailyDurations: days, now: now, calendar: calendar())
        XCTAssertEqual(try XCTUnwrap(summary.percentageChange), 50, accuracy: 0.001)
    }

    func testMissingDayDoesNotBecomeZeroOrProducePartialWeekAverage() {
        var days = previousDays(duration: 60 * 60)
        days.removeValue(forKey: date("2026-10-15 00:00:00"))
        days[calendar().startOfDay(for: now)] = 30 * 60
        let summary = UsageStatistics(dailyDurations: days, now: now, calendar: calendar())
        XCTAssertNil(summary.previousSevenDaysAverage)
        XCTAssertNil(summary.percentageChange)
    }

    func testAnExplicitZeroUsageDayCountsInAverage() throws {
        var days = previousDays(duration: 70 * 60)
        days[date("2026-10-15 00:00:00")] = 0
        days[calendar().startOfDay(for: now)] = 30 * 60
        let summary = UsageStatistics(dailyDurations: days, now: now, calendar: calendar())
        XCTAssertEqual(summary.previousSevenDaysAverage, 60 * 60)
        XCTAssertEqual(try XCTUnwrap(summary.percentageChange), -50, accuracy: 0.001)
    }

    func testMissingTodayIsUnavailableRatherThanZero() {
        let summary = UsageStatistics(dailyDurations: previousDays(duration: 60 * 60), now: now, calendar: calendar())
        XCTAssertNil(summary.todayDuration)
        XCTAssertNil(summary.percentageChange)
    }

    func testZeroBaselineNeverProducesInfinity() {
        var days = previousDays(duration: 0)
        days[calendar().startOfDay(for: now)] = 30 * 60
        XCTAssertNil(UsageStatistics(dailyDurations: days, now: now, calendar: calendar()).percentageChange)

        days[calendar().startOfDay(for: now)] = 0
        XCTAssertEqual(UsageStatistics(dailyDurations: days, now: now, calendar: calendar()).percentageChange, 0)
    }

    func testNoDataIsUnavailable() {
        let summary = UsageStatistics(dailyDurations: [:], now: now, calendar: calendar())
        XCTAssertNil(summary.todayDuration)
        XCTAssertNil(summary.previousSevenDaysAverage)
        XCTAssertNil(summary.percentageChange)
    }

    func testHistoryUsesCalendarDaysAcrossDaylightSavingBoundary() throws {
        let now = date("2026-10-28 16:00:00")
        var days: [Date: TimeInterval] = [:]
        for day in 21...27 {
            days[date("2026-10-\(day) 00:00:00")] = 60 * 60
        }
        days[date("2026-10-28 00:00:00")] = 45 * 60
        let summary = UsageStatistics(dailyDurations: days, now: now, calendar: calendar())
        XCTAssertEqual(summary.previousSevenDaysAverage, 60 * 60)
        XCTAssertEqual(try XCTUnwrap(summary.percentageChange), -25, accuracy: 0.001)
    }

    private func previousDays(duration: TimeInterval) -> [Date: TimeInterval] {
        Dictionary(uniqueKeysWithValues: (11...17).map { (date("2026-10-\($0) 00:00:00"), duration) })
    }
}
