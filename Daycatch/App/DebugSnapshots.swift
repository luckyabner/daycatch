import AppKit
import SwiftUI

/// `Daycatch --snapshot <目录>`：用示例数据渲染各界面为 PNG，便于对照设计稿检查视觉细节。
@MainActor
enum DebugSnapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accent = Theme.defaultAccent

        let selection = RecognitionModel(source: .selection)
        selection.eventCalendarTitle = "工作"
        selection.defaultAlarmMinutes = 15
        selection.sourceText = "@所有人 周四（11月19日）下午3点在3楼大会议室开 Q4 复盘会，请大家提前准备各自模块的数据，会议预计1个半小时。线上参会的同学用会议号 728 391 045。"
        selection.apply(SampleData.selection)
        save(ResultPanelView(model: selection, actions: PanelActions(), footerHint: "⌘E 编辑 · esc 关闭").daycatchStyle(accent: accent), "1-selection", directory)

        selection.isEditing = true
        save(ResultPanelView(model: selection, actions: PanelActions(), footerHint: "⌘E 编辑 · esc 关闭").daycatchStyle(accent: accent), "1-selection-editing", directory)

        let screenshot = RecognitionModel(source: .screenshot)
        screenshot.eventCalendarTitle = "工作"
        screenshot.apply(SampleData.screenshot)
        save(ResultPanelView(model: screenshot, actions: PanelActions(), footerHint: "⌥⇧S 截图识别 · esc 关闭").daycatchStyle(accent: accent), "2-screenshot", directory)

        let manual = RecognitionModel(source: .manual)
        manual.eventCalendarTitle = "工作"
        manual.inputText = "明天上午10点和王总电话沟通合同细节，下周一前把修改版发给法务"
        manual.apply(SampleData.manual)
        save(ManualPanelView(model: manual, actions: PanelActions(), manualActions: ManualPanelActions()).daycatchStyle(accent: accent), "3-manual", directory)

        let emptyManual = RecognitionModel(source: .manual)
        save(ManualPanelView(model: emptyManual, actions: PanelActions(), manualActions: ManualPanelActions()).daycatchStyle(accent: accent), "3-manual-empty", directory)

        let failed = RecognitionModel(source: .selection)
        failed.phase = .notice(AppController.notice(for: AIError.missingAPIKey))
        save(ResultPanelView(model: failed, actions: PanelActions(), footerHint: "⌘E 编辑 · esc 关闭").daycatchStyle(accent: accent), "1-selection-error", directory)

        let loading = RecognitionModel(source: .selection)
        loading.sourceText = selection.sourceText
        loading.phase = .loading("AI 正在提取日程和待办…")
        save(ResultPanelView(model: loading, actions: PanelActions(), footerHint: "⌘E 编辑 · esc 关闭").daycatchStyle(accent: accent), "1-selection-loading", directory)

        let toast = ToastModel()
        toast.title = "已添加 2 项"
        toast.detail = "日历「工作」1 项 · 提醒事项「工作」1 项"
        save(ToastView(model: toast, undo: {}).daycatchStyle(accent: accent), "3-toast", directory)

        let settings = SettingsStore(defaults: UserDefaults(suiteName: "daycatch.snapshot") ?? .standard)
        let env = SettingsEnvironment(
            calendars: { [] }, reminderLists: { [] }, requestCalendarAccess: {},
            testConnection: { .success("") }, shortcutsChanged: {}, accentChanged: {}, setRecordingShortcut: { _ in }
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

/// 设计稿里的示例数据（只用于 --snapshot）
enum SampleData {
    private static let tz = TimeZone(identifier: "Asia/Shanghai")!

    private static func date(_ text: String) -> ItemDate {
        ISODateParser(timeZone: tz).parse(text)!
    }

    static let selection = ExtractionResult(
        summary: "周四下午 3 楼开 Q4 复盘会，线下线上同时进行；会前需准备各自模块的数据。",
        items: [
            ExtractedItem(kind: .event, title: "Q4 复盘会", start: date("2026-11-19T15:00:00+08:00"), end: date("2026-11-19T16:30:00+08:00"), location: "3 楼大会议室", notes: "线上会议号 728 391 045", alarmMinutesBefore: 15),
            ExtractedItem(kind: .todo, title: "准备各自模块的 Q4 数据", due: date("2026-11-19T15:00:00+08:00")),
        ]
    )

    static let screenshot = ExtractionResult(
        summary: nil,
        items: [
            ExtractedItem(kind: .event, title: "消防知识培训", start: date("2026-11-20T14:00:00+08:00"), end: date("2026-11-20T15:00:00+08:00"), location: "2 楼报告厅", inferred: ["end"]),
            ExtractedItem(kind: .todo, title: "向行政部报送参训名单", due: date("2026-11-21")),
            ExtractedItem(kind: .event, title: "消防疏散演练", start: date("2026-11-24T10:00:00+08:00"), end: date("2026-11-24T11:00:00+08:00"), location: "1 号楼前广场"),
        ]
    )

    static let manual = ExtractionResult(
        summary: nil,
        items: [
            ExtractedItem(kind: .event, title: "与王总电话沟通合同细节", start: date("2026-11-18T10:00:00+08:00"), end: date("2026-11-18T10:30:00+08:00")),
            ExtractedItem(kind: .todo, title: "把合同修改版发给法务", due: date("2026-11-23")),
        ]
    )
}
