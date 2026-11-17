import AppKit
import EventKit
import SwiftUI

/// `Daycatch --snapshot <目录> [--language english]`：用示例数据渲染各界面为 PNG，
/// 便于对照设计稿检查视觉细节，也用来出 README 里的截图。
@MainActor
enum DebugSnapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accent = Theme.defaultAccent
        let language = Localization.language
        let calendarTitle = language.isEnglish ? "Work" : "工作"

        let selection = RecognitionModel(source: .selection)
        selection.eventCalendarTitle = calendarTitle
        selection.defaultAlarmMinutes = 15
        selection.sourceText = SampleData.selectionSource(language)
        selection.apply(SampleData.selection(language))
        save(ResultPanelView(model: selection, actions: PanelActions(), footerHint: Localization.strings.editHint).daycatchStyle(accent: accent), "1-selection", directory)

        selection.isEditing = true
        save(ResultPanelView(model: selection, actions: PanelActions(), footerHint: Localization.strings.editHint).daycatchStyle(accent: accent), "1-selection-editing", directory)

        let screenshot = RecognitionModel(source: .screenshot)
        screenshot.eventCalendarTitle = calendarTitle
        screenshot.apply(SampleData.screenshot(language))
        save(ResultPanelView(model: screenshot, actions: PanelActions(), footerHint: Localization.strings.screenshotHint("⌥⇧S")).daycatchStyle(accent: accent), "2-screenshot", directory)

        let manual = RecognitionModel(source: .manual)
        manual.eventCalendarTitle = calendarTitle
        manual.inputText = SampleData.manualInput(language)
        manual.apply(SampleData.manual(language))
        save(ManualPanelView(model: manual, actions: PanelActions(), manualActions: ManualPanelActions()).daycatchStyle(accent: accent), "3-manual", directory)

        let emptyManual = RecognitionModel(source: .manual)
        save(ManualPanelView(model: emptyManual, actions: PanelActions(), manualActions: ManualPanelActions()).daycatchStyle(accent: accent), "3-manual-empty", directory)

        let manualEditing = RecognitionModel(source: .manual)
        manualEditing.eventCalendarTitle = calendarTitle
        manualEditing.defaultAlarmMinutes = 15
        manualEditing.inputText = manual.inputText
        manualEditing.apply(SampleData.manual(language))
        manualEditing.isEditing = true
        save(ManualPanelView(model: manualEditing, actions: PanelActions(), manualActions: ManualPanelActions()).daycatchStyle(accent: accent), "3-manual-editing", directory)

        let failed = RecognitionModel(source: .selection)
        failed.phase = .notice(AppController.notice(for: AIError.missingAPIKey))
        save(ResultPanelView(model: failed, actions: PanelActions(), footerHint: Localization.strings.editHint).daycatchStyle(accent: accent), "1-selection-error", directory)

        let loading = RecognitionModel(source: .selection)
        loading.sourceText = selection.sourceText
        loading.phase = .loading(Localization.strings.extracting)
        save(ResultPanelView(model: loading, actions: PanelActions(), footerHint: Localization.strings.editHint).daycatchStyle(accent: accent), "1-selection-loading", directory)

        let toast = ToastModel()
        toast.title = Localization.strings.addedItemsTitle(2)
        toast.detail = "\(Localization.strings.receiptCalendar(title: calendarTitle, count: 1)) · \(Localization.strings.receiptReminders(title: calendarTitle, count: 1))"
        save(ToastView(model: toast, action: {}).daycatchStyle(accent: accent), "3-toast", directory)

        // 点击菜单栏图标打开的日程面板
        let agenda = AgendaModel(store: EKEventStore())
        agenda.hasLoaded = true
        agenda.eventAccess = .granted
        agenda.reminderAccess = .granted
        agenda.events = SampleData.agendaEvents(language)
        agenda.todos = SampleData.agendaTodos(language)
        save(AgendaPanelView(model: agenda, actions: AgendaPanelActions()).daycatchStyle(accent: accent), "5-agenda", directory)

        let agendaSingle = AgendaModel(store: EKEventStore())
        agendaSingle.hasLoaded = true
        agendaSingle.eventAccess = .granted
        agendaSingle.reminderAccess = .granted
        agendaSingle.todos = SampleData.agendaTodos(language)
        save(AgendaPanelView(model: agendaSingle, actions: AgendaPanelActions()).daycatchStyle(accent: accent), "5-agenda-single", directory)

        let agendaEmpty = AgendaModel(store: EKEventStore())
        agendaEmpty.hasLoaded = true
        agendaEmpty.eventAccess = .granted
        agendaEmpty.reminderAccess = .granted
        save(AgendaPanelView(model: agendaEmpty, actions: AgendaPanelActions()).daycatchStyle(accent: accent), "5-agenda-empty", directory)

        let agendaPermission = AgendaModel(store: EKEventStore())
        agendaPermission.hasLoaded = true
        agendaPermission.eventAccess = .denied
        agendaPermission.reminderAccess = .denied
        save(AgendaPanelView(model: agendaPermission, actions: AgendaPanelActions()).daycatchStyle(accent: accent), "5-agenda-permission", directory)

        // 缺权限时的引导卡片（系统自己弹授权对话框，这里只做不打断的说明）
        let hint = ToastModel()
        hint.title = Localization.strings.screenRecordingPermissionTitle
        hint.detail = Localization.strings.screenRecordingPermissionDetail
        hint.actionTitle = Localization.strings.toastOpenSettings
        hint.state = .hint
        save(ToastView(model: hint, action: {}).daycatchStyle(accent: accent), "3-toast-hint", directory)

        let settings = SettingsStore(defaults: UserDefaults(suiteName: "daycatch.snapshot") ?? .standard)
        settings.language = language
        let env = SettingsEnvironment(
            calendars: { [] }, reminderLists: { [] }, requestCalendarAccess: {},
            testConnection: { .success("") }, shortcutsChanged: {}, accentChanged: {}, languageChanged: {},
            setRecordingShortcut: { _ in }
        )
        save(SettingsView(settings: settings, env: env).frame(width: 920, height: 840), "4-settings", directory)
    }

    private static func save<V: View>(_ view: V, _ name: String, _ directory: URL) {
        let hosting = NSHostingView(rootView: view.padding(40).background(Color(hex: 0xE7E6E3)))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.display()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appending(path: "\(name).png"))
        }
        window.orderOut(nil)
    }
}

/// 设计稿里的示例数据（只用于 --snapshot），中英文各一套。
enum SampleData {
    private static let tz = TimeZone(identifier: "Asia/Shanghai")!

    private static func date(_ text: String) -> ItemDate {
        ISODateParser(timeZone: tz).parse(text)!
    }

    private static func moment(_ text: String) -> Date {
        date(text).date
    }

    private static func isEnglish(_ language: AppLanguage) -> Bool {
        language.isEnglish
    }

    // MARK: ① 选中识别

    static func selectionSource(_ language: AppLanguage) -> String {
        isEnglish(language)
            ? "@all Q4 review this Thursday (Nov 19) at 3pm in the 3F large meeting room. Please prepare your module’s data beforehand — the meeting should take about 1.5 hours. Remote folks can dial in with 728 391 045."
            : "@所有人 周四（11月19日）下午3点在3楼大会议室开 Q4 复盘会，请大家提前准备各自模块的数据，会议预计1个半小时。线上参会的同学用会议号 728 391 045。"
    }

    static func selection(_ language: AppLanguage) -> ExtractionResult {
        let english = isEnglish(language)
        return ExtractionResult(
            summary: english
                ? "Q4 review on Thursday at 3pm on the 3F, in person and remote; prepare your module’s data before the meeting."
                : "周四下午 3 楼开 Q4 复盘会，线下线上同时进行；会前需准备各自模块的数据。",
            items: [
                ExtractedItem(
                    kind: .event,
                    title: english ? "Q4 review" : "Q4 复盘会",
                    start: date("2026-11-19T15:00:00+08:00"),
                    end: date("2026-11-19T16:30:00+08:00"),
                    location: english ? "3F large meeting room" : "3 楼大会议室",
                    notes: english ? "Dial-in 728 391 045" : "线上会议号 728 391 045",
                    alarmMinutesBefore: 15
                ),
                ExtractedItem(
                    kind: .todo,
                    title: english ? "Prepare Q4 data for your module" : "准备各自模块的 Q4 数据",
                    due: date("2026-11-19T15:00:00+08:00")
                ),
            ]
        )
    }

    // MARK: ② 截图识别

    static func screenshot(_ language: AppLanguage) -> ExtractionResult {
        let english = isEnglish(language)
        return ExtractionResult(
            summary: nil,
            items: [
                ExtractedItem(
                    kind: .event,
                    title: english ? "Fire safety training" : "消防知识培训",
                    start: date("2026-11-20T14:00:00+08:00"),
                    end: date("2026-11-20T15:00:00+08:00"),
                    location: english ? "2F auditorium" : "2 楼报告厅",
                    inferred: ["end"]
                ),
                ExtractedItem(
                    kind: .todo,
                    title: english ? "Send attendee list to admin" : "向行政部报送参训名单",
                    due: date("2026-11-21")
                ),
                ExtractedItem(
                    kind: .event,
                    title: english ? "Fire drill" : "消防疏散演练",
                    start: date("2026-11-24T10:00:00+08:00"),
                    end: date("2026-11-24T11:00:00+08:00"),
                    location: english ? "Plaza by Building 1" : "1 号楼前广场"
                ),
            ]
        )
    }

    // MARK: ③ 手动输入

    static func manualInput(_ language: AppLanguage) -> String {
        isEnglish(language)
            ? "Call Mr. Wang tomorrow at 10am to go over the contract, and send the revised version to legal by next Monday"
            : "明天上午10点和王总电话沟通合同细节，下周一前把修改版发给法务"
    }

    static func manual(_ language: AppLanguage) -> ExtractionResult {
        let english = isEnglish(language)
        return ExtractionResult(
            summary: nil,
            items: [
                ExtractedItem(
                    kind: .event,
                    title: english ? "Call Mr. Wang about the contract" : "与王总电话沟通合同细节",
                    start: date("2026-11-18T10:00:00+08:00"),
                    end: date("2026-11-18T10:30:00+08:00")
                ),
                ExtractedItem(
                    kind: .todo,
                    title: english ? "Send the revised contract to legal" : "把合同修改版发给法务",
                    due: date("2026-11-23")
                ),
            ]
        )
    }

    // MARK: 日程面板

    static func agendaEvents(_ language: AppLanguage) -> [AgendaEntry] {
        let english = isEnglish(language)
        return [
            AgendaEntry(id: "event-1", kind: .event, title: english ? "Q4 review" : "Q4 复盘会", date: moment("2026-11-19T15:00:00+08:00"), end: moment("2026-11-19T16:30:00+08:00"), isAllDay: false, hasTime: true, location: english ? "3F meeting room" : "3 楼大会议室", calendarTitle: english ? "Work" : "工作", calendarColorHex: 0xE8462E, isOverdue: false),
            AgendaEntry(id: "event-2", kind: .event, title: english ? "Fire safety training" : "消防知识培训", date: moment("2026-11-20T14:00:00+08:00"), end: moment("2026-11-20T15:00:00+08:00"), isAllDay: false, hasTime: true, location: english ? "2F auditorium" : "2 楼报告厅", calendarTitle: english ? "Work" : "工作", calendarColorHex: 0xE8462E, isOverdue: false),
            AgendaEntry(id: "event-3", kind: .event, title: english ? "Product review day" : "产品评审日", date: moment("2026-11-24"), end: moment("2026-11-24"), isAllDay: true, hasTime: false, location: nil, calendarTitle: english ? "Personal" : "个人", calendarColorHex: 0x2F6BFF, isOverdue: false),
            AgendaEntry(id: "event-4", kind: .event, title: english ? "Homepage redesign sync" : "与设计师同步首页改版", date: moment("2026-11-25T10:00:00+08:00"), end: moment("2026-11-25T10:45:00+08:00"), isAllDay: false, hasTime: true, location: english ? "Online" : "线上", calendarTitle: english ? "Personal" : "个人", calendarColorHex: 0x2F6BFF, isOverdue: false),
        ]
    }

    static func agendaTodos(_ language: AppLanguage) -> [AgendaEntry] {
        let english = isEnglish(language)
        let work = english ? "Work" : "工作"
        let personal = english ? "Personal" : "个人"
        return [
            AgendaEntry(id: "todo-1", kind: .todo, title: english ? "Prepare Q4 data for your module" : "准备各自模块的 Q4 数据", date: moment("2026-11-18T18:00:00+08:00"), end: nil, isAllDay: false, hasTime: true, location: nil, calendarTitle: work, calendarColorHex: 0x1F9D55, isOverdue: false),
            AgendaEntry(id: "todo-2", kind: .todo, title: english ? "Send the revised contract to legal" : "把合同修改版发给法务", date: moment("2026-11-19"), end: nil, isAllDay: false, hasTime: false, location: nil, calendarTitle: work, calendarColorHex: 0x1F9D55, isOverdue: false),
            AgendaEntry(id: "todo-3", kind: .todo, title: english ? "Send attendee list to admin" : "向行政部报送参训名单", date: moment("2026-11-21"), end: nil, isAllDay: false, hasTime: false, location: nil, calendarTitle: work, calendarColorHex: 0x1F9D55, isOverdue: false),
            AgendaEntry(id: "todo-4", kind: .todo, title: english ? "Write up the meeting notes" : "整理会议纪要", date: nil, end: nil, isAllDay: false, hasTime: false, location: nil, calendarTitle: personal, calendarColorHex: 0x9A9A9A, isOverdue: false),
        ]
    }
}
