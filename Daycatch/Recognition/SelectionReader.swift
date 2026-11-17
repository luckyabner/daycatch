import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 读取前台应用中当前选中的文字。
///
/// 1. 先用 Accessibility API 读 `kAXSelectedTextAttribute`（不影响剪贴板）；
/// 2. 读不到（很多 Electron / 自绘控件不支持）时模拟 ⌘C，从剪贴板取文字，
///    读完把剪贴板恢复成原来的内容。
@MainActor
enum SelectionReader {
    enum Method: String {
        case accessibility
        case clipboard
    }

    struct Selection {
        var text: String
        var method: Method
    }

    static func readSelection() async -> Selection? {
        if let text = readViaAccessibility() {
            return Selection(text: text, method: .accessibility)
        }
        if let text = await readViaCopy() {
            return Selection(text: text, method: .clipboard)
        }
        return nil
    }

    // MARK: - Accessibility

    static func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    // MARK: - ⌘C 回退

    static func readViaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        // 等用户松开快捷键里的修饰键，避免目标应用收到 ⌥⌘C
        await waitForModifierRelease()
        postCommandC()

        var changed = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                changed = true
                break
            }
        }
        guard changed else { return nil }
        // 有些应用会分多次写剪贴板，稍等片刻再读
        try? await Task.sleep(for: .milliseconds(30))
        let text = pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func waitForModifierRelease() async {
        for _ in 0..<25 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand]).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - 剪贴板快照

    private typealias PasteboardSnapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
