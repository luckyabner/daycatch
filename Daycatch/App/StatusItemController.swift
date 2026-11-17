import AppKit

/// 菜单栏图标：左键打开 ③ 输入弹窗，右键显示菜单（设置 / 退出）。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var onClick: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    override init() {
        super.init()
        guard let button = statusItem.button else { return }
        button.image = Self.makeIcon()
        button.image?.accessibilityDescription = "Daycatch"
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Daycatch"
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
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Daycatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    /// 设计稿里的日历图标：rect(3.5,5,17,15.5,rx 3.5) + 横线 y=10 + 两个挂钩
    static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
            let s = rect.width / 24
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 3.5 * s, y: 5 * s, width: 17 * s, height: 15.5 * s), xRadius: 3.5 * s, yRadius: 3.5 * s)
            body.lineWidth = 1.8 * s
            body.stroke()
            let lines = NSBezierPath()
            lines.move(to: NSPoint(x: 3.5 * s, y: 10 * s)); lines.line(to: NSPoint(x: 20.5 * s, y: 10 * s))
            lines.move(to: NSPoint(x: 8 * s, y: 3 * s)); lines.line(to: NSPoint(x: 8 * s, y: 7 * s))
            lines.move(to: NSPoint(x: 16 * s, y: 3 * s)); lines.line(to: NSPoint(x: 16 * s, y: 7 * s))
            lines.lineWidth = 1.8 * s
            lines.lineCapStyle = .round
            lines.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
