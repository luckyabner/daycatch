import AppKit

/// 菜单栏图标：左键打开日程面板（日程 / 待办），右键显示菜单（设置 / 退出）。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var onClick: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    override init() {
        super.init()
        guard let button = statusItem.button else { return }
        button.image = Self.makeIcon()
        button.image?.accessibilityDescription = "Daycatch"
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = Localization.strings.statusItemTooltip
    }

    /// 图标按钮在屏幕上的位置，用于定位弹窗；按钮尚未布局到菜单栏时返回 nil
    var buttonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window, let screen = window.screen else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        // 菜单栏位于 visibleFrame 之上；不在那里说明还没布局好
        guard frame.minY >= screen.visibleFrame.maxY - 1, frame.width > 0 else { return nil }
        return frame
    }

    func setHighlighted(_ highlighted: Bool) {
        statusItem.button?.highlight(highlighted)
    }

    /// 语言切换后刷新悬停提示（菜单每次弹出时现建，不用缓存）
    func refreshLocalizedText() {
        statusItem.button?.toolTip = Localization.strings.statusItemTooltip
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onClick?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let t = Localization.strings
        let settings = NSMenuItem(title: "\(t.settings)…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let updates = NSMenuItem(title: t.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: t.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    /// 设计稿 B1 图标（取景框 + 日历页），18pt 模板图，深浅色菜单栏自动适配
    static func makeIcon() -> NSImage {
        // imageset 已设为 Template Image；资源缺失时退回系统日历符号，保证菜单栏仍有可点图标
        // NSImage(named:) 返回缓存实例，copy 一份再改 size / isTemplate
        let named = NSImage(named: "MenuBarIcon")?.copy() as? NSImage
        let image = named ?? NSImage(systemSymbolName: "calendar", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
