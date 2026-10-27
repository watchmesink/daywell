import BlockingCore
import Foundation
import XCTest

final class ProtectionCopyTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    func testNormalNextMidnightMessageUsesTheActualCalendarBoundary() {
        let now = date("2026-10-08 14:00:00")
        let reset = date("2026-10-09 00:00:00")
        XCTAssertTrue(ProtectionCopy.allowanceUsed(resetsAt: reset, now: now,
            calendar: calendar(), locale: locale).contains("midnight"))
    }

    func testTwentyFiveHourDayStillPromisesTheNextLocalMidnight() {
        let now = date("2026-10-25 00:01:00")
        let reset = date("2026-10-26 00:00:00")
        XCTAssertGreaterThan(reset.timeIntervalSince(now), 24 * 60 * 60)
        XCTAssertTrue(ProtectionCopy.allowanceUsed(resetsAt: reset, now: now,
            calendar: calendar(), locale: locale).contains("midnight"))
    }

    func testTravelMessageShowsPinnedResetInTheCurrentTimeZone() {
        let now = date("2026-10-26 19:00:00", zone: "Europe/Berlin")
        let reset = date("2026-10-27 00:00:00", zone: "Europe/Berlin")
        let message = ProtectionCopy.allowanceUsed(resetsAt: reset, now: now,
            calendar: calendar("Asia/Tokyo"), locale: locale)
        XCTAssertTrue(message.contains("8:00"), message)
        XCTAssertTrue(message.contains("Oct 27, 2026"), message)
        XCTAssertFalse(message.contains("midnight"), message)
    }

    func testLaterCalendarDayMidnightIncludesDateInsteadOfAmbiguousMidnight() {
        let now = date("2026-10-26 14:00:00")
        let reset = date("2026-10-28 00:00:00")
        let message = ProtectionCopy.allowanceUsed(resetsAt: reset, now: now,
            calendar: calendar(), locale: locale)
        XCTAssertTrue(message.contains("Oct 28, 2026"), message)
        XCTAssertFalse(message.contains("midnight"), message)
    }

    func testMissingOrExpiredResetDoesNotPromiseAnIncorrectTime() {
        let now = date("2026-10-26 14:00:00")
        for reset in [nil, now, now.addingTimeInterval(-1)] as [Date?] {
            let message = ProtectionCopy.allowanceUsed(resetsAt: reset, now: now,
                calendar: calendar(), locale: locale)
            XCTAssertEqual(message, "The daily allowance is used.")
        }
    }
}
