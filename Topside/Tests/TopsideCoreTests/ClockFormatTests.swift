import XCTest
@testable import TopsideCore

final class ClockFormatTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private let posix = Locale(identifier: "en_US_POSIX")

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testTwentyFourHour() {
        XCTAssertEqual(ClockFormat.string(for: date(2026, 10, 18, 15, 54), style: .twentyFourHour, calendar: cal, locale: posix), "15:54")
        XCTAssertEqual(ClockFormat.string(for: date(2026, 10, 18, 0, 5), style: .twentyFourHour, calendar: cal, locale: posix), "00:05")
    }
    func testTwelveHour() {
        XCTAssertEqual(ClockFormat.string(for: date(2026, 10, 18, 15, 54), style: .twelveHour, calendar: cal, locale: posix), "3:54 PM")
        XCTAssertEqual(ClockFormat.string(for: date(2026, 10, 18, 0, 5), style: .twelveHour, calendar: cal, locale: posix), "12:05 AM")
    }
    func testSystemStyleFollowsLocale() {
        XCTAssertFalse(ClockFormat.uses24Hour(style: .system, locale: Locale(identifier: "en_US")))
        XCTAssertTrue(ClockFormat.uses24Hour(style: .system, locale: Locale(identifier: "en_GB")))
    }
    func testNextMinuteBoundary() {
        XCTAssertEqual(ClockFormat.nextMinuteBoundary(after: date(2026, 10, 18, 12, 0, 30), calendar: cal), date(2026, 10, 18, 12, 1, 0))
        XCTAssertEqual(ClockFormat.nextMinuteBoundary(after: date(2026, 10, 18, 12, 0, 0), calendar: cal), date(2026, 10, 18, 12, 1, 0))
    }
    func testBoundaryAcrossMidnight() {
        XCTAssertEqual(ClockFormat.nextMinuteBoundary(after: date(2026, 10, 18, 23, 59, 45), calendar: cal), date(2026, 10, 19, 0, 0, 0))
    }
    func testMeasurementStringIsWidestForm() {
        XCTAssertEqual(ClockFormat.measurementString(style: .twentyFourHour), "00:00")
        XCTAssertEqual(ClockFormat.measurementString(style: .twelveHour), "00:00 PM")
    }
}
