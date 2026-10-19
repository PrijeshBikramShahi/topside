import XCTest
@testable import TopsideCore

final class BSDateTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)!
    }

    func testVerifiedNewYearBoundaries() {
        XCTAssertEqual(BSDateConverter.convert(date("2024-04-12"), in: utc), BSDate(year: 2080, month: 12, day: 30))
        XCTAssertEqual(BSDateConverter.convert(date("2024-04-13"), in: utc), BSDate(year: 2081, month: 1, day: 1))
        XCTAssertEqual(BSDateConverter.convert(date("2025-04-14"), in: utc), BSDate(year: 2082, month: 1, day: 1))
        XCTAssertEqual(BSDateConverter.convert(date("2026-04-14"), in: utc), BSDate(year: 2083, month: 1, day: 1))
        XCTAssertEqual(BSDateConverter.convert(date("2027-04-14"), in: utc), BSDate(year: 2084, month: 1, day: 1))
    }

    func testCurrentProjectDate() {
        XCTAssertEqual(BSDateConverter.convert(date("2026-10-19"), in: utc), BSDate(year: 2083, month: 7, day: 2))
    }

    func testRejectsOutsideVerifiedRange() {
        XCTAssertNil(BSDateConverter.convert(date("2013-04-13"), in: utc))
        XCTAssertNil(BSDateConverter.convert(date("2043-04-14"), in: utc))
    }

    func testProjectedRangeExtendsThrough2099() {
        XCTAssertEqual(BSDateConverter.convert(date("2028-04-13"), in: utc), BSDate(year: 2085, month: 1, day: 1))
        XCTAssertEqual(BSDateConverter.convert(date("2033-04-14"), in: utc), BSDate(year: 2090, month: 1, day: 1))
        XCTAssertEqual(BSDateConverter.convert(date("2042-04-14"), in: utc), BSDate(year: 2099, month: 1, day: 1))
        XCTAssertEqual(BSDateConverter.convert(date("2043-04-13"), in: utc), BSDate(year: 2099, month: 12, day: 30))
    }

    func testCivilDateUsesRequestedTimezone() {
        let instant = ISO8601DateFormatter().date(from: "2026-04-13T20:00:00Z")!
        XCTAssertEqual(BSDateConverter.convert(instant, in: utc), BSDate(year: 2082, month: 12, day: 30))
        XCTAssertEqual(BSDateConverter.convert(instant, in: TimeZone(secondsFromGMT: 5 * 3600 + 45 * 60)!),
                       BSDate(year: 2083, month: 1, day: 1))
    }

    func testFormattingIsExplicitAndIncludesYear() {
        let text = DualDateFormatter.string(for: date("2026-10-19"), timeZone: utc)
        XCTAssertEqual(text.ad, "Monday, 19 October 2026")
        XCTAssertEqual(text.bs, "2 Kartik 2083 BS")
        XCTAssertTrue(text.combined.contains("AD:"))
        XCTAssertTrue(text.combined.contains("BS:"))
    }
}
