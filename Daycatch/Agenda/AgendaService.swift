import AppKit
import EventKit
import Foundation

/// 从 EventKit 读取「接下来的日程」和「未完成的待办」，都按时间由近到远排好。
/// 只读，不写入、不弹权限（权限由 AgendaModel 处理）。
struct AgendaService {
    var store: EKEventStore
    var now: Date = Date()
    var calendar: Calendar = .current

    // MARK: - 日程

    /// 从今天 0 点开始往后一年，跳过已结束和已取消的日程。
    @MainActor
    func events(limit: Int = 200) -> [AgendaEntry] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now.addingTimeInterval(366 * 24 * 3600)

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isDetached && $0.status != .canceled }
            // 正在进行中的日程也算「接下来」
            .filter { ($0.endDate ?? $0.startDate ?? .distantPast) >= now }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        return events.prefix(limit).compactMap(entry(for:))
    }

    private func entry(for event: EKEvent) -> AgendaEntry? {
        guard let start = event.startDate else { return nil }
        return AgendaEntry(
            // 重复日程的多次 occurrence 共用 calendarItemIdentifier，必须加上开始时间才是唯一 ID
            id: Self.identifier(event.calendarItemIdentifier, at: start),
            kind: .event,
            title: Self.clean(event.title) ?? Localization.strings.untitledEvent,
            date: start,
            end: event.endDate,
            isAllDay: event.isAllDay,
            hasTime: !event.isAllDay,
            location: Self.clean(event.location),
            calendarTitle: Self.clean(event.calendar?.title) ?? Localization.strings.calendarFallbackName,
            calendarColorHex: Self.hex(event.calendar?.color),
            isOverdue: false
        )
    }

    // MARK: - 待办

    /// 所有未完成的提醒事项：有截止时间的按时间由近到远（过期的在最前面），
    /// 没有截止时间的排在最后。
    @MainActor
    func reminders(limit: Int = 200) async -> [AgendaEntry] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let now = now
        let calendar = calendar

        return await withCheckedContinuation { (continuation: CheckedContinuation<[AgendaEntry], Never>) in
            // EventKit 在后台队列回调；显式声明成 @Sendable，避免闭包继承 MainActor 隔离后
            // 在后台线程触发 dispatch_assert_queue 崩溃
            let completion: @Sendable ([EKReminder]?) -> Void = { reminders in
                let entries = (reminders ?? [])
                    .filter { !$0.isCompleted }
                    .compactMap { Self.entry(for: $0, now: now, calendar: calendar) }
                    .sorted(by: Self.isOrderedBefore)
                continuation.resume(returning: Array(entries.prefix(limit)))
            }
            _ = store.fetchReminders(matching: predicate, completion: completion)
        }
    }

    private static func entry(for reminder: EKReminder, now: Date, calendar: Calendar) -> AgendaEntry? {
        let components = reminder.dueDateComponents
        let due = components.flatMap { calendar.date(from: $0) }
        let hasTime = components?.hour != nil
        let isOverdue: Bool
        if let due {
            // 只有日期没有时间的待办，当天内不算过期
            isOverdue = due < (hasTime ? now : calendar.startOfDay(for: now))
        } else {
            isOverdue = false
        }
        return AgendaEntry(
            // 同样避免重复提醒的 ID 冲突
            id: identifier(reminder.calendarItemIdentifier, at: due),
            kind: .todo,
            title: clean(reminder.title) ?? Localization.strings.untitledTodo,
            date: due,
            end: nil,
            isAllDay: false,
            hasTime: hasTime,
            location: clean(reminder.location),
            calendarTitle: clean(reminder.calendar?.title) ?? Localization.strings.remindersFallbackName,
            calendarColorHex: hex(reminder.calendar?.color),
            isOverdue: isOverdue
        )
    }

    /// 列表行的唯一标识：EventKit 的 item 标识 + 这一次的时间
    private static func identifier(_ base: String, at date: Date?) -> String {
        guard let date else { return "\(base)@none" }
        return "\(base)@\(Int(date.timeIntervalSince1970))"
    }

    private static func isOrderedBefore(_ lhs: AgendaEntry, _ rhs: AgendaEntry) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?):
            if left != right { return left < right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    // MARK: - 小工具

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func hex(_ color: NSColor?) -> UInt32? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        let red = UInt32(max(0, min(255, (rgb.redComponent * 255).rounded())))
        let green = UInt32(max(0, min(255, (rgb.greenComponent * 255).rounded())))
        let blue = UInt32(max(0, min(255, (rgb.blueComponent * 255).rounded())))
        return (red << 16) | (green << 8) | blue
    }
}
