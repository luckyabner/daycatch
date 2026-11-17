import Foundation

/// 日程面板里的一条：来自「日历」的日程或「提醒事项」里的未完成待办。
/// 只做展示用，不改动 EventKit 里的任何数据。
struct AgendaEntry: Identifiable, Equatable, Sendable {
    var id: String
    var kind: ItemKind
    var title: String
    /// 日程开始时间 / 待办截止时间；nil = 没有截止日期的待办
    var date: Date?
    var end: Date?
    var isAllDay: Bool
    var hasTime: Bool
    var location: String?
    var calendarTitle: String
    var calendarColorHex: UInt32?
    var isOverdue: Bool

    /// 排序用：没有日期的待办排在最后
    var sortDate: Date { date ?? .distantFuture }
}
