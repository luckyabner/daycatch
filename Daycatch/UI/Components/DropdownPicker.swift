import AppKit
import SwiftUI

/// 下拉的尺寸规格。触发器与弹出菜单共用同一套高度 / 圆角 / 字号，
/// 展开时视觉上像是同一个胶囊在变形，而不是换了个控件。
struct DropdownStyle {
    var height: CGFloat = 30
    var cornerRadius: CGFloat = 8
    var fontSize: CGFloat = 13
    var detailFontSize: CGFloat = 11
    var chevronSize: CGFloat = 10
    var horizontalPadding: CGFloat = 10

    static let regular = DropdownStyle()

    /// 结果面板行内编辑器里的小号下拉（和 EditorField 等高）
    static func compact(fontSize: CGFloat = 12) -> DropdownStyle {
        DropdownStyle(
            height: fontSize + 14,
            cornerRadius: 6,
            fontSize: fontSize,
            detailFontSize: max(fontSize - 2, 10),
            chevronSize: 8,
            horizontalPadding: 8
        )
    }
}

/// 全 App 唯一的下拉控件：无边框胶囊 + 贴着控件弹出的白色卡片菜单。
///
/// 不用系统 `Menu`／`NSPopover`：系统的菜单模板和这里的浅灰胶囊差得太远，
/// 弹出时像换了个控件；这里自己开一个无边框面板，圆角、字号、行高都和触发器对齐，
/// 展开时还有一段从触发器顶部开始的淡入 + 放大，过渡更连贯。
struct DropdownPicker<Value: Hashable>: View {
    struct Option: Identifiable, Hashable {
        var value: Value
        var title: String
        /// 第二行说明（例如日历所属账号），为空时不显示
        var detail: String?

        var id: Value { value }
    }

    @Binding var selection: Value
    var options: [Option]
    var width: CGFloat = 200
    var style: DropdownStyle = .regular
    var placeholder: String = Localization.strings.choose

    @State private var isPresented = false
    @State private var triggerView: NSView?

    private var selected: Option? { options.first { $0.value == selection } }

    private var menuWidth: CGFloat {
        let hasDetail = options.contains { $0.detail?.isEmpty == false }
        return max(width, hasDetail ? 230 : 160)
    }

    var body: some View {
        Button(action: toggle) { trigger }
            .buttonStyle(.plain)
            .background(TriggerProbe { triggerView = $0 })
            .onDisappear(perform: close)
    }

    private var trigger: some View {
        HStack(spacing: 6) {
            Text(selected?.title ?? placeholder)
                .font(.system(size: style.fontSize))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            if let detail = selected?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: style.detailFontSize))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, style.horizontalPadding)
        .padding(.trailing, style.horizontalPadding + 22)
        .frame(width: width, height: style.height)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(isPresented ? Theme.fillControlPressed : Theme.fillControl)
        )
        .overlay(alignment: .trailing) {
            ChevronDownShape()
                .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: style.chevronSize, height: style.chevronSize)
                .padding(.trailing, style.horizontalPadding + 2)
        }
        .contentShape(Rectangle())
    }

    private func toggle() {
        isPresented ? close() : present()
    }

    private func present() {
        guard let view = triggerView, let window = view.window else { return }
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let size = DropdownMenuMetrics.size(options: options, style: style, width: menuWidth)
        // 打开时高亮当前选中项，和系统菜单一致
        let state = DropdownMenuState(highlighted: options.firstIndex { $0.value == selection })
        let pick: (Int) -> Void = { index in
            guard options.indices.contains(index) else { return }
            selection = options[index].value
            DropdownPresenter.shared.dismiss()
        }
        isPresented = true
        DropdownPresenter.shared.present(
            DropdownMenuList(
                options: options,
                selection: selection,
                style: style,
                width: menuWidth,
                state: state,
                onPick: pick
            ),
            size: size,
            anchoredBelow: anchor,
            hostWindow: window,
            triggerView: view,
            optionCount: options.count,
            state: state,
            onPick: pick,
            onDismiss: { isPresented = false }
        )
    }

    private func close() {
        guard isPresented else { return }
        DropdownPresenter.shared.dismiss()
    }
}

/// 菜单尺寸完全由选项数量算出来，避免弹面板后再测量 / 二次定位造成闪烁。
private enum DropdownMenuMetrics {
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 1

    static func rowHeight(detail: String?, style: DropdownStyle) -> CGFloat {
        style.height + (detail?.isEmpty == false ? 10 : 0)
    }

    static func size<Value: Hashable>(options: [DropdownPicker<Value>.Option], style: DropdownStyle, width: CGFloat) -> CGSize {
        let height = padding * 2
            + options.reduce(0) { $0 + rowHeight(detail: $1.detail, style: style) }
            + CGFloat(max(options.count - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }
}

/// 键盘高亮（↑↓ 移动，↩ 选中），悬浮和键盘高亮共用一套底色
@MainActor
final class DropdownMenuState: ObservableObject {
    @Published var highlighted: Int?

    init(highlighted: Int?) {
        self.highlighted = highlighted
    }
}

/// 菜单本体：白卡片 + 圆角行，行高、字号、圆角都沿用触发器的那一套。
private struct DropdownMenuList<Value: Hashable>: View {
    var options: [DropdownPicker<Value>.Option]
    var selection: Value
    var style: DropdownStyle
    var width: CGFloat
    @ObservedObject var state: DropdownMenuState
    var onPick: (Int) -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DropdownMenuMetrics.spacing) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                row(option, index: index)
            }
        }
        .padding(DropdownMenuMetrics.padding)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: .top)
        .onAppear {
            withAnimation(.easeOut(duration: 0.14)) { appeared = true }
        }
    }

    private func row(_ option: DropdownPicker<Value>.Option, index: Int) -> some View {
        let isSelected = option.value == selection
        let isHighlighted = state.highlighted == index
        return Button {
            onPick(index)
        } label: {
            HoverHighlight { hovering in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.title)
                            .font(.system(size: style.fontSize))
                            .foregroundStyle(Theme.textPrimary)
                        if let detail = option.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: style.detailFontSize))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 12)
                    CheckmarkShape()
                        .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 11, height: 11)
                        .opacity(isSelected ? 1 : 0)
                }
                .padding(.horizontal, 8)
                .frame(
                    minWidth: width - DropdownMenuMetrics.padding * 2,
                    maxWidth: .infinity,
                    minHeight: DropdownMenuMetrics.rowHeight(detail: option.detail, style: style),
                    alignment: .leading
                )
                .background(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(hovering || isHighlighted ? Theme.fillControl : .clear)
                )
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// 把触发器的 NSView 交给 SwiftUI，用来算弹出位置（SwiftUI 的坐标系换算窗口 / 屏幕太绕）。
/// 视图不参与点击，避免挡在按钮前面吃掉手势。
private struct TriggerProbe: NSViewRepresentable {
    var onResolve: (NSView) -> Void

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - 弹层

/// 无边框、透明背景的菜单面板：白色卡片自带系统窗口阴影。
@MainActor
final class DropdownMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .aqua)
        // 菜单里的文字对读屏软件可读
        setAccessibilityRole(.menu)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// 全局只允许一个下拉展开；负责定位、监控点击 / 滚动 / 窗口变化并收起。
@MainActor
final class DropdownPresenter {
    static let shared = DropdownPresenter()

    private var panel: DropdownMenuPanel?
    private var hostWindow: NSWindow?
    private var menuState: DropdownMenuState?
    private var optionCount = 0
    private var onPick: ((Int) -> Void)?
    private var onDismiss: (() -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// 收起菜单的那一次点击只吞掉 mouseDown，还要把随后的 mouseUp 一起吞掉，
    /// 否则外面的按钮会被点下去（系统菜单也是整次点击都吃掉）
    private var swallowClickUp = false

    private init() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .keyDown]
        ) { event in
            var swallows = false
            MainActor.assumeIsolated { swallows = self.handle(event) }
            return swallows ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { Self.shared.dismiss() }
        }
    }

    func present<Content: View>(
        _ content: Content,
        size: CGSize,
        anchoredBelow anchor: NSRect,
        hostWindow: NSWindow,
        triggerView: NSView,
        optionCount: Int,
        state: DropdownMenuState,
        onPick: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss()

        let screen = hostWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let gap: CGFloat = 4
        let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - size.width - 8)
        var y = anchor.minY - gap - size.height
        if y < visible.minY + 8 {
            // 下方放不下就翻到触发区上方
            y = min(anchor.maxY + gap, visible.maxY - size.height - 8)
        }

        let panel = DropdownMenuPanel()
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)

        self.hostWindow = hostWindow
        self.panel = panel
        self.optionCount = optionCount
        self.menuState = state
        self.onPick = onPick
        self.onDismiss = onDismiss

        observeHost(hostWindow: hostWindow, triggerView: triggerView)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)

        removeObservers()
        if let hostWindow, NSApp.keyWindow == nil || NSApp.keyWindow == panel {
            // 关掉菜单后把键盘焦点还给原来的窗口（设置窗口 / 日程面板）
            hostWindow.makeKey()
        }
        hostWindow = nil
        menuState = nil
        optionCount = 0
        onPick = nil
        let handler = onDismiss
        onDismiss = nil
        handler?()
    }

    // MARK: - 事件

    /// 返回 true 表示这次事件被吞掉
    private func handle(_ event: NSEvent) -> Bool {
        guard let panel else {
            // 已经在收起状态：只等这次点击的 mouseUp 收尾
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                swallowClickUp = false
                return false
            }
            guard swallowClickUp else { return false }
            if event.type == .leftMouseUp || event.type == .rightMouseUp { swallowClickUp = false }
            return true
        }

        if event.type == .keyDown {
            // ↑↓ 移动高亮，↩ 选中，esc 收起
            switch event.keyCode {
            case 125, 126:
                moveHighlight(by: event.keyCode == 125 ? 1 : -1)
                return true
            case 36, 76:
                if let index = menuState?.highlighted { onPick?(index) }
                return true
            case 53:
                dismiss()
                return true
            default:
                return false
            }
        }

        guard event.window !== panel else { return false }
        // 点菜单外面：收起，这次点击整次吞掉，和系统菜单一致
        swallowClickUp = true
        dismiss()
        return true
    }

    private func moveHighlight(by delta: Int) {
        guard let menuState, optionCount > 0 else { return }
        let current = menuState.highlighted ?? (delta > 0 ? -1 : optionCount)
        menuState.highlighted = min(max(current + delta, 0), optionCount - 1)
    }

    // MARK: - 跟随宿主窗口

    private func observeHost(hostWindow: NSWindow, triggerView: NSView) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.shared.dismiss() }
        })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: hostWindow, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.dismiss() }
            })
        }
        // 菜单跟着触发器走：滚动列表时直接收起，避免悬在半空
        if let scrollView = triggerView.enclosingScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.dismiss() }
            })
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}
