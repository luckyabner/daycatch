import XCTest

final class ExtractionParserTests: XCTestCase {
    private let parser = ExtractionParser(timeZone: shanghai)

    func testParsesSpecSample() throws {
        let result = try parser.parse(specSampleJSON)
        XCTAssertEqual(result.summary, "周四下午 3 楼开 Q4 复盘会，会前需准备数据。")
        XCTAssertEqual(result.items.count, 2)

        let event = result.items[0]
        XCTAssertEqual(event.kind, .event)
        XCTAssertEqual(event.title, "Q4 复盘会")
        XCTAssertEqual(event.start, ItemDate(date: shanghaiDate(2026, 11, 19, 15), hasTime: true))
        XCTAssertEqual(event.end, ItemDate(date: shanghaiDate(2026, 11, 19, 16, 30), hasTime: true))
        XCTAssertEqual(event.location, "3 楼大会议室")
        XCTAssertEqual(event.notes, "线上会议号 728 391 045")
        XCTAssertEqual(event.alarmMinutesBefore, 15)
        XCTAssertFalse(event.isAllDay)
        XCTAssertTrue(event.inferred.isEmpty)

        let todo = result.items[1]
        XCTAssertEqual(todo.kind, .todo)
        XCTAssertEqual(todo.due, ItemDate(date: shanghaiDate(2026, 11, 19, 15), hasTime: true))
        XCTAssertNil(todo.start)
    }

    func testStripsMarkdownFenceAndProse() throws {
        let reply = "好的，以下是结果：\n```json\n\(specSampleJSON)\n```\n希望有帮助。"
        XCTAssertEqual(try parser.parse(reply).items.count, 2)
    }

    func testMissingEndDefaultsToOneHourAndMarksInferred() throws {
        let reply = #"{"summary":"","items":[{"kind":"event","title":"消防知识培训","start":"2026-11-20T14:00:00+08:00","location":"2 楼报告厅"}]}"#
        let item = try XCTUnwrap(parser.parse(reply).items.first)
        XCTAssertEqual(item.end?.date, shanghaiDate(2026, 11, 20, 15))
        XCTAssertTrue(item.inferred.contains("end"))
    }

    func testEndBeforeStartIsRepaired() throws {
        let reply = #"{"items":[{"kind":"event","title":"会","start":"2026-11-20T14:00:00+08:00","end":"2026-11-20T13:00:00+08:00"}]}"#
        let item = try XCTUnwrap(parser.parse(reply).items.first)
        XCTAssertEqual(item.end?.date, shanghaiDate(2026, 11, 20, 15))
        XCTAssertTrue(item.inferred.contains("end"))
    }

    func testDateOnlyTodoHasNoTime() throws {
        let reply = #"{"items":[{"kind":"todo","title":"报送名单","due":"2026-11-21","inferred":[]}]}"#
        let item = try XCTUnwrap(parser.parse(reply).items.first)
        XCTAssertEqual(item.due, ItemDate(date: shanghaiDate(2026, 11, 21), hasTime: false))
    }

    func testDateOnlyEventBecomesAllDay() throws {
        let reply = #"{"items":[{"kind":"event","title":"团建","start":"2026-11-28","end":"2026-11-29"}]}"#
        let item = try XCTUnwrap(parser.parse(reply).items.first)
        XCTAssertTrue(item.isAllDay)
        XCTAssertEqual(item.start, ItemDate(date: shanghaiDate(2026, 11, 28), hasTime: false))
        XCTAssertEqual(item.end, ItemDate(date: shanghaiDate(2026, 11, 29), hasTime: false))
        XCTAssertFalse(item.inferred.contains("end"))
    }

    func testEventWithoutStartFallsBackToTodo() throws {
        let reply = #"{"items":[{"kind":"event","title":"找时间聊聊"}]}"#
        let item = try XCTUnwrap(parser.parse(reply).items.first)
        XCTAssertEqual(item.kind, .todo)
        XCTAssertNil(item.due)
    }

    func testToleratesLooseTypes() throws {
        let reply = #"{"items":[{"kind":"EVENT","title":"会","start":"2026-11-20 14:00","alarmMinutesBefore":"30","allDay":"false","location":null,"notes":""}]}"#
        let item = try XCTUnwrap(parser.parse(reply).items.first)
        XCTAssertEqual(item.kind, .event)
        XCTAssertEqual(item.alarmMinutesBefore, 30)
        XCTAssertNil(item.location)
        XCTAssertNil(item.notes)
        XCTAssertEqual(item.start?.date, shanghaiDate(2026, 11, 20, 14))
    }

    func testSkipsInvalidItemsButKeepsValidOnes() throws {
        let reply = #"{"items":[{"kind":"event","start":"2026-11-20T14:00:00+08:00"},"oops",{"kind":"todo","title":"写周报"}]}"#
        let items = try parser.parse(reply).items
        XCTAssertEqual(items.map(\.title), ["写周报"])
    }

    func testEmptyItemsIsValid() throws {
        let result = try parser.parse(#"{"summary":"","items":[]}"#)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.summary)
    }

    func testTopLevelArrayAccepted() throws {
        let items = try parser.parse(#"[{"kind":"todo","title":"写周报"}]"#).items
        XCTAssertEqual(items.count, 1)
    }

    func testFriendlyErrors() {
        XCTAssertThrowsError(try parser.parse("")) { XCTAssertEqual($0 as? ExtractionError, .emptyResponse) }
        XCTAssertThrowsError(try parser.parse("抱歉，我无法处理。")) { XCTAssertEqual($0 as? ExtractionError, .notJSON) }
        XCTAssertThrowsError(try parser.parse(#"{"items": [1, 2"#)) { XCTAssertEqual($0 as? ExtractionError, .notJSON) }
        XCTAssertThrowsError(try parser.parse(#"{"items": "none"}"#)) {
            guard case .invalidStructure = $0 as? ExtractionError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try parser.parse(#"{"items":[{"title":""}]}"#)) {
            guard case .invalidStructure = $0 as? ExtractionError else { return XCTFail("\($0)") }
        }
    }

    func testGarbageNeverCrashes() {
        let inputs = ["{", "}", "{}", "[]", "null", "{\"items\":null}", "```", "```json\n```", "{\"items\":[{}]}", "\u{0}"]
        for input in inputs {
            _ = try? parser.parse(input)
        }
    }
}
