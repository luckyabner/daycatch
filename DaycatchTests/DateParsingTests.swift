import XCTest

final class DateParsingTests: XCTestCase {
    private let parser = ISODateParser(timeZone: shanghai)

    func testOffsetFormats() {
        let expected = shanghaiDate(2026, 11, 19, 15)
        for text in [
            "2026-11-19T15:00:00+08:00",
            "2026-11-19T07:00:00Z",
            "2026-11-19T07:00:00.000Z",
            "2026-11-19T15:00+08:00",
            "2026-11-19T15:00:00+0800",
            "2026-11-19T02:00:00-05:00",
        ] {
            XCTAssertEqual(parser.parse(text), ItemDate(date: expected, hasTime: true), text)
        }
    }

    func testLocalTimesUseGivenTimeZone() {
        let expected = ItemDate(date: shanghaiDate(2026, 11, 19, 15, 30), hasTime: true)
        XCTAssertEqual(parser.parse("2026-11-19T15:30:00"), expected)
        XCTAssertEqual(parser.parse("2026-11-19T15:30"), expected)
        XCTAssertEqual(parser.parse("2026-11-19 15:30"), expected)
        XCTAssertEqual(parser.parse("  2026-11-19 15:30:00 "), expected)
    }

    func testDateOnly() {
        XCTAssertEqual(parser.parse("2026-11-23"), ItemDate(date: shanghaiDate(2026, 11, 23), hasTime: false))
    }

    func testInvalidInputs() {
        for text in ["", "明天", "2026-13-01", "2026-11-31", "11/19 15:00", "2026-11-19T25:00:00+08:00"] {
            XCTAssertNil(parser.parse(text), text)
        }
    }

    func testDifferentTimeZoneShiftsDateOnly() {
        let tokyo = ISODateParser(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let date = tokyo.parse("2026-11-23")!.date
        XCTAssertEqual(date, shanghaiDate(2026, 11, 22, 23))
    }
}
