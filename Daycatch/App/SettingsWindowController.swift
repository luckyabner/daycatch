import AppKit
import SwiftUI

/// 设置窗口：标题栏透明，交通灯叠在左侧导航上（对应设计稿 ④）。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var controller: AppController?

    init(controller: AppController) {
        self.controller = controller
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = Localization.strings.settingsWindowTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.delegate = self
        window.contentView = makeContentView(controller)
        window.center()
        window.setFrameAutosaveName("DaycatchSettings")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 语言切换后重建界面（SwiftUI 视图里的文案在创建时取当前语言）
    func refreshLocalizedText() {
        window.title = Localization.strings.settingsWindowTitle
        guard let controller else { return }
        window.contentView = makeContentView(controller)
    }

    private func makeContentView(_ controller: AppController) -> NSView {
        NSHostingView(rootView: SettingsView(settings: controller.settings, env: makeEnvironment(controller), updates: controller.updates))
    }

    private func makeEnvironment(_ controller: AppController) -> SettingsEnvironment {
        SettingsEnvironment(
            calendars: { [weak controller] in controller?.calendarWriter.eventCalendars() ?? [] },
            reminderLists: { [weak controller] in controller?.calendarWriter.reminderLists() ?? [] },
            requestCalendarAccess: { [weak controller] in
                try? await controller?.calendarWriter.ensureAccess(events: true, reminders: true)
                if !CalendarWriter.hasEventAccess { Permissions.openSystemSettings(.calendars) }
                else if !CalendarWriter.hasReminderAccess { Permissions.openSystemSettings(.reminders) }
            },
            testConnection: { [weak controller] in
                await controller?.testAIConnection() ?? .failure(AIError.missingAPIKey)
            },
            shortcutsChanged: { [weak controller] in controller?.applyShortcuts() },
            accentChanged: { [weak controller] in controller?.setContentAccent() },
            // 等 SwiftUI 这轮更新结束再重建界面，避免在 body 更新中替换窗口内容
            languageChanged: { [weak controller] in
                DispatchQueue.main.async { controller?.applyLanguage() }
            },
            setRecordingShortcut: { [weak controller] recording in controller?.hotkeys.isSuspended = recording }
        )
    }

    func windowWillClose(_ notification: Notification) {
        controller?.hotkeys.isSuspended = false
    }
}
