import XCTest

final class LocalizationTests: XCTestCase {
    private let english = Strings(language: .english)
    private let chinese = Strings(language: .chinese)

    func testSystemLanguageResolvesToSupportedLanguage() {
        XCTAssertNotEqual(AppLanguage.system.resolved, .system)
        XCTAssertEqual(AppLanguage.chinese.resolved, .chinese)
        XCTAssertEqual(AppLanguage.english.resolved, .english)
        XCTAssertTrue(AppLanguage.english.locale.identifier.hasPrefix("en"))
        XCTAssertTrue(AppLanguage.chinese.locale.identifier.hasPrefix("zh"))
    }

    func testEnglishStringsUseNaturalPlurals() {
        XCTAssertEqual(english.addItems(1), "Add 1 item")
        XCTAssertEqual(english.addItems(3), "Add 3 items")
        XCTAssertEqual(english.panelTitleFound(0), "Found 0 items")
        XCTAssertEqual(english.eventCount(2), "2 events")
        XCTAssertEqual(english.todoCount(1), "1 todo")
        XCTAssertEqual(english.duration(90), "1.5 hours")
        XCTAssertEqual(english.duration(75), "1 hour 15 minutes")
        XCTAssertEqual(english.alertReminder(15), "Alert 15 minutes before")
        XCTAssertEqual(english.alertReminder(0, isTodo: true), "Alert at due time")
        XCTAssertEqual(english.alertOption(1440), "1 day before")
    }

    func testChineseStringsKeepExistingWording() {
        XCTAssertEqual(chinese.addItems(2), "添加 2 项")
        XCTAssertEqual(chinese.panelTitleFound(1), "识别到 1 项")
        XCTAssertEqual(chinese.eventCount(2), "2 个日程")
        XCTAssertEqual(chinese.duration(90), "1 个半小时")
        XCTAssertEqual(chinese.duration(75), "1 小时 15 分钟")
        XCTAssertEqual(chinese.alertReminder(1440), "提前 1 天提醒")
        XCTAssertEqual(chinese.alertOption(5), "提前 5 分钟")
        XCTAssertEqual(chinese.alertReminder(0, isTodo: true), "到点提醒")
        XCTAssertEqual(chinese.alertOption(0, isTodo: true), "到点")
    }

    func testEnglishDateFormatting() {
        let text = DateText(language: .english, timeZone: shanghai)
        let start = shanghaiDate(2026, 11, 19, 15)
        let end = shanghaiDate(2026, 11, 19, 16, 30)
        XCTAssertEqual(text.month(start), "Nov")
        XCTAssertEqual(text.weekday(start), "Thu")
        XCTAssertEqual(text.monthDay(start), "Nov 19")
        XCTAssertEqual(text.dayTitle(start), "Thu, Nov 19")
        XCTAssertTrue(text.clock(start).contains("3:00"))
        XCTAssertEqual(text.eventTime(start: start, end: end, isAllDay: false).filter { $0 == "–" }.count, 1)
        XCTAssertEqual(text.eventTime(start: start, end: start, isAllDay: true), "All day")
    }

    func testChineseDateFormattingMatchesDesign() {
        let text = DateText(language: .chinese, timeZone: shanghai)
        XCTAssertEqual(text.dayTitle(shanghaiDate(2026, 11, 17, 17, 43)), "11月17日 周二")
        XCTAssertEqual(text.monthDay(shanghaiDate(2026, 11, 20)), "11月20日")
        XCTAssertEqual(text.clock(shanghaiDate(2026, 11, 19, 15)), "15:00")
        XCTAssertEqual(
            text.eventTime(start: shanghaiDate(2026, 11, 28), end: shanghaiDate(2026, 11, 29), isAllDay: true),
            "全天 · 至 11月29日"
        )
    }

    func testCountdownStrings() {
        XCTAssertEqual(chinese.today, "今天")
        XCTAssertEqual(chinese.tomorrow, "明天")
        XCTAssertEqual(chinese.dayAfterTomorrow, "后天")
        XCTAssertEqual(chinese.countdownDays(3), "还有 3 天")
        XCTAssertEqual(chinese.overdueDays(2), "已过期 2 天")

        XCTAssertEqual(english.today, "Today")
        XCTAssertEqual(english.tomorrow, "Tomorrow")
        XCTAssertEqual(english.dayAfterTomorrow, "In 2 days")
        XCTAssertEqual(english.countdownDays(1), "In 1 day")
        XCTAssertEqual(english.countdownDays(6), "In 6 days")
        XCTAssertEqual(english.overdueDays(2), "2 days overdue")
    }

    func testDaysBetweenCountsCalendarDays() {
        let text = DateText(language: .chinese, timeZone: shanghai)
        XCTAssertEqual(text.daysBetween(shanghaiDate(2026, 11, 17, 23, 30), shanghaiDate(2026, 11, 18, 0, 30)), 1)
        XCTAssertEqual(text.daysBetween(shanghaiDate(2026, 11, 17, 0, 30), shanghaiDate(2026, 11, 17, 23, 30)), 0)
        XCTAssertEqual(text.daysBetween(shanghaiDate(2026, 11, 17), shanghaiDate(2026, 11, 16)), -1)
        XCTAssertEqual(text.daysBetween(shanghaiDate(2026, 11, 17), shanghaiDate(2026, 12, 17)), 30)
    }

    func testItemFormatterFollowsLanguage() {
        let item = ExtractedItem(
            kind: .event, title: "Q4 review",
            start: ItemDate(date: shanghaiDate(2026, 11, 19, 15), hasTime: true),
            end: ItemDate(date: shanghaiDate(2026, 11, 19, 16, 30), hasTime: true),
            location: "3F", inferred: ["end"]
        )
        let englishFormatter = ItemFormatter(timeZone: shanghai, language: .english)
        let englishLines = englishFormatter.detailLines(for: item, alarmMinutes: 15)
        XCTAssertEqual(englishLines.count, 2)
        XCTAssertTrue(englishLines[0].contains("3:00"))
        XCTAssertTrue(englishLines[0].contains("4:30"))
        XCTAssertTrue(englishLines[0].hasSuffix(" · 3F"))
        XCTAssertEqual(englishLines[1], "Alert 15 minutes before")
        XCTAssertEqual(englishFormatter.warnings(for: item), ["No end time in the text — using 1.5 hours"])

        let chineseFormatter = ItemFormatter(timeZone: shanghai, language: .chinese)
        XCTAssertEqual(
            chineseFormatter.detailLines(for: item, alarmMinutes: 15),
            ["15:00 – 16:30 · 3F", "提前 15 分钟提醒"]
        )
        XCTAssertEqual(chineseFormatter.warnings(for: item), ["原文未写结束时间，暂按 1 个半小时"])
    }

    func testEnglishPromptSwitchesLanguage() {
        let message = ExtractionPrompt.userMessage(text: "sync tomorrow", now: referenceNow, timeZone: shanghai, language: .english)
        XCTAssertTrue(message.contains("Current time: 2026-11-17T17:43:00+08:00 (Tuesday)"))
        XCTAssertTrue(message.contains("- 2026-11-18 Wednesday (tomorrow)"))
        XCTAssertTrue(message.contains("<text>\nsync tomorrow\n</text>"))
        XCTAssertTrue(ExtractionPrompt.system(.english).contains("You are Daycatch"))
        XCTAssertFalse(ExtractionPrompt.system(.english).contains("日程"))
        XCTAssertTrue(ExtractionPrompt.system(.chinese).contains("日程提取引擎"))
    }

    func testCurrentLanguageDrivesGlobalStrings() {
        let original = Localization.language
        defer { Localization.language = original }

        Localization.language = .english
        XCTAssertEqual(Localization.strings.undo, "Undo")
        XCTAssertEqual(AIError.unauthorized.errorDescription, "Invalid API key")
        XCTAssertEqual(HotkeyAction.screenshot.title, "Capture screenshot")
        XCTAssertEqual(ProviderKind.qwen.displayName, "Qwen")

        Localization.language = .chinese
        XCTAssertEqual(Localization.strings.undo, "撤销")
        XCTAssertEqual(AIError.unauthorized.errorDescription, "API Key 无效")
        XCTAssertEqual(HotkeyAction.screenshot.title, "截图识别")
        XCTAssertEqual(ProviderKind.qwen.displayName, "通义千问")
    }
}
