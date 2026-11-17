import Foundation
import Observation

enum RecognitionSource: Sendable {
    case selection
    case screenshot
    case manual

    var label: String {
        let t = Localization.strings
        return switch self {
        case .selection: t.sourceSelection
        case .screenshot: t.sourceScreenshot
        case .manual: t.sourceManual
        }
    }

    var metrics: RowMetrics {
        switch self {
        case .selection: .selection
        case .screenshot: .screenshot
        case .manual: .manual
        }
    }
}

/// 失败/引导状态下可提供的操作按钮。
enum RecoveryAction: Equatable, Sendable {
    case retry
    case openSettings
    case openAccessibilitySettings
    case openScreenRecordingSettings
    case openCalendarPrivacy
    case openRemindersPrivacy
    case recapture
    case openManualInput

    var title: String {
        let t = Localization.strings
        return switch self {
        case .retry: t.retry
        case .openSettings: t.openSettings
        case .openAccessibilitySettings, .openScreenRecordingSettings, .openCalendarPrivacy, .openRemindersPrivacy: t.openSystemSettings
        case .recapture: t.recapture
        case .openManualInput: t.manualInput
        }
    }
}

struct Notice: Equatable, Sendable {
    var title: String
    var message: String
    var actions: [RecoveryAction] = []
}

struct ItemRowState: Identifiable, Equatable {
    var item: ExtractedItem
    var isChecked = true
    var id: UUID { item.id }
}

/// 一次识别会话的全部界面状态（三种入口共用）。
@MainActor
@Observable
final class RecognitionModel {
    enum Phase: Equatable {
        case idle
        case loading(String)
        case results
        case empty
        case notice(Notice)
    }

    let source: RecognitionSource
    var phase: Phase = .idle
    /// 送去识别的原文（截图则为 OCR 文字）
    var sourceText = ""
    var summary: String?
    var rows: [ItemRowState] = []
    var isEditing = false
    var showsSourceText = false
    var isAdding = false
    /// 写入失败等提示（不替换结果列表）
    var addError: Notice?

    /// ③ 手动输入框里的文字
    var inputText = ""
    /// 递增以请求输入框获得焦点
    var focusInputToken = 0
    /// 递增以请求输入框失去焦点（识别完成后让 ↩ 用于添加）
    var blurInputToken = 0

    /// 日程所在日历的名字，显示在 "日程 · 工作"
    var eventCalendarTitle = Localization.strings.calendarFallbackName
    var defaultAlarmMinutes: Int?

    var task: Task<Void, Never>?

    init(source: RecognitionSource) {
        self.source = source
    }

    var checkedCount: Int { rows.filter(\.isChecked).count }
    var checkedItems: [ExtractedItem] { rows.filter(\.isChecked).map(\.item) }
    var isLoading: Bool { if case .loading = phase { true } else { false } }
    var canAdd: Bool { phase == .results && checkedCount > 0 && !isAdding }

    func apply(_ result: ExtractionResult) {
        summary = result.summary
        rows = result.items.map { ItemRowState(item: $0) }
        isEditing = false
        addError = nil
        phase = rows.isEmpty ? .empty : .results
    }

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        sourceText = ""
        summary = nil
        rows = []
        isEditing = false
        showsSourceText = false
        isAdding = false
        addError = nil
    }

    /// ③ 「取消」：丢掉这次识别结果并清空输入框，从头开始；
    /// 正在识别时也用它中断请求
    func discardResults() {
        reset()
        inputText = ""
        focusInputToken += 1
    }

    func toggle(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isChecked.toggle()
    }
}
