import AppKit
import SwiftUI

enum PanelKeyCommand {
    case escape
    case returnKey
    case commandReturn
    case commandE
    case commandPeriod
}

/// 无边框、不激活应用的浮动面板。
///
/// `.nonactivatingPanel` 让面板成为 key window 接收键盘，但前台应用（微信、钉钉…）保持激活，
/// 菜单栏也不会切换成 Daycatch。
final class FloatingPanel: NSPanel {
    /// 返回 true 表示已处理该按键
    var keyHandler: ((PanelKeyCommand) -> Bool)?
    var allowsKey = true

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .aqua)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// 位置由 PanelHost 计算；不让 AppKit 因为透明阴影边距碰到菜单栏而把面板往下推
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let command = command(for: event), keyHandler?(command) == true { return }
        }
        super.sendEvent(event)
    }

    private func command(for event: NSEvent) -> PanelKeyCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        switch (event.keyCode, flags) {
        case (53, []):
            return .escape
        case (_, [.command]) where isReturn:
            return .commandReturn
        case (14, [.command]):
            return .commandE
        case (47, [.command]):
            // ⌘.：macOS 惯用的「取消」
            return .commandPeriod
        case (_, []) where isReturn:
            // 正在文本框里输入时，↩ 交给文本框（换行 / 提交编辑）
            if firstResponder is NSText { return nil }
            return .returnKey
        default:
            return nil
        }
    }
}

/// 把 SwiftUI 视图放进 FloatingPanel，并随内容尺寸调整窗口，保持可见区域的左上角不动。
@MainActor
final class PanelHost {
    let panel = FloatingPanel()
    private let insets: NSEdgeInsets
    private var hostingView: NSHostingView<AnyView>?
    /// 可见面板（不含阴影边距）左上角在屏幕坐标中的位置
    private var anchorTopLeft: NSPoint = .zero
    /// SwiftUI 最近一次报告的内容尺寸
    private var contentSize: NSSize?
    /// 尺寸变化后是否需要把面板挪回屏幕内
    var keepsOnScreen = true

    init(insets: NSEdgeInsets = Theme.panelShadowInsets) {
        self.insets = insets
    }

    var isVisible: Bool { panel.isVisible }

    func setContent<Content: View>(_ content: Content) {
        let root = AnyView(
            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self] size in
                    self?.contentSizeChanged(size)
                }
                .padding(EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right))
        )
        if let hostingView {
            hostingView.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            view.sizingOptions = []
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            hostingView = view
        }
    }

    /// 以可见面板的左上角定位
    func show(topLeft: NSPoint, makeKey: Bool = true) {
        anchorTopLeft = topLeft
        hostingView?.layoutSubtreeIfNeeded()
        if let contentSize {
            applyFrame(contentSize: contentSize)
        } else if let size = hostingView?.fittingSize, size.width > insets.left + insets.right {
            applyFrame(contentSize: NSSize(width: size.width - insets.left - insets.right, height: size.height - insets.top - insets.bottom))
        }
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel.orderOut(nil)
    }

    /// 当前可见面板的尺寸（不含阴影边距）
    var visibleSize: NSSize {
        NSSize(
            width: panel.frame.width - insets.left - insets.right,
            height: panel.frame.height - insets.top - insets.bottom
        )
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        applyFrame(contentSize: size)
    }

    private func applyFrame(contentSize: NSSize) {
        var topLeft = anchorTopLeft
        if keepsOnScreen, let screen = screen(containing: topLeft) {
            let visible = screen.visibleFrame
            topLeft.x = min(max(topLeft.x, visible.minX + 8), visible.maxX - contentSize.width - 8)
            if topLeft.y - contentSize.height < visible.minY + 8 {
                topLeft.y = visible.minY + 8 + contentSize.height
            }
            topLeft.y = min(topLeft.y, visible.maxY - 8)
        }
        let frame = NSRect(
            x: topLeft.x - insets.left,
            y: topLeft.y - contentSize.height - insets.bottom,
            width: contentSize.width + insets.left + insets.right,
            height: contentSize.height + insets.top + insets.bottom
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) } ?? NSScreen.main
    }
}
