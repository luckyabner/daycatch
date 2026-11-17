import Carbon.HIToolbox
import XCTest

final class ItemEditingTests: XCTestCase {
    private var calendar: Calendar { ItemFormatter(timeZone: shanghai).calendar }

    private func sampleEvent() -> ExtractedItem {
        ExtractedItem(
            kind: .event, title: "会",
            start: ItemDate(date: shanghaiDate(2026, 11, 20, 14), hasTime: true),
            end: ItemDate(date: shanghaiDate(2026, 11, 20, 15, 30), hasTime: true),
            inferred: ["end", "time"]
        )
    }

    func testSetStartKeepsDurationAndClearsInferred() {
        var item = sampleEvent()
        item.setStart(shanghaiDate(2026, 11, 21, 9))
        XCTAssertEqual(item.end?.date, shanghaiDate(2026, 11, 21, 10, 30))
        XCTAssertFalse(item.inferred.contains("time"))
        XCTAssertTrue(item.inferred.contains("end"))
    }

    func testSetEndClampsAndClearsInferred() {
        var item = sampleEvent()
        item.setEnd(shanghaiDate(2026, 11, 20, 13))
        XCTAssertEqual(item.end?.date, shanghaiDate(2026, 11, 20, 14, 5))
        XCTAssertFalse(item.inferred.contains("end"))
    }

    func testConvertEventToTodoAndBack() {
        var item = sampleEvent()
        item.setKind(.todo, now: referenceNow)
        XCTAssertEqual(item.kind, .todo)
        XCTAssertEqual(item.due, ItemDate(date: shanghaiDate(2026, 11, 20, 14), hasTime: true))
        XCTAssertNil(item.start)

        item.setKind(.event, now: referenceNow)
        XCTAssertEqual(item.start?.date, shanghaiDate(2026, 11, 20, 14))
        XCTAssertEqual(item.end?.date, shanghaiDate(2026, 11, 20, 15))
        XCTAssertTrue(item.inferred.contains("end"))
    }

    func testTodoWithoutDueBecomesEventAtNextHour() {
        var item = ExtractedItem(kind: .todo, title: "x")
        item.setKind(.event, now: referenceNow)
        XCTAssertEqual(item.start?.date, shanghaiDate(2026, 11, 17, 18))
        XCTAssertTrue(item.inferred.isSuperset(of: ["date", "time", "end"]))
    }

    func testAllDayToggle() {
        var item = sampleEvent()
        item.setAllDay(true, calendar: calendar)
        XCTAssertTrue(item.isAllDay)
        XCTAssertEqual(item.start, ItemDate(date: shanghaiDate(2026, 11, 20), hasTime: false))
        item.setAllDay(false, calendar: calendar)
        XCTAssertEqual(item.start?.date, shanghaiDate(2026, 11, 20, 9))
        XCTAssertEqual(item.end?.date, shanghaiDate(2026, 11, 20, 10))
    }
}

final class ShortcutTests: XCTestCase {
    func testDisplayStrings() {
        XCTAssertEqual(HotkeyAction.selection.defaultShortcut.spacedDisplay, "⌥ Space")
        XCTAssertEqual(HotkeyAction.screenshot.defaultShortcut.spacedDisplay, "⌥ ⇧ S")
        XCTAssertEqual(HotkeyAction.screenshot.defaultShortcut.compactDisplay, "⌥⇧S")
        XCTAssertEqual(HotkeyAction.manual.defaultShortcut.spacedDisplay, "⌥ ⇧ Space")
        XCTAssertEqual(Shortcut(keyCode: kVK_ANSI_K, modifiers: [.command, .control]).spacedDisplay, "⌃ ⌘ K")
    }

    func testValidity() {
        XCTAssertTrue(Shortcut(keyCode: kVK_Space, modifiers: [.option]).isValidGlobalShortcut)
        XCTAssertFalse(Shortcut(keyCode: kVK_ANSI_S, modifiers: [.shift]).isValidGlobalShortcut)
        XCTAssertFalse(Shortcut(keyCode: kVK_ANSI_S, modifiers: []).isValidGlobalShortcut)
    }

    func testFlagConversionsAgree() {
        let fromNS = Shortcut(keyCode: UInt16(kVK_ANSI_S), flags: [.option, .shift, .capsLock])
        let fromCG = Shortcut(keyCode: UInt16(kVK_ANSI_S), cgFlags: [.maskAlternate, .maskShift, .maskAlphaShift, .maskNonCoalesced])
        XCTAssertEqual(fromNS, HotkeyAction.screenshot.defaultShortcut)
        XCTAssertEqual(fromCG, HotkeyAction.screenshot.defaultShortcut)
        XCTAssertEqual(HotkeyAction.screenshot.defaultShortcut.carbonModifiers, UInt32(optionKey | shiftKey))
    }

    func testCodableRoundTrip() throws {
        let shortcut = HotkeyAction.manual.defaultShortcut
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), shortcut)
    }
}
