import AppKit
import ApplicationServices
import CoreGraphics

/// 辅助功能 / 屏幕录制权限检查与引导。
@MainActor
enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// 触发系统的"允许 Daycatch 控制这台电脑"提示（只会出现一次）。
    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var hasScreenRecordingAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// 首次调用会弹出系统授权提示；之后只返回当前状态。
    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
        case calendars = "Privacy_Calendars"
        case reminders = "Privacy_Reminders"
    }

    static func openSystemSettings(_ pane: Pane) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        NSWorkspace.shared.open(url)
    }
}
