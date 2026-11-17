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
        window.title = "Daycatch 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(settings: controller.settings, env: makeEnvironment(controller)))
        window.center()
        window.setFrameAutosaveName("DaycatchSettings")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
            setRecordingShortcut: { [weak controller] recording in controller?.hotkeys.isSuspended = recording }
        )
    }

    func windowWillClose(_ notification: Notification) {
        controller?.hotkeys.isSuspended = false
    }
}
