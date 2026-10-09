import BlockingCore
import Foundation
import XCTest

func calendar(_ zone: String = "Europe/Amsterdam") -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: zone)!
    return value
}

func date(_ value: String, zone: String = "Europe/Amsterdam") -> Date {
    let formatter = DateFormatter()
    formatter.calendar = calendar(zone)
    formatter.timeZone = formatter.calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: value)!
}

let selectedApp = Data("opaque-app-token".utf8)
let anotherApp = Data("opaque-other-token".utf8)

func activeSnapshot(at now: Date = date("2026-10-08 14:00:00")) -> ProtectionSnapshot {
    var value = ProtectionSnapshot()
    value.policy.applications = [selectedApp]
    value.advance(to: now, calendar: calendar())
    return value
}

final class RulesTests: XCTestCase {
    func testDefaultWindowsAreStartInclusiveAndEndExclusive() {
        let policy = BlockingPolicy(applications: [selectedApp])
        for (time, blocked) in [("05:59:59", false), ("06:00:00", true), ("09:59:59", true),
                                ("10:00:00", false), ("21:59:59", false), ("22:00:00", true),
                                ("23:59:59", true), ("00:00:00", false)] {
            XCTAssertEqual(policy.scheduleIsActive(at: date("2026-10-08 \(time)"), calendar: calendar()), blocked, time)
        }
    }

    func testNoSelectionDoesNotLockOnboarding() {
        let policy = BlockingPolicy()
        XCTAssertFalse(policy.scheduleIsActive(at: date("2026-10-08 07:00:00"), calendar: calendar()))
    }

    func testMultipleAppsShareTheSameScheduleAndBudgetMonitor() throws {
        let now = date("2026-10-08 14:00:00")
        var state = ProtectionSnapshot()
        try state.apply(.applications([anotherApp, selectedApp, selectedApp]), at: now, calendar: calendar())
        XCTAssertEqual(Set(state.policy.applications), Set([selectedApp, anotherApp]))
        XCTAssertEqual(state.policy.applications.count, 2)
        XCTAssertTrue(state.decision(at: date("2026-10-08 07:00:00"), calendar: calendar()).scheduled)
        let budgets = MonitorSpec.plan(for: state).compactMap { spec -> [Data]? in
            if case .budget(_, let applications, _) = spec.kind { return applications }
            return nil
        }
        XCTAssertEqual(budgets.count, 2)
        XCTAssertTrue(budgets.allSatisfy { Set($0) == Set([selectedApp, anotherApp]) })
        state.receiveThreshold(activity: MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[0].id),
                               event: MonitorSpec.limitEvent, at: now)
        let decision = state.decision(at: now, calendar: calendar())
        XCTAssertTrue(decision.budgetExhausted)
        XCTAssertEqual(Set(decision.applications), Set([selectedApp, anotherApp]))
    }

    func testOvernightWindowIncludesPreviousDaysOccurrence() {
        let policy = BlockingPolicy(applications: [selectedApp], windows: [.init(startMinute: 23 * 60, endMinute: 7 * 60)])
        XCTAssertTrue(policy.scheduleIsActive(at: date("2026-10-09 03:00:00"), calendar: calendar()))
        XCTAssertFalse(policy.scheduleIsActive(at: date("2026-10-09 07:00:00"), calendar: calendar()))
        XCTAssertEqual(policy.nextScheduleTransition(after: date("2026-10-09 03:00:00"), calendar: calendar()), date("2026-10-09 07:00:00"))
    }

    func testOverlappingAndAdjacentWindowsDoNotSuggestAnEarlyUnblock() {
        let policy = BlockingPolicy(applications: [selectedApp], windows: [
            .init(startMinute: 360, endMinute: 600), .init(startMinute: 540, endMinute: 660),
            .init(startMinute: 660, endMinute: 720)
        ])
        XCTAssertEqual(policy.nextScheduleTransition(after: date("2026-10-08 07:00:00"), calendar: calendar()), date("2026-10-08 12:00:00"))
    }

    func testFullDayUnionHasNoFalseUnblockTime() {
        let policy = BlockingPolicy(applications: [selectedApp], windows: [
            .init(startMinute: 0, endMinute: 720), .init(startMinute: 720, endMinute: 0)
        ])
        XCTAssertNil(policy.nextScheduleTransition(after: date("2026-10-08 07:00:00"), calendar: calendar()))
    }

    func testValidationHonorsPlatformIntervalsAndLimitRange() throws {
        for window in [BlockWindow(startMinute: 1, endMinute: 1), .init(startMinute: 0, endMinute: 14),
                       .init(startMinute: -1, endMinute: 60), .init(startMinute: 0, endMinute: 1440)] {
            XCTAssertThrowsError(try BlockingPolicy(windows: [window]).validate())
        }
        try BlockingPolicy(windows: [.init(startMinute: 1430, endMinute: 5)]).validate()
        XCTAssertThrowsError(try BlockingPolicy(dailyLimitMinutes: 0).validate())
        XCTAssertThrowsError(try BlockingPolicy(dailyLimitMinutes: 1441).validate())
        try BlockingPolicy(dailyLimitMinutes: nil).validate()
    }

    func testSpringDSTUsesCalendarDayRatherThanTwentyFourHours() {
        let cycle = BudgetCycle(containing: date("2026-03-29 12:00:00"), calendar: calendar())
        XCTAssertEqual(cycle.end.timeIntervalSince(cycle.start), 23 * 3600)
        let policy = BlockingPolicy(applications: [selectedApp])
        XCTAssertTrue(policy.scheduleIsActive(at: date("2026-03-29 06:00:00"), calendar: calendar()))
        XCTAssertFalse(policy.scheduleIsActive(at: date("2026-03-29 10:00:00"), calendar: calendar()))
    }

    func testFallDSTIncludesRepeatedHourAndTwentyFiveHourDay() {
        let cycle = BudgetCycle(containing: date("2026-10-25 12:00:00"), calendar: calendar())
        XCTAssertEqual(cycle.end.timeIntervalSince(cycle.start), 25 * 3600)
        let window = BlockWindow(startMinute: 2 * 60, endMinute: 3 * 60)
        let interval = window.interval(startingOn: cycle.start, calendar: calendar())!
        XCTAssertEqual(interval.duration, 2 * 3600)
    }

    func testMissingDSTHourMovesToNextValidTime() {
        let window = BlockWindow(startMinute: 2 * 60 + 30, endMinute: 4 * 60)
        let interval = window.interval(startingOn: date("2026-03-29 00:00:00"), calendar: calendar())!
        XCTAssertEqual(interval.start, date("2026-03-29 03:00:00"))
        XCTAssertEqual(interval.end, date("2026-03-29 04:00:00"))
    }
}

final class EditTests: XCTestCase {
    func testActiveScheduleAcceptsEditsWithoutWeakeningTodaysProtection() throws {
        let now = date("2026-10-08 07:00:00")
        for edit in [RuleEdit.windows([]), .applications([]), .applications([anotherApp]), .limit(60), .limit(nil)] {
            var state = activeSnapshot(at: now)
            try state.apply(edit, at: now, calendar: calendar())
            XCTAssertTrue(state.hasPendingChanges)
            XCTAssertTrue(state.policy.applications.contains(selectedApp))
            XCTAssertEqual(state.policy.windows, BlockWindow.defaults)
            XCTAssertEqual(state.policy.dailyLimitMinutes, 30)
            XCTAssertTrue(state.decision(at: now, calendar: calendar()).scheduled)
        }
        var state = activeSnapshot(at: now)
        try state.apply(.limit(10), at: now, calendar: calendar())
        XCTAssertEqual(state.policy.dailyLimitMinutes, 10)
        XCTAssertFalse(state.hasPendingChanges)
    }

    func testScheduleRemovalQueuesEvenOutsideActiveWindow() throws {
        var state = activeSnapshot()
        try state.apply(.windows([]), at: date("2026-10-08 10:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.windows, BlockWindow.defaults)
        XCTAssertEqual(state.pendingWindows?.effectiveAfter, date("2026-10-09 00:00:00"))
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertTrue(state.policy.windows.isEmpty)
        XCTAssertNil(state.pendingWindows)
    }

    func testInitialActivationDuringMorningAllowsQueuedRemoval() throws {
        var state = ProtectionSnapshot()
        let now = date("2026-10-08 08:00:00")
        try state.apply(.applications([selectedApp]), at: now, calendar: calendar())
        XCTAssertTrue(state.decision(at: now, calendar: calendar()).scheduled)
        try state.apply(.applications([]), at: now, calendar: calendar())
        XCTAssertEqual(state.policy.applications, [selectedApp])
        XCTAssertEqual(state.pendingApplications?.applications, [])
    }

    func testAllowanceIncreaseQueuesWithoutClearingExhaustion() throws {
        let now = date("2026-10-08 14:00:00")
        var state = activeSnapshot(at: now)
        state.reachedCycles.insert(state.cycles[0].id)
        try state.apply(.limit(60), at: now, calendar: calendar())
        XCTAssertEqual(state.policy.dailyLimitMinutes, 30)
        XCTAssertEqual(state.pendingLimit?.effectiveAfter, date("2026-10-09 00:00:00"))
        XCTAssertTrue(state.decision(at: now, calendar: calendar()).budgetExhausted)
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.dailyLimitMinutes, 60)
        XCTAssertNil(state.pendingLimit)
        XCTAssertFalse(state.decision(at: date("2026-10-09 00:00:00"), calendar: calendar()).budgetExhausted)
    }

    func testRemovingAllowanceQueuesRatherThanDisablingToday() throws {
        var state = activeSnapshot()
        try state.apply(.limit(nil), at: date("2026-10-08 14:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.dailyLimitMinutes, 30)
        XCTAssertNotNil(state.pendingLimit)
        XCTAssertNil(state.pendingLimit?.minutes)
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertNil(state.policy.dailyLimitMinutes)
    }

    func testLowerAllowancePreservesPreviouslyExhaustedDay() throws {
        var state = activeSnapshot()
        state.reachedCycles.insert(state.cycles[0].id)
        try state.apply(.limit(10), at: date("2026-10-08 14:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.dailyLimitMinutes, 10)
        XCTAssertTrue(state.decision(at: date("2026-10-08 14:00:00"), calendar: calendar()).budgetExhausted)
    }

    func testAppReplacementWaitsThroughAnOvernightBlock() throws {
        var state = activeSnapshot()
        state.policy.windows = [.init(startMinute: 22 * 60, endMinute: 7 * 60)]
        try state.apply(.applications([anotherApp]), at: date("2026-10-08 14:00:00"), calendar: calendar())
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertEqual(Set(state.policy.applications), Set([selectedApp, anotherApp]))
        XCTAssertEqual(state.pendingApplications?.effectiveAfter, date("2026-10-09 07:00:00"))
        state.advance(to: date("2026-10-09 07:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.applications, [anotherApp])
        XCTAssertNil(state.pendingApplications)
    }

    func testAddingAppsAppliesDuringBlockAndPreservesTodaysExhaustion() throws {
        let now = date("2026-10-08 07:00:00")
        var state = activeSnapshot(at: now)
        state.reachedCycles.insert(state.cycles[0].id)
        try state.apply(.applications([anotherApp, selectedApp]), at: now, calendar: calendar())
        XCTAssertEqual(Set(state.policy.applications), Set([selectedApp, anotherApp]))
        XCTAssertNil(state.pendingApplications)
        XCTAssertTrue(state.decision(at: now, calendar: calendar()).budgetExhausted)
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertEqual(Set(state.policy.applications), Set([selectedApp, anotherApp]))
        XCTAssertFalse(state.decision(at: date("2026-10-09 00:00:00"), calendar: calendar()).budgetExhausted)
    }

    func testMidnightAllowanceChangeCannotRemoveOvernightShield() throws {
        var state = activeSnapshot()
        state.policy.windows = [.init(startMinute: 22 * 60, endMinute: 7 * 60)]
        try state.apply(.limit(60), at: date("2026-10-08 14:00:00"), calendar: calendar())
        let midnight = date("2026-10-09 00:00:00")
        state.advance(to: midnight, calendar: calendar())
        XCTAssertTrue(state.decision(at: midnight, calendar: calendar()).scheduled)
        XCTAssertEqual(state.policy.dailyLimitMinutes, 60)
    }

    func testCancellingPendingChangesOnlyPreservesCurrentRules() throws {
        var state = activeSnapshot()
        try state.apply(.limit(90), at: date("2026-10-08 14:00:00"), calendar: calendar())
        try state.apply(.windows([]), at: date("2026-10-08 14:00:00"), calendar: calendar())
        try state.apply(.applications([]), at: date("2026-10-08 14:00:00"), calendar: calendar())
        try state.apply(.cancelPending, at: date("2026-10-08 22:30:00"), calendar: calendar())
        XCTAssertFalse(state.hasPendingChanges)
        XCTAssertEqual(state.policy.windows, BlockWindow.defaults)
        XCTAssertEqual(state.policy.applications, [selectedApp])
        XCTAssertEqual(state.policy.dailyLimitMinutes, 30)
        XCTAssertTrue(state.decision(at: date("2026-10-08 22:30:00"), calendar: calendar()).scheduled)
    }

    func testDuplicateAndStaleThresholdsCannotAffectDifferentDayOrGeneration() {
        var state = activeSnapshot()
        let now = date("2026-10-08 14:00:00")
        let current = MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[0].id)
        state.receiveThreshold(activity: current, event: MonitorSpec.limitEvent, at: now)
        state.receiveThreshold(activity: current, event: MonitorSpec.limitEvent, at: now)
        XCTAssertEqual(state.reachedCycles.count, 1)
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        state.receiveThreshold(activity: current, event: MonitorSpec.limitEvent, at: date("2026-10-09 00:00:01"))
        let stale = MonitorSpec.budgetName(generation: UUID(), cycle: state.cycles[0].id)
        state.receiveThreshold(activity: stale, event: MonitorSpec.limitEvent, at: date("2026-10-09 00:00:01"))
        XCTAssertTrue(state.reachedCycles.isEmpty)
    }

    func testFutureAndUnknownEventsDoNotConsumeAllowance() {
        var state = activeSnapshot()
        let now = date("2026-10-08 14:00:00")
        state.receiveThreshold(activity: MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[1].id), event: MonitorSpec.limitEvent, at: now)
        state.receiveThreshold(activity: MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[0].id), event: "unknown", at: now)
        XCTAssertTrue(state.reachedCycles.isEmpty)
    }

    func testBackwardClockOrTimezoneChangeDoesNotResetCurrentAllowance() {
        var state = activeSnapshot()
        let cycle = state.cycles[0]
        state.reachedCycles.insert(cycle.id)
        state.advance(to: date("2026-10-08 13:00:00"), calendar: calendar("America/New_York"))
        XCTAssertEqual(state.cycles[0], cycle)
        XCTAssertTrue(state.decision(at: date("2026-10-08 13:00:00"), calendar: calendar()).budgetExhausted)
        XCTAssertTrue(state.decision(at: date("2026-10-07 13:00:00"), calendar: calendar()).budgetExhausted)
    }

    func testTimezoneAdoptsLocalCalendarOnlyAfterExistingBudgetBoundary() {
        var state = activeSnapshot()
        let original = state.cycles[0]
        state.advance(to: date("2026-10-08 15:00:00"), calendar: calendar("America/New_York"))
        XCTAssertEqual(state.cycles[0], original)
        XCTAssertEqual(state.scheduleTimeZoneIdentifier, "America/New_York")
        state.advance(to: original.end, calendar: calendar("America/New_York"))
        XCTAssertEqual(state.cycles[0].timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(state.cycles[0].start, date("2026-10-08 00:00:00", zone: "America/New_York"))
    }
}
