import SwiftUI

/// DESIGN_SPEC §3 设计 Token。
enum Theme {
    static let textPrimary = Color(hex: 0x111111)
    static let textBody = Color(hex: 0x4A4A4A)
    static let textSecondary = Color(hex: 0x6B6B6B)
    static let textPlaceholder = Color(hex: 0x8A8A8A)
    static let surface = Color.white
    static let fillControl = Color(hex: 0xF3F3F2)
    static let fillControlPressed = Color(hex: 0xE9E9E7)
    static let fillPrimaryButton = Color(hex: 0xF0F0EE)
    static let fillPrimaryButtonHover = Color(hex: 0xE8E8E5)
    static let divider = Color(hex: 0xECECEA)
    static let todoRing = Color(hex: 0x9A9A9A)
    static let uncheckedRing = Color(hex: 0xCFCFCC)
    static let warning = Color(hex: 0x8A5A00)
    static let error = Color(hex: 0xB42318)
    static let success = Color(hex: 0x1F9D55)
    static let successText = Color(hex: 0x1F7A45)

    static let defaultAccent = Color(hex: 0xE8462E)
    static let accentOptions = ["#E8462E", "#2F6BFF", "#111111", "#1F9D55"]

    /// 面板阴影 `0 1px 2px rgba(0,0,0,.06), 0 30px 70px rgba(0,0,0,.16)` 需要的透明边距
    static var panelShadowInsets: NSEdgeInsets { NSEdgeInsets(top: 24, left: 44, bottom: 96, right: 44) }
}

/// 三种界面里事项行的尺寸差异（① 选中 / ② 截图 / ③ 手动输入）。
struct RowMetrics: Sendable {
    var dateWidth: CGFloat
    var dateFontSize: CGFloat
    var titleFontSize: CGFloat
    var verticalPadding: CGFloat
    var horizontalPadding: CGFloat
    var columnSpacing: CGFloat
    var lineSpacing: CGFloat

    static let selection = RowMetrics(dateWidth: 52, dateFontSize: 34, titleFontSize: 17, verticalPadding: 20, horizontalPadding: 28, columnSpacing: 20, lineSpacing: 6)
    static let screenshot = RowMetrics(dateWidth: 52, dateFontSize: 32, titleFontSize: 16, verticalPadding: 18, horizontalPadding: 28, columnSpacing: 20, lineSpacing: 5)
    static let manual = RowMetrics(dateWidth: 44, dateFontSize: 28, titleFontSize: 15, verticalPadding: 16, horizontalPadding: 22, columnSpacing: 18, lineSpacing: 5)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

// MARK: - 环境

private struct AccentColorKey: EnvironmentKey {
    static let defaultValue = Theme.defaultAccent
}

extension EnvironmentValues {
    /// 点缀色（日程圆点、勾选按钮），可在设置里切换。
    var dcAccent: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

extension View {
    /// 设计稿只有浅色版：统一锁定浅色外观。
    func daycatchStyle(accent: Color) -> some View {
        environment(\.dcAccent, accent)
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .foregroundStyle(Theme.textPrimary)
            .font(.system(size: 13))
    }
}
