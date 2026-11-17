import AppKit
import Carbon.HIToolbox

/// 全局快捷键（虚拟键码 + 修饰键）。
struct Shortcut: Equatable, Hashable, Codable, Sendable {
    struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    var keyCode: UInt16
    var modifiers: Modifiers

    init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = UInt16(keyCode)
        self.modifiers = modifiers
    }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: UInt16, cgFlags: CGEventFlags) {
        var modifiers: Modifiers = []
        if cgFlags.contains(.maskControl) { modifiers.insert(.control) }
        if cgFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if cgFlags.contains(.maskShift) { modifiers.insert(.shift) }
        if cgFlags.contains(.maskCommand) { modifiers.insert(.command) }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 至少包含 ⌃ ⌥ ⌘ 之一才算合法的全局快捷键（只有 ⇧ 会和正常打字冲突）。
    var isValidGlobalShortcut: Bool {
        !modifiers.intersection([.control, .option, .command]).isEmpty
    }

    var carbonModifiers: UInt32 {
        var value = 0
        if modifiers.contains(.control) { value |= controlKey }
        if modifiers.contains(.option) { value |= optionKey }
        if modifiers.contains(.shift) { value |= shiftKey }
        if modifiers.contains(.command) { value |= cmdKey }
        return UInt32(value)
    }

    // MARK: - 显示

    private var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    /// 设置页胶囊里的写法："⌥ ⇧ S"
    var spacedDisplay: String { (modifierSymbols + [keyName]).joined(separator: " ") }

    /// 底部提示里的写法："⌥⇧S"
    var compactDisplay: String { modifierSymbols.joined() + keyName }

    var keyName: String { Self.keyNames[Int(keyCode)] ?? "Key\(keyCode)" }

    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"), (kVK_F6, "F6"),
            (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]
        for (code, name) in letters { names[code] = name }
        return names
    }()
}

enum HotkeyAction: String, CaseIterable, Sendable {
    case selection
    case screenshot
    case manual

    var title: String {
        switch self {
        case .selection: "识别选中文字"
        case .screenshot: "截图识别"
        case .manual: "打开输入框"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .selection: Shortcut(keyCode: kVK_Space, modifiers: [.option])
        case .screenshot: Shortcut(keyCode: kVK_ANSI_S, modifiers: [.option, .shift])
        case .manual: Shortcut(keyCode: kVK_Space, modifiers: [.option, .shift])
        }
    }
}
