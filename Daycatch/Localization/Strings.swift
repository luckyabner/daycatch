import Foundation

/// 全部界面文案。中英对照写在同一个属性里，避免出现漏翻或键值对不上的 `.strings` 文件。
///
/// 用法：`Localization.strings.<文案>`（当前语言）或 `Strings(language: .english)`（指定语言）。
/// 带数字的文案都提供成方法，中英文各按自己的习惯处理量词和复数。
struct Strings: Equatable, Sendable {
    var language: AppLanguage

    init(language: AppLanguage = Localization.language) {
        self.language = language.resolved
    }

    var isEnglish: Bool { language.isEnglish }

    private func pick(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }

    /// 英文的数量词组：1 item / 2 items
    private func quantity(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }

    // MARK: - 通用

    var cancel: String { pick("取消", "Cancel") }
    var close: String { pick("关闭", "Close") }
    var done: String { pick("完成", "Done") }
    var edit: String { pick("编辑", "Edit") }
    var settings: String { pick("设置", "Settings") }
    var paste: String { pick("粘贴", "Paste") }
    var screenshot: String { pick("截图", "Screenshot") }
    var undo: String { pick("撤销", "Undo") }
    var retry: String { pick("重试", "Try again") }
    var openSettings: String { pick("打开设置", "Open Settings") }
    var openSystemSettings: String { pick("打开系统设置", "Open System Settings") }
    var manualInput: String { pick("手动输入", "Enter manually") }
    var recapture: String { pick("重新框选", "Capture again") }
    var choose: String { pick("请选择", "Choose") }
    var colonSeparator: String { pick("：", ": ") }

    // MARK: - 设置

    var settingsWindowTitle: String { pick("Daycatch 设置", "Daycatch Settings") }

    var paneGeneral: String { pick("通用", "General") }
    var paneAI: String { pick("AI 服务", "AI service") }
    var paneCalendar: String { pick("日历", "Calendar") }
    var panePrivacy: String { pick("隐私", "Privacy") }

    // 通用

    var sectionShortcuts: String { pick("快捷键", "Shortcuts") }
    var sectionAIService: String { pick("AI 服务", "AI service") }
    var sectionDefaultTargets: String { pick("默认写入", "Default destinations") }
    var sectionPrivacy: String { pick("隐私", "Privacy") }

    func hotkeyTitle(_ action: HotkeyAction) -> String {
        switch action {
        case .selection: pick("识别选中文字", "Capture selection")
        case .screenshot: pick("截图识别", "Capture screenshot")
        case .manual: pick("打开输入框", "Open input field")
        }
    }

    var shortcutsNote: String {
        pick(
            "选中识别需开启“辅助功能”权限，读取失败时自动改用 ⌘C。如果开关已打开仍提示无权限，在列表里用「−」移除 Daycatch 后重新添加。",
            "Selection capture needs Accessibility access; Daycatch falls back to ⌘C when reading fails. If the switch is already on but you still see a permission warning, remove Daycatch with “−” and add it again."
        )
    }

    var accessibilityRow: String { pick("辅助功能权限", "Accessibility access") }
    var accessibilityEnabled: String { pick("已开启", "On") }
    var accessibilityTurnOn: String { pick("去开启", "Turn on") }
    var accentColorRow: String { pick("点缀色", "Accent color") }
    var languageRow: String { pick("语言", "Language") }
    var launchAtLoginRow: String { pick("登录时启动", "Launch at login") }

    func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system: pick("跟随系统", "System")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    func shortcutConflict(_ shortcut: String, action: String) -> String {
        pick(
            "\(shortcut) 已用于「\(action)」，请换一个组合。",
            "\(shortcut) is already used for “\(action)”. Choose another combination."
        )
    }

    func launchFailed(_ message: String) -> String {
        pick("设置失败：\(message)", "Couldn’t update: \(message)")
    }

    // AI 服务

    func providerName(_ provider: ProviderKind) -> String {
        switch provider {
        case .anthropic: pick("Claude（Anthropic）", "Claude (Anthropic)")
        case .openai: "OpenAI"
        case .deepseek: "DeepSeek"
        case .qwen: pick("通义千问", "Qwen")
        case .custom: pick("自定义（OpenAI 兼容）", "Custom (OpenAI-compatible)")
        }
    }

    var providerRow: String { pick("服务商", "Provider") }
    var testButton: String { pick("测试", "Test") }
    var apiKeyPlaceholder: String { pick("粘贴 API Key", "Paste API key") }
    var modelRow: String { pick("模型", "Model") }
    var modelPlaceholder: String { pick("模型名称", "Model name") }
    var revealSecret: String { pick("显示明文", "Show") }
    var hideSecret: String { pick("隐藏", "Hide") }
    var showAPIKey: String { pick("显示 API Key", "Show API key") }
    var hideAPIKey: String { pick("隐藏 API Key", "Hide API key") }
    var shortcutRecording: String { pick("按下新的快捷键…", "Press a new shortcut…") }
    var shortcutUnset: String { pick("未设置", "Not set") }
    var shortcutNeedsModifier: String { pick("需要包含 ⌃ ⌥ 或 ⌘", "Include ⌃, ⌥, or ⌘") }
    var testRunning: String { pick("测试中…", "Testing…") }
    var testConnected: String { pick("连接正常", "Connected") }
    var testFailed: String { pick("连接失败", "Connection failed") }

    func testSucceeded(_ count: Int) -> String {
        pick("连接正常，识别到 \(count) 项", "Connected — extracted \(quantity(count, "item"))")
    }

    /// 设置页「测试」按钮发给 AI 的示例文字
    var connectionTestText: String {
        pick("明天下午 3 点在 2 楼会议室开周会", "Team sync tomorrow at 3pm in the 2nd floor meeting room")
    }

    var apiKeyNote: String {
        pick(
            "API Key 只保存在这台 Mac 上，仅你的账户可读。",
            "Your API key is stored only on this Mac and is readable only by your account."
        )
    }

    // 默认写入

    var eventsTargetRow: String { pick("日程 → 日历", "Events → Calendar") }
    var todosTargetRow: String { pick("待办 → 提醒事项", "Todos → Reminders") }
    var systemDefault: String { pick("系统默认", "System default") }
    var defaultAlertRow: String { pick("默认提醒", "Default alert") }
    var grantAccessButton: String { pick("授权访问", "Grant access") }

    var defaultAlertNote: String {
        pick(
            "原文写明提醒时间时以原文为准；默认提醒只用于有具体时间的日程。",
            "An alert time written in the text always wins; the default only applies to events with a specific time."
        )
    }

    // 隐私

    var privacyLocalRecognitionRow: String { pick("截图只在本机识别文字", "Text recognition stays on this Mac") }
    var privacyAlwaysOn: String { pick("始终开启", "Always on") }
    var privacyAttachSourceRow: String { pick("在日程备注里附上原文", "Attach source text to notes") }
    var privacyDiscardSourceRow: String { pick("添加后不保留原文", "Discard source text after adding") }

    var privacyNote: String {
        pick(
            "只有识别出的文字会发送给你选择的 AI 服务商；截图图片不会离开这台 Mac，识别后立即删除。",
            "Only the recognized text is sent to your AI provider. Screenshots never leave this Mac and are deleted right after recognition."
        )
    }

    // MARK: - 识别面板（①②③）

    var recognizeTab: String { pick("识别", "Recognize") }
    var sourceSelection: String { pick("来自选中文字", "From selection") }
    var sourceScreenshot: String { pick("来自截图", "From screenshot") }
    var sourceManual: String { pick("手动输入", "Manual input") }
    var manualInputPlaceholder: String { pick("粘贴或输入包含时间安排的文字", "Paste or type text with dates and times") }
    var manualInputAccessibilityLabel: String { pick("输入包含时间安排的文字", "Input text with dates and times") }
    var recognizing: String { pick("识别中…", "Recognizing…") }
    var recognizeShortcutButton: String { pick("⌘↩ 识别", "⌘↩ Recognize") }
    var cancelRecognitionHelp: String { pick("中断这次识别，清空输入重新开始（⌘.）", "Stop this recognition and start over (⌘.)") }
    var discardResultsHelp: String { pick("放弃这次识别结果并清空输入，重新开始（⌘.）", "Discard these results and clear the input (⌘.)") }
    var finishEditingHelp: String { pick("完成编辑（⌘E）", "Finish editing (⌘E)") }
    var startEditingHelp: String { pick("修改识别出的事项（⌘E）", "Edit the extracted items (⌘E)") }

    var panelTitleRecognizing: String { pick("正在识别…", "Recognizing…") }

    func panelTitleFound(_ count: Int) -> String {
        pick("识别到 \(count) 项", "Found \(quantity(count, "item"))")
    }

    var panelTitleScreenshot: String { pick("截图识别", "Screenshot") }
    var panelTitleSelection: String { pick("选中识别", "Selection") }

    var hideSourceText: String { pick("收起原文", "Hide original") }
    var showSourceText: String { pick("查看原文", "Show original") }
    var showRecognizedText: String { pick("查看识别文字", "Show recognized text") }

    var emptyResultTitle: String { pick("没有识别到日程或待办", "No events or todos found") }
    var emptyResultMessage: String { pick("AI 没有在这段文字里找到时间安排。", "The AI didn’t find any schedule in this text.") }
    var emptyResultMessageManual: String { pick("可以补充时间、地点等信息后再识别一次。", "Add a time, place, or other details and try again.") }

    var addInProgress: String { pick("正在添加…", "Adding…") }
    var nothingSelected: String { pick("未选择事项", "Nothing selected") }

    func addItems(_ count: Int) -> String {
        pick("添加 \(count) 项", "Add \(quantity(count, "item"))")
    }

    var finishEditingHint: String { pick("⌘E 完成编辑 · esc 关闭", "⌘E done editing · esc to close") }
    var editHint: String { pick("⌘E 编辑 · esc 关闭", "⌘E edit · esc to close") }

    func screenshotHint(_ shortcut: String) -> String {
        pick("\(shortcut) 截图识别 · esc 关闭", "\(shortcut) screenshot · esc to close")
    }

    // 无障碍标签

    var settingsAccessibilityLabel: String { pick("设置", "Settings") }
    var closeAccessibilityLabel: String { pick("关闭", "Close") }

    func checkItemAccessibilityLabel(_ title: String) -> String {
        pick("添加 \(title)", "Add \(title)")
    }

    var checkedAccessibilityValue: String { pick("已选中", "Selected") }
    var uncheckedAccessibilityValue: String { pick("未选中", "Not selected") }

    // MARK: - 日程面板

    var upcoming: String { pick("接下来", "Upcoming") }
    var loadingAgendaSubtitle: String { pick("正在读取…", "Loading…") }
    var permissionAgendaSubtitle: String { pick("需要访问权限", "Access needed") }
    var nothingScheduled: String { pick("没有安排", "Nothing scheduled") }

    func eventCount(_ count: Int) -> String {
        pick("\(count) 个日程", quantity(count, "event"))
    }

    func todoCount(_ count: Int) -> String {
        pick("\(count) 个待办", quantity(count, "todo"))
    }

    var readingCalendar: String { pick("正在读取日历和提醒事项…", "Reading Calendar and Reminders…") }
    var permissionTitle: String { pick("需要访问「日历」和「提醒事项」", "Calendar and Reminders access needed") }

    var permissionMessage: String {
        pick(
            "在系统设置的「隐私与安全性」中允许 Daycatch 访问后，这里会显示接下来的日程和未完成的待办。",
            "Allow Daycatch in System Settings → Privacy & Security and upcoming events and open reminders will appear here."
        )
    }

    var calendarAccessButton: String { pick("日历权限", "Calendar access") }
    var remindersAccessButton: String { pick("提醒事项权限", "Reminders access") }
    var noAgendaTitle: String { pick("最近没有安排", "Nothing coming up") }

    var noAgendaMessage: String {
        pick("未来一年没有日程，也没有未完成的待办。", "No events in the next year and no open reminders.")
    }

    var recognizeTextButton: String { pick("识别一段文字", "Recognize some text") }
    var eventsColumnTitle: String { pick("日程", "Events") }
    var todosColumnTitle: String { pick("待办", "Todos") }
    var noEventsInYear: String { pick("未来一年没有日程", "No events in the next year") }
    var noOpenTodos: String { pick("没有未完成的待办", "No open reminders") }

    func deniedColumnTitle(_ kind: ItemKind) -> String {
        switch kind {
        case .event: pick("没有「日历」的访问权限", "No access to Calendar")
        case .todo: pick("没有「提醒事项」的访问权限", "No access to Reminders")
        }
    }

    func deniedColumnMessage(_ kind: ItemKind) -> String {
        switch kind {
        case .event:
            pick(
                "在系统设置的「隐私与安全性」中允许 Daycatch 访问后，这里会显示日程。",
                "Allow Daycatch in System Settings → Privacy & Security and your events will appear here."
            )
        case .todo:
            pick(
                "在系统设置的「隐私与安全性」中允许 Daycatch 访问后，这里会显示待办。",
                "Allow Daycatch in System Settings → Privacy & Security and your reminders will appear here."
            )
        }
    }

    func recognizeHint(_ shortcut: String) -> String {
        pick("输入文字识别（\(shortcut)）", "Recognize text (\(shortcut))")
    }

    // MARK: - 事项行

    var overdue: String { pick("已过期", "Overdue") }
    var noDate: String { pick("无日期", "No date") }
    var eventKindChip: String { pick("日程", "Event") }
    var todoKindChip: String { pick("待办", "Todo") }

    func kindLine(_ kind: ItemKind, calendarTitle: String) -> String {
        switch kind {
        case .event: pick("日程 · \(calendarTitle)", "Event · \(calendarTitle)")
        case .todo: pick("待办 · 提醒事项", "Todo · Reminders")
        }
    }

    // MARK: - 行内编辑

    var titlePlaceholder: String { pick("标题", "Title") }
    var locationPlaceholder: String { pick("地点", "Location") }
    var notesPlaceholder: String { pick("备注", "Notes") }
    var startLabel: String { pick("开始", "Start") }
    var endLabel: String { pick("结束", "End") }
    var alertLabel: String { pick("提醒", "Alert") }
    var allDayToggle: String { pick("全天", "All-day") }
    var dueToggle: String { pick("截止", "Due") }
    var specificTimeToggle: String { pick("具体时间", "Specific time") }
    var enableSpecificTimeHint: String { pick("打开「具体时间」后可以加提醒", "Turn on “Specific time” to add an alert") }
    var noAlert: String { pick("不提醒", "None") }

    /// 下拉选项：提前 N 分钟 / N minutes before
    func alertOption(_ minutes: Int, isTodo: Bool = false) -> String {
        if minutes == 0 {
            return isTodo ? pick("截止时", "At due time") : pick("开始时", "At start")
        }
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return pick("提前 \(days) 天", "\(quantity(days, "day")) before")
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return pick("提前 \(hours) 小时", "\(quantity(hours, "hour")) before")
        }
        return pick("提前 \(minutes) 分钟", "\(quantity(minutes, "minute")) before")
    }

    // MARK: - 日期与时长

    var allDay: String { pick("全天", "All day") }

    func allDayUntil(_ date: String) -> String {
        pick("全天 · 至 \(date)", "All day · until \(date)")
    }

    func timeRange(_ start: String, _ end: String) -> String {
        "\(start) – \(end)"
    }

    func dueBy(_ time: String) -> String {
        pick("\(time) 前完成", "Due by \(time)")
    }

    var dueThatDay: String { pick("当天截止", "Due end of day") }
    var noDueTime: String { pick("无截止时间", "No due time") }
    var noDueDate: String { pick("无截止日期", "No due date") }

    func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        guard hours > 0 else { return pick("\(rest) 分钟", quantity(rest, "minute")) }
        if isEnglish {
            if rest == 0 { return quantity(hours, "hour") }
            if rest == 30 { return "\(hours).5 hours" }
            return "\(quantity(hours, "hour")) \(quantity(rest, "minute"))"
        }
        switch rest {
        case 0: return "\(hours) 小时"
        case 30: return "\(hours) 个半小时"
        default: return "\(hours) 小时 \(rest) 分钟"
        }
    }

    /// 事项行下方的「提醒」说明
    func alertReminder(_ minutes: Int, isTodo: Bool = false) -> String {
        if minutes == 0 {
            return isTodo ? pick("截止时提醒", "Alert at due time") : pick("开始时提醒", "Alert at start")
        }
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return pick("提前 \(days) 天提醒", "Alert \(quantity(days, "day")) before")
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return pick("提前 \(hours) 小时提醒", "Alert \(quantity(hours, "hour")) before")
        }
        return pick("提前 \(minutes) 分钟提醒", "Alert \(quantity(minutes, "minute")) before")
    }

    // MARK: - AI 推断提示

    var inferredDateWarning: String {
        pick("原文日期不明确，请核对", "The date isn’t explicit in the text — please check it")
    }

    func inferredTimeWarning(_ time: String) -> String {
        pick("原文未写具体时间，暂按 \(time)", "No time in the text — using \(time)")
    }

    func inferredEndWarning(_ duration: String) -> String {
        pick("原文未写结束时间，暂按 \(duration)", "No end time in the text — using \(duration)")
    }

    func inferredDueTimeWarning(_ time: String) -> String {
        pick("原文未写截止时间，暂按 \(time)", "No due time in the text — using \(time)")
    }

    var inferredDueDayWarning: String {
        pick("原文未写截止时间，暂按当天", "No due time in the text — using that day")
    }

    var inferredLocationWarning: String {
        pick("地点由 AI 推断，请核对", "The location was guessed by the AI — please check it")
    }

    var inferredSomeWarning: String {
        pick("部分信息由 AI 推断，请核对", "Some details were guessed by the AI — please check them")
    }

    // MARK: - 写入与通知

    var toastOpenSettings: String { pick("去设置", "Open Settings") }
    var toastUndoneTitle: String { pick("已撤销", "Undone") }
    var toastFailedTitle: String { pick("操作失败", "Something went wrong") }
    var toastUndoneDetail: String { pick("刚写入的事项已删除", "The items just added were deleted") }

    func addedItemsTitle(_ count: Int) -> String {
        pick("已添加 \(count) 项", "Added \(quantity(count, "item"))")
    }

    func receiptCalendar(title: String, count: Int) -> String {
        pick("日历「\(title)」\(count) 项", "Calendar “\(title)”: \(count)")
    }

    func receiptReminders(title: String, count: Int) -> String {
        pick("提醒事项「\(title)」\(count) 项", "Reminders “\(title)”: \(count)")
    }

    func sourceNote(_ source: String) -> String {
        pick("原文：\n\(source)", "Source:\n\(source)")
    }

    // MARK: - 错误与提示

    var calendarFallbackName: String { pick("日历", "Calendar") }
    var remindersFallbackName: String { pick("提醒事项", "Reminders") }
    var untitledEvent: String { pick("未命名日程", "Untitled event") }
    var untitledTodo: String { pick("未命名待办", "Untitled reminder") }
    var shortcutFallbackName: String { pick("快捷键", "Shortcut") }
    var recognitionFailedTitle: String { pick("识别失败", "Recognition failed") }
    var extracting: String { pick("AI 正在提取日程和待办…", "Extracting events and todos with AI…") }
    var recognizingOnDevice: String { pick("正在本机识别文字…", "Recognizing text on this Mac…") }

    var accessibilityPermissionTitle: String { pick("需要开启「辅助功能」权限", "Accessibility access is needed") }

    func accessibilityPermissionDetail(_ shortcut: String) -> String {
        pick("允许后再按一次 \(shortcut) 即可。", "Allow it, then press \(shortcut) again.")
    }

    var screenRecordingPermissionTitle: String { pick("需要开启「屏幕录制」权限", "Screen Recording access is needed") }
    var screenRecordingPermissionDetail: String {
        pick("允许后重新截图；未生效就重启一次 Daycatch。", "Allow it and capture again; restart Daycatch if it doesn’t take effect.")
    }

    var noSelectedTextTitle: String { pick("没有读到选中的文字", "No selected text found") }

    func noSelectedTextMessage(_ shortcut: String) -> String {
        pick(
            "先在聊天或邮件里选中一段文字，再按 \(shortcut)。如果这个应用不支持读取，可以复制后在菜单栏的输入框里粘贴识别。",
            "Select some text in a chat or email, then press \(shortcut). If Daycatch can’t read the selection in that app, copy the text and paste it into the menu bar input instead."
        )
    }

    var captureFailedTitle: String { pick("无法启动截图", "Couldn’t start the capture") }
    var noTextInScreenshotTitle: String { pick("截图里没有识别到文字", "No text found in the screenshot") }
    var noTextInScreenshotMessage: String { pick("换一个区域再试，或者框选得大一些。", "Try another area or select a larger region.") }
    var textRecognitionFailedTitle: String { pick("文字识别失败", "Text recognition failed") }
    var screenshotUnreadable: String { pick("无法读取截图", "Couldn’t read the screenshot") }

    // AI 错误

    var aiMissingKeyTitle: String { pick("还没有填写 API Key", "No API key yet") }
    var aiMissingKeyMessage: String {
        pick("在设置的「AI 服务」里选择服务商并填写 API Key 后再试。", "Pick a provider and enter your API key in Settings → AI service, then try again.")
    }

    var aiMissingModelTitle: String { pick("还没有填写模型名称", "No model name yet") }
    var aiMissingModelMessage: String { pick("在设置的「AI 服务」里填写模型名称。", "Enter a model name in Settings → AI service.") }

    var aiInvalidBaseURLTitle: String { pick("服务地址无效", "Invalid endpoint") }
    var aiInvalidBaseURLMessage: String { pick("请检查「Base URL」，例如 https://api.example.com/v1。", "Check the Base URL, for example https://api.example.com/v1.") }

    var aiOfflineTitle: String { pick("网络未连接", "No network connection") }
    var aiOfflineMessage: String { pick("连接网络后重试。识别需要把文字发送给 AI 服务。", "Reconnect and try again — recognition sends the text to your AI provider.") }

    var aiTimedOutTitle: String { pick("请求超时", "Request timed out") }
    var aiTimedOutMessage: String { pick("AI 服务响应太慢，可以稍后重试。", "The AI provider is responding slowly. Try again in a moment.") }

    var aiUnauthorizedTitle: String { pick("API Key 无效", "Invalid API key") }
    var aiUnauthorizedMessage: String {
        pick("服务商拒绝了这个 Key，请检查是否填写正确、是否已过期。", "The provider rejected this key. Check that it is correct and hasn’t expired.")
    }

    var aiForbiddenTitle: String { pick("没有访问权限", "Access denied") }

    func aiModelNotFoundTitle(_ model: String) -> String {
        pick("找不到模型「\(model)」", "Model “\(model)” not found")
    }

    var aiModelNotFoundMessage: String {
        pick("请在设置里检查模型名称是否正确，以及当前 Key 是否能使用该模型。", "Double-check the model name in Settings, and whether your key has access to that model.")
    }

    var aiRateLimitedTitle: String { pick("请求太频繁或额度不足", "Too many requests or out of quota") }
    var aiRateLimitedMessage: String { pick("稍等片刻再试，或检查账户余额。", "Wait a moment and try again, or check your account balance.") }

    var aiRefusedTitle: String { pick("AI 拒绝处理这段文字", "The AI declined this text") }
    var aiRefusedMessage: String { pick("可以换一段文字，或在设置里换一个模型。", "Try different text, or pick another model in Settings.") }

    var aiUnparseableTitle: String { pick("AI 返回的内容无法解析", "The AI response couldn’t be parsed") }

    func aiUnparseableMessage(_ detail: String) -> String {
        pick("\(detail)。可以重试一次，或在设置里换一个模型。", "\(detail). Try again, or pick another model in Settings.")
    }

    var calendarsDeniedHelp: String {
        pick(
            "在系统设置的「隐私与安全性 → 日历」中允许 Daycatch 完全访问后再添加。",
            "Allow Daycatch full access in System Settings → Privacy & Security → Calendars, then add again."
        )
    }

    var remindersDeniedHelp: String {
        pick(
            "在系统设置的「隐私与安全性 → 提醒事项」中允许 Daycatch 完全访问后再添加。",
            "Allow Daycatch full access in System Settings → Privacy & Security → Reminders, then add again."
        )
    }

    var noDestinationHelp: String { pick("在设置的「默认写入」中选择一个可写入的列表。", "Pick a writable list in Settings → Default destinations.") }
    var saveFailedHelp: String { pick("请稍后重试。", "Please try again in a moment.") }

    // AIError / CalendarAccessError / ExtractionError 的描述

    var aiErrorMissingAPIKey: String { pick("还没有填写 API Key", "No API key provided") }
    var aiErrorMissingModel: String { pick("还没有填写模型名称", "No model name provided") }
    var aiErrorInvalidBaseURL: String { pick("服务地址（Base URL）无效", "Invalid Base URL") }
    var aiErrorOffline: String { pick("网络未连接", "No network connection") }
    var aiErrorTimedOut: String { pick("请求超时", "Request timed out") }

    func aiErrorNetwork(_ message: String) -> String {
        pick("网络错误：\(message)", "Network error: \(message)")
    }

    var aiErrorUnauthorized: String { pick("API Key 无效", "Invalid API key") }

    func aiErrorForbidden(_ message: String) -> String {
        pick("没有访问权限：\(message)", "Access denied: \(message)")
    }

    func aiErrorModelNotFound(_ model: String) -> String {
        pick("找不到模型「\(model)」", "Model “\(model)” not found")
    }

    var aiErrorRateLimited: String { pick("请求太频繁或额度不足", "Too many requests or out of quota") }

    func aiErrorServer(_ status: Int) -> String {
        pick("AI 服务暂时不可用（HTTP \(status)）", "The AI service is temporarily unavailable (HTTP \(status))")
    }

    func aiErrorBadRequest(_ message: String) -> String {
        pick("请求被拒绝：\(message)", "Request rejected: \(message)")
    }

    var aiErrorRefused: String { pick("AI 拒绝处理这段文字", "The AI declined this text") }

    func aiErrorBadResponse(_ message: String) -> String {
        pick("AI 返回了无法理解的响应：\(message)", "Unreadable AI response: \(message)")
    }

    func aiErrorTextTooLong(_ limit: Int) -> String {
        pick("文字太长（超过 \(limit) 字）", "Text is too long (over \(limit) characters)")
    }

    var responseNotJSON: String { pick("响应不是 JSON", "Response isn’t JSON") }
    var responseMissingContent: String { pick("缺少 content", "Missing content") }
    var responseMissingChoices: String { pick("缺少 choices", "Missing choices") }
    var notHTTPResponse: String { pick("不是 HTTP 响应", "Not an HTTP response") }

    var calendarDenied: String { pick("没有「日历」的访问权限", "No access to Calendar") }
    var remindersDenied: String { pick("没有「提醒事项」的访问权限", "No access to Reminders") }
    var noWritableCalendar: String { pick("找不到可写入的日历", "No writable calendar found") }
    var noWritableReminderList: String { pick("找不到可写入的提醒事项列表", "No writable reminders list found") }

    func saveFailed(_ message: String) -> String {
        pick("写入失败：\(message)", "Couldn’t save: \(message)")
    }

    var extractionEmptyResponse: String { pick("AI 没有返回任何内容", "The AI returned nothing") }
    var extractionNotJSON: String { pick("AI 返回的内容不是有效的 JSON", "The AI response isn’t valid JSON") }

    func extractionInvalidStructure(_ detail: String) -> String {
        pick("AI 返回的结构不符合要求：\(detail)", "The AI response has the wrong structure: \(detail)")
    }

    var parserItemsNotArray: String { pick("items 不是数组", "items is not an array") }
    var parserTopLevelNotObject: String { pick("顶层不是对象", "the top level is not an object") }
    var parserNoUsableItem: String { pick("没有一个事项包含可用的标题和时间", "no item had a usable title and time") }

    // MARK: - 菜单栏

    var menuCloseWindow: String { pick("关闭窗口", "Close Window") }
    var menuQuit: String { pick("退出 Daycatch", "Quit Daycatch") }
    var menuEdit: String { pick("编辑", "Edit") }
    var menuUndo: String { pick("撤销", "Undo") }
    var menuRedo: String { pick("重做", "Redo") }
    var menuCut: String { pick("剪切", "Cut") }
    var menuCopy: String { pick("拷贝", "Copy") }
    var menuPaste: String { pick("粘贴", "Paste") }
    var menuSelectAll: String { pick("全选", "Select All") }
    var statusItemTooltip: String { pick("Daycatch · 日程与待办", "Daycatch · Events and todos") }
}
