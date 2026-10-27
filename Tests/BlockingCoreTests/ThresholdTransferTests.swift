import BlockingCore
import Foundation
import XCTest

final class ThresholdTransferTests: XCTestCase {
    func testSubsetWithLongerAllowanceCanExhaustStricterRetainedPolicy() {
        var target = activeSnapshot()
        target.policy.selection = .init(applications: [selectedApp, anotherApp])
        target.policy.dailyLimitMinutes = 15
        var source = target
        source.generation = UUID()
        source.policy.selection = .init(applications: [selectedApp])
        source.policy.dailyLimitMinutes = 30
        source.reachedCycles.insert(source.cycles[0].id)

        target.mergeCompatibleThresholds(from: source)
        XCTAssertTrue(target.reachedCycles.contains(target.cycles[0].id))
    }

    func testSameIDWithDifferentBudgetDatesCannotTransferExhaustion() {
        var target = activeSnapshot()
        var source = target
        source.cycles[0].start = source.cycles[0].start.addingTimeInterval(-3600)
        source.reachedCycles.insert(source.cycles[0].id)

        target.mergeCompatibleThresholds(from: source)
        XCTAssertTrue(target.reachedCycles.isEmpty)
    }

    func testThresholdFromAnotherBudgetDayCannotTransferExhaustion() {
        var target = activeSnapshot()
        var source = activeSnapshot(at: date("2026-10-09 14:00:00"))
        source.reachedCycles.insert(source.cycles[0].id)

        target.mergeCompatibleThresholds(from: source)
        XCTAssertTrue(target.reachedCycles.isEmpty)
    }

    func testTransferChecksCategoriesAndWebsitesAsWellAsApplications() {
        var source = activeSnapshot()
        source.policy.selection = .init(applications: [selectedApp], categories: [Data("category".utf8)],
            webDomains: [Data("website".utf8)])
        source.reachedCycles.insert(source.cycles[0].id)
        for selection in [BlockingSelection(applications: [selectedApp]),
                          BlockingSelection(applications: [selectedApp], categories: [Data("category".utf8)])] {
            var target = source
            target.policy.selection = selection
            target.reachedCycles.removeAll()
            target.mergeCompatibleThresholds(from: source)
            XCTAssertTrue(target.reachedCycles.isEmpty)
        }
    }

    func testNoAllowanceOrEmptySourceCannotTransferExhaustion() {
        for variant in 0..<3 {
            var target = activeSnapshot()
            var source = target
            source.reachedCycles.insert(source.cycles[0].id)
            if variant == 0 { target.policy.dailyLimitMinutes = nil }
            if variant == 1 { source.policy.dailyLimitMinutes = nil }
            if variant == 2 { source.policy.selection = BlockingSelection() }

            target.mergeCompatibleThresholds(from: source)
            XCTAssertTrue(target.reachedCycles.isEmpty)
        }
    }
}
