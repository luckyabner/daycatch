import XCTest

final class ItemFormatterTests: XCTestCase {
    private let formatter = ItemFormatter(timeZone: shanghai)

    private func event(_ start: Date, _ end: Date, inferred: Set<String> = [], allDay: Bool = false) -> ExtractedItem {
        ExtractedItem(
            kind: .event, title: "会",
            start: ItemDate(date: start, hasTime: !allDay), end: ItemDate(date: end, hasTime: !allDay),
            isAllDay: allDay, inferred: inferred
        )
    }

    func testBadge() {
        let item = event(shanghaiDate(2026, 11, 19, 15), shanghaiDate(2026, 11, 19, 16, 30))
        XCTAssertEqual(formatter.badge(for: item), .init(month: "11月", day: "19", weekday: "周四"))
        let todo = ExtractedItem(kind: .todo, title: "x", due: ItemDate(date: shanghaiDate(2026, 11, 23), hasTime: false))
        XCTAssertEqual(formatter.badge(for: todo), .init(month: "11月", day: "23", weekday: "周一"))
        XCTAssertNil(formatter.badge(for: ExtractedItem(kind: .todo, title: "x")))
    }

    func testEventDetailLinesMatchDesign() {
        var item = event(shanghaiDate(2026, 11, 19, 15), shanghaiDate(2026, 11, 19, 16, 30))
        item.location = "3 楼大会议室"
        item.notes = "线上会议号 728 391 045"
        XCTAssertEqual(formatter.detailLines(for: item, alarmMinutes: 15), [
            "15:00 – 16:30 · 3 楼大会议室",
            "线上会议号 728 391 045 · 提前 15 分钟提醒",
        ])
        XCTAssertEqual(formatter.detailLines(for: item, alarmMinutes: nil).count, 2)
        item.notes = nil
        XCTAssertEqual(formatter.detailLines(for: item, alarmMinutes: nil), ["15:00 – 16:30 · 3 楼大会议室"])
    }

    func testCrossDayAndAllDay() {
        let cross = event(shanghaiDate(2026, 11, 19, 22), shanghaiDate(2026, 11, 20, 1))
        XCTAssertEqual(formatter.eventTimeText(cross), "22:00 – 11月20日 01:00")
        let allDay = event(shanghaiDate(2026, 11, 28), shanghaiDate(2026, 11, 28), allDay: true)
        XCTAssertEqual(formatter.eventTimeText(allDay), "全天")
        let multiDay = event(shanghaiDate(2026, 11, 28), shanghaiDate(2026, 11, 29), allDay: true)
        XCTAssertEqual(formatter.eventTimeText(multiDay), "全天 · 至 11月29日")
    }

    func testTodoDueText() {
        var todo = ExtractedItem(kind: .todo, title: "x", due: ItemDate(date: shanghaiDate(2026, 11, 19, 15), hasTime: true))
        XCTAssertEqual(formatter.dueText(todo), "15:00 前完成")
        todo.due = ItemDate(date: shanghaiDate(2026, 11, 21), hasTime: false)
        XCTAssertEqual(formatter.dueText(todo), "当天截止")
        todo.due = nil
        XCTAssertEqual(formatter.dueText(todo), "无截止时间")
    }

    func testAlarmText() {
        XCTAssertEqual(formatter.alarmText(0), "开始时提醒")
        XCTAssertEqual(formatter.alarmText(15), "提前 15 分钟提醒")
        XCTAssertEqual(formatter.alarmText(60), "提前 1 小时提醒")
        XCTAssertEqual(formatter.alarmText(1440), "提前 1 天提醒")
        // 待办在截止时刻提醒
        XCTAssertEqual(formatter.alarmText(0, isTodo: true), "截止时提醒")
        XCTAssertEqual(formatter.alarmText(30, isTodo: true), "提前 30 分钟提醒")
    }

    func testEffectiveAlarmMinutesFollowsDefaultUnlessEdited() {
        var item = event(shanghaiDate(2026, 11, 19, 15), shanghaiDate(2026, 11, 19, 16, 30))
        // AI 没给提醒 → 跟随设置里的默认值
        XCTAssertEqual(item.effectiveAlarmMinutes(defaults: 15), 15)
        XCTAssertNil(item.effectiveAlarmMinutes(defaults: nil))
        // 编辑器里选具体时间
        item.alarmMinutesBefore = 30
        XCTAssertEqual(item.effectiveAlarmMinutes(defaults: 15), 30)
        // 编辑器里选「不提醒」：覆盖默认值
        item.alarmMinutesBefore = ExtractedItem.alarmNone
        XCTAssertNil(item.effectiveAlarmMinutes(defaults: 15))
    }

    func testTodoDetailLinesShowAlarm() {
        let todo = ExtractedItem(kind: .todo, title: "x", due: ItemDate(date: shanghaiDate(2026, 11, 19, 15), hasTime: true))
        XCTAssertEqual(formatter.detailLines(for: todo, alarmMinutes: 0), ["15:00 前完成", "截止时提醒"])
        XCTAssertEqual(formatter.detailLines(for: todo, alarmMinutes: nil), ["15:00 前完成"])
        // 只有日期没有时间时不写闹钟，也不显示提醒
        let untimed = ExtractedItem(kind: .todo, title: "x", due: ItemDate(date: shanghaiDate(2026, 11, 21), hasTime: false))
        XCTAssertEqual(formatter.detailLines(for: untimed, alarmMinutes: 0), ["当天截止"])
    }

    func testInferredWarnings() {
        let item = event(shanghaiDate(2026, 11, 20, 14), shanghaiDate(2026, 11, 20, 15), inferred: ["end"])
        XCTAssertEqual(formatter.warnings(for: item), ["原文未写结束时间，暂按 1 小时"])

        let long = event(shanghaiDate(2026, 11, 20, 14), shanghaiDate(2026, 11, 20, 15, 30), inferred: ["end", "time"])
        XCTAssertEqual(formatter.warnings(for: long), ["原文未写具体时间，暂按 14:00", "原文未写结束时间，暂按 1 个半小时"])

        let todo = ExtractedItem(kind: .todo, title: "x", due: ItemDate(date: shanghaiDate(2026, 11, 21), hasTime: false), inferred: ["due"])
        XCTAssertEqual(formatter.warnings(for: todo), ["原文未写截止时间，暂按当天"])

        let unknown = event(shanghaiDate(2026, 11, 20, 14), shanghaiDate(2026, 11, 20, 15), inferred: ["title"])
        XCTAssertEqual(formatter.warnings(for: unknown), ["部分信息由 AI 推断，请核对"])

        XCTAssertEqual(formatter.warnings(for: event(shanghaiDate(2026, 11, 20, 14), shanghaiDate(2026, 11, 20, 15))), [])
    }

    func testDurationText() {
        XCTAssertEqual(formatter.durationText(45 * 60), "45 分钟")
        XCTAssertEqual(formatter.durationText(3600), "1 小时")
        XCTAssertEqual(formatter.durationText(5400), "1 个半小时")
        XCTAssertEqual(formatter.durationText(4500), "1 小时 15 分钟")
    }
}
