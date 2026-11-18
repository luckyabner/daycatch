import AppKit
import SwiftUI

/// 串起各模块：快捷键 / 菜单栏 → 识别（选中、截图、手动）→ AI 提取 → 用户确认 → 写入日历 → 通知与撤销。
@MainActor
final class AppController {
    let settings = SettingsStore()
    let calendarWriter = CalendarWriter()
    let hotkeys = HotkeyManager()
    let updates = UpdateController()
    private let statusItem = StatusItemController()

    private let manualModel = RecognitionModel(source: .manual)
    private let manualHost = PanelHost()
    private lazy var agendaModel = AgendaModel(store: calendarWriter.eventStore)
    private let agendaHost = PanelHost()
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
        // 界面语言要在建面板 / 提示之前就位
        Localization.language = settings.language
        statusItem.refreshLocalizedText()
        statusItem.onClick = { [weak self] in self?.toggleAgenda() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onCheckForUpdates = { [weak self] in self?.updates.checkForUpdates() }

        updates.onScheduledUpdateFound = { [weak self] version in self?.showUpdateReminder(version) }
        updates.onUpdateAttention = { [weak self] in
            guard let self, self.toastModel.action == .update else { return }
            self.toastHost.close()
        }

        hotkeys.setHandler(for: .selection) { [weak self] in self?.startSelection() }
        hotkeys.setHandler(for: .screenshot) { [weak self] in self?.startScreenshot() }
        hotkeys.setHandler(for: .manual) { [weak self] in self?.toggleManual() }
        hotkeys.update(settings.shortcuts)

        calendarWriter.onStoreChanged = { [weak self] in
            self?.refreshCalendarTitles()
            self?.refreshAgendaIfVisible()
        }

        configureAgendaPanel()
        configureManualPanel()
        configureToast { [weak self] in self?.undoLastWrite() }
    }

    /// 当前语言的文案（语言切换后会重建所有面板）
    private var t: Strings { Localization.strings }

    // MARK: - 菜单栏日程面板

    private func configureAgendaPanel() {
        agendaHost.panel.keyHandler = { [weak self] command in
            guard command == .escape else { return false }
            self?.closeAgenda()
            return true
        }
        rebuildAgendaPanel()
    }

    private func rebuildAgendaPanel() {
        agendaHost.setContent(
            AgendaPanelView(
                model: agendaModel,
                actions: AgendaPanelActions(
                    recognize: { [weak self] in
                        self?.closeAgenda()
                        self?.openManual()
                    },
                    openSettings: { [weak self] in
                        self?.closeAgenda()
                        self?.openSettings()
                    },
                    openPrivacy: { pane in Permissions.openSystemSettings(pane) },
                    recognizeHint: t.recognizeHint(shortcutText(.manual, compact: true))
                )
            )
            .daycatchStyle(accent: settings.accent)
        )
    }

    func toggleAgenda() {
        if agendaHost.isVisible {
            closeAgenda()
        } else {
            openAgenda()
        }
    }

    func openAgenda() {
        closeManual()
        closeResult()
        rebuildAgendaPanel()
        agendaHost.show(topLeft: agendaTopLeft())
        statusItem.setHighlighted(true)
        startOutsideClickMonitor()
        refreshAgenda()
    }

    func closeAgenda() {
        agendaHost.close()
        updateStatusItemHighlight()
    }

    /// 关掉一个面板后：还有别的菜单栏面板开着就保持图标高亮和「点外面收起」
    private func updateStatusItemHighlight() {
        let anyPanelVisible = manualHost.isVisible || agendaHost.isVisible
        statusItem.setHighlighted(anyPanelVisible)
        if !anyPanelVisible {
            stopOutsideClickMonitor()
        }
    }

    /// 面板左上角：居中挂在菜单栏图标下方（两栏变一栏后也要重新对齐）
    private func agendaTopLeft() -> NSPoint {
        let width = AgendaPanelView.width(columns: agendaModel.columnCount)
        if let frame = statusItem.buttonFrame {
            return NSPoint(x: frame.midX - width / 2, y: frame.minY - 8)
        }
        let visible = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - width - 24, y: visible.maxY - 8)
    }

    private func refreshAgendaIfVisible() {
        guard agendaHost.isVisible else { return }
        refreshAgenda()
    }

    private func refreshAgenda() {
        Task { [weak self] in
            guard let self else { return }
            await self.agendaModel.refresh()
            guard self.agendaHost.isVisible else { return }
            self.agendaHost.reanchor(topLeft: self.agendaTopLeft())
        }
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
                    },
                    discard: { [weak self] in
                        self?.manualModel.discardResults()
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
        closeAgenda()
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
        manualModel.isEditing = false
        updateStatusItemHighlight()
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
                guard let self else { return }
                if self.manualHost.isVisible, !self.manualModel.isAdding {
                    self.closeManual()
                }
                if self.agendaHost.isVisible {
                    self.closeAgenda()
                }
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    // MARK: - ① 选中识别

    func startSelection() {
        let hadOwnPanel = manualHost.isVisible || resultHost.isVisible || agendaHost.isVisible
        closeAgenda()
        closeManual()
        closeResult()
        let mouse = NSEvent.mouseLocation
        guard Permissions.isAccessibilityTrusted else {
            // 只让系统弹自己的授权对话框（macOS 只会问一次）；
            // 我们不再叠一个自制的权限面板，改用右下角不打断操作的小卡片
            Permissions.promptAccessibility()
            showPermissionHint(
                title: t.accessibilityPermissionTitle,
                detail: t.accessibilityPermissionDetail(shortcutText(.selection)),
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
                    title: t.noSelectedTextTitle,
                    message: t.noSelectedTextMessage(shortcutText(.selection)),
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
        closeAgenda()
        closeManual()
        closeResult()

        guard Permissions.hasScreenRecordingAccess else {
            // 同上：授权对话框交给系统，应用只给一条可忽略的提示
            Permissions.requestScreenRecording()
            showPermissionHint(
                title: t.screenRecordingPermissionTitle,
                detail: t.screenRecordingPermissionDetail,
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
                model.phase = .notice(Notice(title: t.captureFailedTitle, message: error.localizedDescription, actions: [.recapture]))
                showResult(model, near: NSEvent.mouseLocation)
                return
            }
            guard let url else { return } // 用户按了 esc
            defer { try? FileManager.default.removeItem(at: url) }

            let model = RecognitionModel(source: .screenshot)
            model.phase = .loading(t.recognizingOnDevice)
            showResult(model, near: NSEvent.mouseLocation)

            do {
                let text = try await TextRecognizer.recognizeText(at: url)
                try? FileManager.default.removeItem(at: url)
                guard resultModel === model else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    model.phase = .notice(Notice(
                        title: t.noTextInScreenshotTitle,
                        message: t.noTextInScreenshotMessage,
                        actions: [.recapture]
                    ))
                    return
                }
                recognize(model, text: text)
            } catch {
                model.phase = .notice(Notice(title: t.textRecognitionFailedTitle, message: error.localizedDescription, actions: [.recapture]))
            }
        }
    }

    // MARK: - ①② 结果面板

    private func showResult(_ model: RecognitionModel, near mouse: NSPoint) {
        resultModel?.task?.cancel()
        prepare(model)
        resultModel = model
        resultHost.panel.keyHandler = { [weak self, weak model] command in
            self?.handleKey(command, model: model) ?? false
        }
        updateResultContent(model)
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

    /// 结果面板的文案随语言变化：只换内容，位置和尺寸由 PanelHost 保持
    private func updateResultContent(_ model: RecognitionModel) {
        let hint = model.source == .screenshot
            ? t.screenshotHint(shortcutText(.screenshot, compact: true))
            : t.editHint
        resultHost.setContent(
            ResultPanelView(model: model, actions: panelActions(for: model), footerHint: hint)
                .daycatchStyle(accent: settings.accent, language: Localization.language)
        )
    }

    func closeResult() {
        resultModel?.task?.cancel()
        resultHost.close()
        resultModel = nil
    }

    // MARK: - 识别

    private func prepare(_ model: RecognitionModel) {
        model.defaultAlarmMinutes = settings.defaultAlarmMinutes
        model.eventCalendarTitle = calendarWriter.resolveEventCalendar(id: settings.eventCalendarID)?.title ?? t.calendarFallbackName
    }

    private func recognize(_ model: RecognitionModel, text: String) {
        model.task?.cancel()
        model.sourceText = text
        model.addError = nil
        model.phase = .loading(t.extracting)
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
        let t = Localization.strings
        switch error {
        case AIError.missingAPIKey:
            return Notice(title: t.aiMissingKeyTitle, message: t.aiMissingKeyMessage, actions: [.openSettings])
        case AIError.missingModel:
            return Notice(title: t.aiMissingModelTitle, message: t.aiMissingModelMessage, actions: [.openSettings])
        case AIError.invalidBaseURL:
            return Notice(title: t.aiInvalidBaseURLTitle, message: t.aiInvalidBaseURLMessage, actions: [.openSettings])
        case AIError.offline:
            return Notice(title: t.aiOfflineTitle, message: t.aiOfflineMessage, actions: [.retry])
        case AIError.timedOut:
            return Notice(title: t.aiTimedOutTitle, message: t.aiTimedOutMessage, actions: [.retry])
        case AIError.unauthorized:
            return Notice(title: t.aiUnauthorizedTitle, message: t.aiUnauthorizedMessage, actions: [.openSettings])
        case AIError.forbidden(let message):
            return Notice(title: t.aiForbiddenTitle, message: message, actions: [.openSettings])
        case AIError.modelNotFound(let model):
            return Notice(title: t.aiModelNotFoundTitle(model), message: t.aiModelNotFoundMessage, actions: [.openSettings])
        case AIError.rateLimited:
            return Notice(title: t.aiRateLimitedTitle, message: t.aiRateLimitedMessage, actions: [.retry])
        case AIError.refused:
            return Notice(title: t.aiRefusedTitle, message: t.aiRefusedMessage, actions: [.retry])
        case let error as ExtractionError:
            return Notice(title: t.aiUnparseableTitle, message: t.aiUnparseableMessage(error.localizedDescription), actions: [.retry])
        case let error as CalendarAccessError:
            return Notice(title: error.localizedDescription, message: calendarHelp(error), actions: error.recoveryAction.map { [$0] } ?? [])
        default:
            return Notice(title: t.recognitionFailedTitle, message: error.localizedDescription, actions: [.retry])
        }
    }

    private static func calendarHelp(_ error: CalendarAccessError) -> String {
        let t = Localization.strings
        return switch error {
        case .calendarDenied: t.calendarsDeniedHelp
        case .remindersDenied: t.remindersDeniedHelp
        case .noCalendar, .noReminderList: t.noDestinationHelp
        case .saveFailed: t.saveFailedHelp
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
        toastModel.title = t.addedItemsTitle(receipt.totalCount)
        toastModel.detail = receipt.summary
        toastModel.action = .undo
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
        toastModel.action = .openSettings
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

    /// 后台检查到了新版本：用右下角卡片提醒，不抢焦点；点「更新」才让 Sparkle
    /// 弹自己的更新窗口（那里的下载/安装/重启都由 Sparkle 负责）
    private func showUpdateReminder(_ version: String) {
        // 正在显示撤销提示时不覆盖它，等下一轮检查再提醒
        guard !toastHost.isVisible else { return }
        toastReceipt = nil
        toastModel.title = t.updateAvailableToastTitle(version)
        toastModel.detail = t.updateAvailableToastDetail
        toastModel.action = .update
        toastModel.state = .hint
        configureToast { [weak self] in
            self?.toastDismissTask?.cancel()
            self?.toastHost.close()
            self?.updates.checkForUpdates()
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        toastHost.show(topLeft: NSPoint(x: visible.maxX - 340 - 24, y: visible.minY + 24 + 64), makeKey: false)
        scheduleToastDismiss(after: 15)
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
        case .commandPeriod:
            // ③ 里放弃这次识别（结果或正在进行的请求），回到输入框
            guard model === manualModel, !model.isAdding, model.phase == .results || model.isLoading else { return false }
            model.discardResults()
            return true
        }
    }

    // MARK: - 设置

    func openSettings() {
        closeAgenda()
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
        rebuildAgendaPanel()
    }

    /// 语言修改后：重新生成菜单、菜单栏文案和所有已打开的面板
    func applyLanguage() {
        Localization.language = settings.language
        NSApp.mainMenu = MainMenu.make()
        statusItem.refreshLocalizedText()
        settingsWindow?.refreshLocalizedText()
        configureManualPanel()
        rebuildAgendaPanel()
        if let resultModel { updateResultContent(resultModel) }
    }

    private func refreshCalendarTitles() {
        let title = calendarWriter.resolveEventCalendar(id: settings.eventCalendarID)?.title ?? Localization.strings.calendarFallbackName
        manualModel.eventCalendarTitle = title
        resultModel?.eventCalendarTitle = title
    }

    func shortcutText(_ action: HotkeyAction, compact: Bool = false) -> String {
        guard let shortcut = settings.shortcut(for: action) else { return t.shortcutFallbackName }
        return compact ? shortcut.compactDisplay : shortcut.spacedDisplay
    }

    /// 设置页"测试"按钮：用一段固定文字走一遍完整识别流程
    func testAIConnection() async -> Result<String, Error> {
        do {
            let service = ExtractionService(provider: try AIProviderFactory.make(settings.aiConfiguration()))
            let result = try await service.extract(text: t.connectionTestText)
            return .success(t.testSucceeded(result.items.count))
        } catch {
            return .failure(error)
        }
    }
}
