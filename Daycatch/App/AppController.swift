import AppKit
import SwiftUI

/// 串起各模块：快捷键 / 菜单栏 → 识别（选中、截图、手动）→ AI 提取 → 用户确认 → 写入日历 → 通知与撤销。
@MainActor
final class AppController {
    let settings = SettingsStore()
    let calendarWriter = CalendarWriter()
    let hotkeys = HotkeyManager()
    private let statusItem = StatusItemController()

    private let manualModel = RecognitionModel(source: .manual)
    private let manualHost = PanelHost()
    private var resultModel: RecognitionModel?
    private let resultHost = PanelHost()
    private let toastModel = ToastModel()
    private let toastHost = PanelHost(insets: NSEdgeInsets(top: 12, left: 24, bottom: 40, right: 24))
    private var toastReceipt: WriteReceipt?
    private var toastDismissTask: Task<Void, Never>?
    private var settingsWindow: SettingsWindowController?
    private var outsideClickMonitor: Any?
    private var isCapturing = false

    init() {
        statusItem.onClick = { [weak self] in self?.toggleManual() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }

        hotkeys.setHandler(for: .selection) { [weak self] in self?.startSelection() }
        hotkeys.setHandler(for: .screenshot) { [weak self] in self?.startScreenshot() }
        hotkeys.setHandler(for: .manual) { [weak self] in self?.toggleManual() }
        hotkeys.update(settings.shortcuts)

        calendarWriter.onStoreChanged = { [weak self] in self?.refreshCalendarTitles() }

        configureManualPanel()
        configureToast { [weak self] in self?.undoLastWrite() }
    }

    // MARK: - ③ 手动输入

    private func configureManualPanel() {
        manualHost.keepsOnScreen = true
        manualHost.panel.keyHandler = { [weak self] command in
            self?.handleKey(command, model: self?.manualModel) ?? false
        }
        manualHost.setContent(
            ManualPanelView(
                model: manualModel,
                actions: panelActions(for: manualModel),
                manualActions: ManualPanelActions(
                    recognize: { [weak self] in self?.recognizeManualInput() },
                    paste: { [weak self] in self?.pasteIntoManualInput() },
                    screenshot: { [weak self] in
                        self?.closeManual()
                        self?.startScreenshot()
                    },
                    openSettings: { [weak self] in
                        self?.closeManual()
                        self?.openSettings()
                    }
                )
            )
            .daycatchStyle(accent: settings.accent)
        )
    }

    func toggleManual() {
        if manualHost.isVisible {
            closeManual()
        } else {
            openManual()
        }
    }

    func openManual() {
        prepare(manualModel)
        let topLeft: NSPoint
        if let frame = statusItem.buttonFrame {
            topLeft = NSPoint(x: frame.midX - 210, y: frame.minY - 8)
        } else {
            let visible = NSScreen.main?.visibleFrame ?? .zero
            topLeft = NSPoint(x: visible.maxX - 440, y: visible.maxY - 8)
        }
        setContentAccent()
        manualHost.show(topLeft: topLeft)
        statusItem.setHighlighted(true)
        manualModel.focusInputToken += 1
        startOutsideClickMonitor()
    }

    func closeManual() {
        manualHost.close()
        statusItem.setHighlighted(false)
        stopOutsideClickMonitor()
        manualModel.isEditing = false
    }

    private func recognizeManualInput() {
        let text = manualModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !manualModel.isLoading else { return }
        recognize(manualModel, text: text)
    }

    private func pasteIntoManualInput() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        manualModel.inputText = text
        manualModel.focusInputToken += 1
    }

    /// 点击弹窗以外的地方时收起（和系统菜单栏弹窗一致）
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.manualHost.isVisible, !self.manualModel.isAdding else { return }
                self.closeManual()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    // MARK: - ① 选中识别

    func startSelection() {
        let hadOwnPanel = manualHost.isVisible || resultHost.isVisible
        closeManual()
        closeResult()
        let mouse = NSEvent.mouseLocation
        guard Permissions.isAccessibilityTrusted else {
            // 只让系统弹自己的授权对话框（macOS 只会问一次）；
            // 我们不再叠一个自制的权限面板，改用右下角不打断操作的小卡片
            Permissions.promptAccessibility()
            showPermissionHint(
                title: "需要开启「辅助功能」权限",
                detail: "允许后再按一次 \(shortcutText(.selection)) 即可。",
                pane: .accessibility
            )
            return
        }

        Task {
            // 必须在面板出现之前读取，否则焦点已经到了 Daycatch 自己身上
            if hadOwnPanel { try? await Task.sleep(for: .milliseconds(80)) }
            let selection = await SelectionReader.readSelection()
            let model = RecognitionModel(source: .selection)
            guard let selection else {
                model.phase = .notice(Notice(
                    title: "没有读到选中的文字",
                    message: "先在聊天或邮件里选中一段文字，再按 \(shortcutText(.selection))。如果这个应用不支持读取，可以复制后在菜单栏的输入框里粘贴识别。",
                    actions: [.openManualInput]
                ))
                showResult(model, near: mouse)
                return
            }
            showResult(model, near: mouse)
            recognize(model, text: selection.text)
        }
    }

    // MARK: - ② 截图识别

    func startScreenshot() {
        guard !isCapturing else { return }
        closeManual()
        closeResult()

        guard Permissions.hasScreenRecordingAccess else {
            // 同上：授权对话框交给系统，应用只给一条可忽略的提示
            Permissions.requestScreenRecording()
            showPermissionHint(
                title: "需要开启「屏幕录制」权限",
                detail: "允许后重新截图；未生效就重启一次 Daycatch。",
                pane: .screenRecording
            )
            return
        }

        isCapturing = true
        Task {
            defer { isCapturing = false }
            let url: URL?
            do {
                url = try await ScreenCapture.captureInteractive()
            } catch {
                let model = RecognitionModel(source: .screenshot)
                model.phase = .notice(Notice(title: "无法启动截图", message: error.localizedDescription, actions: [.recapture]))
                showResult(model, near: NSEvent.mouseLocation)
                return
            }
            guard let url else { return } // 用户按了 esc
            defer { try? FileManager.default.removeItem(at: url) }

            let model = RecognitionModel(source: .screenshot)
            model.phase = .loading("正在本机识别文字…")
            showResult(model, near: NSEvent.mouseLocation)

            do {
                let text = try await TextRecognizer.recognizeText(at: url)
                try? FileManager.default.removeItem(at: url)
                guard resultModel === model else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    model.phase = .notice(Notice(
                        title: "截图里没有识别到文字",
                        message: "换一个区域再试，或者框选得大一些。",
                        actions: [.recapture]
                    ))
                    return
                }
                recognize(model, text: text)
            } catch {
                model.phase = .notice(Notice(title: "文字识别失败", message: error.localizedDescription, actions: [.recapture]))
            }
        }
    }

    // MARK: - ①② 结果面板

    private func showResult(_ model: RecognitionModel, near mouse: NSPoint) {
        resultModel?.task?.cancel()
        prepare(model)
        resultModel = model
        let hint = model.source == .screenshot
            ? "\(shortcutText(.screenshot, compact: true)) 截图识别 · esc 关闭"
            : "⌘E 编辑 · esc 关闭"
        resultHost.panel.keyHandler = { [weak self, weak model] command in
            self?.handleKey(command, model: model) ?? false
        }
        resultHost.setContent(
            ResultPanelView(model: model, actions: panelActions(for: model), footerHint: hint)
                .daycatchStyle(accent: settings.accent)
        )
        // 出现在鼠标右下方；空间不够时 PanelHost 会挪回屏幕内
        var topLeft = NSPoint(x: mouse.x + 16, y: mouse.y - 16)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            let width: CGFloat = model.source == .screenshot ? 520 : 480
            if topLeft.x + width > screen.visibleFrame.maxX - 8 {
                topLeft.x = mouse.x - 16 - width
            }
        }
        resultHost.show(topLeft: topLeft)
    }

    func closeResult() {
        resultModel?.task?.cancel()
        resultHost.close()
        resultModel = nil
    }

    // MARK: - 识别

    private func prepare(_ model: RecognitionModel) {
        model.defaultAlarmMinutes = settings.defaultAlarmMinutes
        model.eventCalendarTitle = calendarWriter.resolveEventCalendar(id: settings.eventCalendarID)?.title ?? "日历"
    }

    private func recognize(_ model: RecognitionModel, text: String) {
        model.task?.cancel()
        model.sourceText = text
        model.addError = nil
        model.phase = .loading("AI 正在提取日程和待办…")
        model.isEditing = false

        let service: ExtractionService
        do {
            service = ExtractionService(provider: try AIProviderFactory.make(settings.aiConfiguration()))
        } catch {
            model.phase = .notice(Self.notice(for: error))
            return
        }

        model.task = Task { [weak model] in
            do {
                let result = try await service.extract(text: text)
                guard let model, !Task.isCancelled else { return }
                model.apply(result)
                if model.source == .manual { model.blurInputToken += 1 }
            } catch is CancellationError {
            } catch {
                guard let model, !Task.isCancelled else { return }
                model.phase = .notice(Self.notice(for: error))
            }
        }
    }

    static func notice(for error: Error) -> Notice {
        switch error {
        case AIError.missingAPIKey:
            return Notice(title: "还没有填写 API Key", message: "在设置的「AI 服务」里选择服务商并填写 API Key 后再试。", actions: [.openSettings])
        case AIError.missingModel:
            return Notice(title: "还没有填写模型名称", message: "在设置的「AI 服务」里填写模型名称。", actions: [.openSettings])
        case AIError.invalidBaseURL:
            return Notice(title: "服务地址无效", message: "请检查「Base URL」，例如 https://api.example.com/v1。", actions: [.openSettings])
        case AIError.offline:
            return Notice(title: "网络未连接", message: "连接网络后重试。识别需要把文字发送给 AI 服务。", actions: [.retry])
        case AIError.timedOut:
            return Notice(title: "请求超时", message: "AI 服务响应太慢，可以稍后重试。", actions: [.retry])
        case AIError.unauthorized:
            return Notice(title: "API Key 无效", message: "服务商拒绝了这个 Key，请检查是否填写正确、是否已过期。", actions: [.openSettings])
        case AIError.forbidden(let message):
            return Notice(title: "没有访问权限", message: message, actions: [.openSettings])
        case AIError.modelNotFound(let model):
            return Notice(title: "找不到模型「\(model)」", message: "请在设置里检查模型名称是否正确，以及当前 Key 是否能使用该模型。", actions: [.openSettings])
        case AIError.rateLimited:
            return Notice(title: "请求太频繁或额度不足", message: "稍等片刻再试，或检查账户余额。", actions: [.retry])
        case AIError.refused:
            return Notice(title: "AI 拒绝处理这段文字", message: "可以换一段文字，或在设置里换一个模型。", actions: [.retry])
        case let error as ExtractionError:
            return Notice(title: "AI 返回的内容无法解析", message: "\(error.localizedDescription)。可以重试一次，或在设置里换一个模型。", actions: [.retry])
        case let error as CalendarAccessError:
            return Notice(title: error.localizedDescription, message: calendarHelp(error), actions: error.recoveryAction.map { [$0] } ?? [])
        default:
            return Notice(title: "识别失败", message: error.localizedDescription, actions: [.retry])
        }
    }

    private static func calendarHelp(_ error: CalendarAccessError) -> String {
        switch error {
        case .calendarDenied: "在系统设置的「隐私与安全性 → 日历」中允许 Daycatch 完全访问后再添加。"
        case .remindersDenied: "在系统设置的「隐私与安全性 → 提醒事项」中允许 Daycatch 完全访问后再添加。"
        case .noCalendar, .noReminderList: "在设置的「默认写入」中选择一个可写入的列表。"
        case .saveFailed: "请稍后重试。"
        }
    }

    // MARK: - 添加 / 撤销

    private func add(_ model: RecognitionModel) {
        guard model.canAdd else { return }
        let items = model.checkedItems
        model.isAdding = true
        model.addError = nil
        model.isEditing = false
        let options = WriteOptions(
            eventCalendarID: settings.eventCalendarID,
            reminderListID: settings.reminderListID,
            defaultAlarmMinutes: settings.defaultAlarmMinutes,
            sourceText: settings.attachSourceToNotes ? model.sourceText : nil
        )
        Task {
            do {
                let receipt = try await calendarWriter.write(items, options: options)
                model.isAdding = false
                if model === manualModel {
                    closeManual()
                    model.reset()
                    if settings.discardSourceAfterAdd { model.inputText = "" }
                } else {
                    closeResult()
                    if settings.discardSourceAfterAdd { model.sourceText = "" }
                }
                showToast(for: receipt)
            } catch {
                model.isAdding = false
                model.addError = Self.notice(for: error)
            }
        }
    }

    private func configureToast(action: @escaping () -> Void) {
        toastHost.panel.allowsKey = false
        toastHost.keepsOnScreen = false
        toastHost.setContent(
            ToastView(model: toastModel, action: action)
                .daycatchStyle(accent: settings.accent)
        )
    }

    private func showToast(for receipt: WriteReceipt) {
        toastReceipt = receipt
        toastModel.title = "已添加 \(receipt.totalCount) 项"
        toastModel.detail = receipt.summary
        toastModel.actionTitle = "撤销"
        toastModel.state = .added
        configureToast { [weak self] in self?.undoLastWrite() }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        toastHost.show(topLeft: NSPoint(x: visible.maxX - 340 - 24, y: visible.minY + 24 + 64), makeKey: false)
        scheduleToastDismiss(after: 8)
    }

    /// 缺少系统权限时的提示：系统自己会弹授权对话框，这里只用右下角卡片说明，
    /// 不占焦点、不遮挡、也不需要用户在这里做决定
    private func showPermissionHint(title: String, detail: String, pane: Permissions.Pane) {
        toastReceipt = nil
        toastModel.title = title
        toastModel.detail = detail
        toastModel.actionTitle = "去设置"
        toastModel.state = .hint
        configureToast { [weak self] in
            // 点「去设置」后立即收起卡片：接下来要看的是系统设置窗口
            self?.toastDismissTask?.cancel()
            self?.toastHost.close()
            Permissions.openSystemSettings(pane)
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        toastHost.show(topLeft: NSPoint(x: visible.maxX - 340 - 24, y: visible.minY + 24 + 64), makeKey: false)
        scheduleToastDismiss(after: 10)
    }

    private func scheduleToastDismiss(after seconds: Double) {
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            // 鼠标停在通知上时不消失
            while self.toastModel.isHovering {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            self.toastHost.close()
            self.toastReceipt = nil
        }
    }

    private func undoLastWrite() {
        guard let receipt = toastReceipt else { return }
        toastModel.state = .undoing
        do {
            try calendarWriter.undo(receipt)
            toastModel.state = .undone
        } catch {
            toastModel.state = .failed(error.localizedDescription)
        }
        toastReceipt = nil
        scheduleToastDismiss(after: 2.5)
    }

    // MARK: - 键盘与操作

    private func panelActions(for model: RecognitionModel) -> PanelActions {
        PanelActions(
            add: { [weak self, weak model] in
                guard let self, let model else { return }
                self.add(model)
            },
            close: { [weak self, weak model] in
                guard let self, let model else { return }
                model === self.manualModel ? self.closeManual() : self.closeResult()
            },
            perform: { [weak self, weak model] action in
                guard let self, let model else { return }
                self.perform(action, model: model)
            }
        )
    }

    private func perform(_ action: RecoveryAction, model: RecognitionModel) {
        switch action {
        case .retry:
            if model === manualModel {
                recognizeManualInput()
            } else if !model.sourceText.isEmpty {
                recognize(model, text: model.sourceText)
            } else if model.source == .screenshot {
                startScreenshot()
            } else {
                closeResult()
            }
        case .openSettings:
            model === manualModel ? closeManual() : closeResult()
            openSettings()
        case .openAccessibilitySettings:
            Permissions.openSystemSettings(.accessibility)
        case .openScreenRecordingSettings:
            Permissions.openSystemSettings(.screenRecording)
        case .openCalendarPrivacy:
            Permissions.openSystemSettings(.calendars)
        case .openRemindersPrivacy:
            Permissions.openSystemSettings(.reminders)
        case .recapture:
            closeResult()
            startScreenshot()
        case .openManualInput:
            closeResult()
            openManual()
        }
    }

    private func handleKey(_ command: PanelKeyCommand, model: RecognitionModel?) -> Bool {
        guard let model else { return false }
        switch command {
        case .escape:
            if model.isEditing {
                model.isEditing = false
                model.blurInputToken += 1
            } else {
                model === manualModel ? closeManual() : closeResult()
            }
            return true
        case .returnKey:
            guard model.canAdd else { return false }
            add(model)
            return true
        case .commandReturn:
            if model === manualModel {
                recognizeManualInput()
            } else if model.canAdd {
                add(model)
            }
            return true
        case .commandE:
            guard model.phase == .results else { return false }
            model.isEditing.toggle()
            if !model.isEditing {
                // 结束编辑：让焦点离开文本框，↩ 恢复为"添加"
                (model === manualModel ? manualHost : resultHost).panel.makeFirstResponder(nil)
            }
            return true
        }
    }

    // MARK: - 设置

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(controller: self)
        }
        settingsWindow?.show()
    }

    /// 快捷键修改后重新注册
    func applyShortcuts() {
        hotkeys.update(settings.shortcuts)
    }

    /// 点缀色修改后刷新面板
    func setContentAccent() {
        configureManualPanel()
    }

    private func refreshCalendarTitles() {
        let title = calendarWriter.resolveEventCalendar(id: settings.eventCalendarID)?.title ?? "日历"
        manualModel.eventCalendarTitle = title
        resultModel?.eventCalendarTitle = title
    }

    func shortcutText(_ action: HotkeyAction, compact: Bool = false) -> String {
        guard let shortcut = settings.shortcut(for: action) else { return "快捷键" }
        return compact ? shortcut.compactDisplay : shortcut.spacedDisplay
    }

    /// 设置页"测试"按钮：用一段固定文字走一遍完整识别流程
    func testAIConnection() async -> Result<String, Error> {
        do {
            let service = ExtractionService(provider: try AIProviderFactory.make(settings.aiConfiguration()))
            let result = try await service.extract(text: "明天下午 3 点在 2 楼会议室开周会")
            return .success("连接正常，识别到 \(result.items.count) 项")
        } catch {
            return .failure(error)
        }
    }
}
