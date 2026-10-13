import BlockingCore
import Foundation
import XCTest

let selectedCategory = Data("opaque-category-token".utf8)
let selectedWebsite = Data("opaque-website-token".utf8)

final class SelectionTests: XCTestCase {
    private let now = date("2026-10-08 14:00:00")
    private let categoriesOnly = BlockingSelection(categories: [selectedCategory])
    private let websitesOnly = BlockingSelection(webDomains: [selectedWebsite])

    func testCategoryOnlyAndWebsiteOnlySelectionsHaveSchedulesAndSharedBudgets() throws {
        let mixed = BlockingSelection(applications: [selectedApp], categories: [selectedCategory], webDomains: [selectedWebsite])
        for selection in [categoriesOnly, websitesOnly, mixed] {
            var state = ProtectionSnapshot()
            state.policy.windows = sampleWindows
            try state.apply(.selection(selection), at: now, calendar: calendar())
            let morning = date("2026-10-09 07:00:00")
            XCTAssertTrue(state.decision(at: morning, calendar: calendar()).scheduled)
            XCTAssertEqual(state.policy.nextScheduleTransition(after: morning, calendar: calendar()), date("2026-10-09 10:00:00"))
            let budgets = MonitorSpec.plan(for: state).filter {
                if case .budget(_, let targets, let minutes) = $0.kind {
                    XCTAssertEqual(targets, selection)
                    XCTAssertEqual(minutes, 30)
                    return true
                }
                return false
            }
            XCTAssertEqual(budgets.count, 2, "One shared event per day, not one per target kind")
            state.receiveThreshold(activity: MonitorSpec.budgetName(generation: state.generation, cycle: state.cycles[0].id),
                                   event: MonitorSpec.limitEvent, at: now)
            let decision = state.decision(at: now, calendar: calendar())
            XCTAssertTrue(decision.budgetExhausted)
            XCTAssertEqual(decision.selection, selection)
        }
    }

    func testAddingOtherKindsPreservesAnExhaustedAllowance() throws {
        for original in [categoriesOnly, websitesOnly] {
            var state = ProtectionSnapshot()
            state.policy.windows = sampleWindows
            try state.apply(.selection(original), at: now, calendar: calendar())
            state.reachedCycles.insert(state.cycles[0].id)
            let larger = original.union(.init(applications: [selectedApp], categories: [selectedCategory], webDomains: [selectedWebsite]))
            try state.apply(.selection(larger), at: now, calendar: calendar())
            XCTAssertEqual(state.policy.selection, larger)
            XCTAssertNil(state.pendingSelection)
            XCTAssertTrue(state.decision(at: now, calendar: calendar()).budgetExhausted)
        }
    }

    func testCategoryAndWebsiteRulesAreNotTreatedAsUnprotectedDrafts() throws {
        for selection in [categoriesOnly, websitesOnly] {
            for edit in [RuleEdit.limit(60), .limit(nil), .windows([])] {
                var state = ProtectionSnapshot()
                state.policy.windows = sampleWindows
                try state.apply(.selection(selection), at: now, calendar: calendar())
                try state.apply(edit, at: now, calendar: calendar())
                XCTAssertTrue(state.hasPendingChanges)
                XCTAssertEqual(state.policy.dailyLimitMinutes, 30)
                XCTAssertEqual(state.policy.windows, sampleWindows)
            }
        }
    }

    func testMixedReplacementKeepsAllOldKindsUntilOvernightBlockEnds() throws {
        var state = ProtectionSnapshot()
        state.policy.windows = sampleWindows
        let original = BlockingSelection(applications: [selectedApp], categories: [selectedCategory], webDomains: [selectedWebsite])
        let replacement = BlockingSelection(webDomains: [Data("other-site".utf8)])
        try state.apply(.selection(original), at: now, calendar: calendar())
        state.policy.windows = [.init(startMinute: 22 * 60, endMinute: 7 * 60)]
        state.reachedCycles.insert(state.cycles[0].id)
        try state.apply(.selection(replacement), at: now, calendar: calendar())
        XCTAssertEqual(state.policy.selection, original.union(replacement))
        XCTAssertTrue(state.decision(at: now, calendar: calendar()).budgetExhausted)
        XCTAssertEqual(state.pendingSelection?.selection, replacement)
        XCTAssertEqual(state.pendingSelection?.effectiveAfter, date("2026-10-09 07:00:00"))
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.selection, original.union(replacement))
        XCTAssertTrue(state.decision(at: date("2026-10-09 06:59:59"), calendar: calendar()).scheduled)
        state.advance(to: date("2026-10-09 07:00:00"), calendar: calendar())
        XCTAssertEqual(state.policy.selection, replacement)
        XCTAssertNil(state.pendingSelection)
    }

    func testRemovingEverythingWaitsAndThenRemovesEveryMonitor() throws {
        var state = ProtectionSnapshot()
        state.policy.windows = sampleWindows
        try state.apply(.selection(categoriesOnly.union(websitesOnly)), at: now, calendar: calendar())
        try state.apply(.selection(.init()), at: now, calendar: calendar())
        XCTAssertFalse(state.policy.selection.isEmpty)
        XCTAssertEqual(state.pendingSelection?.selection, BlockingSelection())
        state.advance(to: date("2026-10-09 00:00:00"), calendar: calendar())
        XCTAssertTrue(state.policy.selection.isEmpty)
        XCTAssertTrue(MonitorSpec.plan(for: state).isEmpty)
        XCTAssertFalse(state.decision(at: date("2026-10-09 07:00:00"), calendar: calendar()).isBlocked)
    }

    func testCancellingRemovalKeepsImmediateAdditionsAcrossAllKinds() throws {
        var state = ProtectionSnapshot()
        state.policy.windows = sampleWindows
        try state.apply(.selection(categoriesOnly), at: now, calendar: calendar())
        try state.apply(.selection(websitesOnly), at: now, calendar: calendar())
        try state.apply(.cancelPending, at: now, calendar: calendar())
        XCTAssertNil(state.pendingSelection)
        XCTAssertEqual(state.policy.selection, categoriesOnly.union(websitesOnly))
    }

    func testTokensWithIdenticalBytesRemainDistinctAcrossKinds() throws {
        let selection = BlockingSelection(applications: [selectedApp, selectedApp],
                                          categories: [selectedApp], webDomains: [selectedApp])
        XCTAssertEqual(selection.applications.count, 1)
        XCTAssertEqual(selection.categories.count, 1)
        XCTAssertEqual(selection.webDomains.count, 1)
        XCTAssertFalse(BlockingSelection(applications: [selectedApp]).isSuperset(of: selection))
        XCTAssertEqual(try JSONDecoder().decode(BlockingSelection.self, from: JSONEncoder().encode(selection)), selection)
    }

    func testInvalidTokensAndPlatformLimitsCannotSilentlyDropTargets() throws {
        for invalid in [BlockingSelection(applications: [Data()]), .init(categories: [Data()]), .init(webDomains: [Data()])] {
            XCTAssertThrowsError(try invalid.validate()) { XCTAssertEqual($0 as? RuleError, .invalidSelection) }
        }
        let fifty = (0..<50).map { Data("site-\($0)".utf8) }
        var state = ProtectionSnapshot()
        state.policy.windows = sampleWindows
        try state.apply(.selection(.init(webDomains: fifty)), at: now, calendar: calendar())
        // A replacement would temporarily retain the old 50 websites plus a new one.
        XCTAssertThrowsError(try state.apply(.selection(websitesOnly), at: now, calendar: calendar())) {
            XCTAssertEqual($0 as? RuleError, .tooManySelections)
        }
        XCTAssertEqual(state.policy.selection, BlockingSelection(webDomains: fifty))
        XCTAssertNil(state.pendingSelection)
    }
}
