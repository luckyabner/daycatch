import AppKit
import EventKit

enum CalendarAccessError: Error, LocalizedError, Equatable {
    case calendarDenied
    case remindersDenied
    case noCalendar
    case noReminderList
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .calendarDenied: "没有「日历」的访问权限"
        case .remindersDenied: "没有「提醒事项」的访问权限"
        case .noCalendar: "找不到可写入的日历"
        case .noReminderList: "找不到可写入的提醒事项列表"
        case .saveFailed(let message): "写入失败：\(message)"
        }
    }

    var recoveryAction: RecoveryAction? {
        switch self {
        case .calendarDenied: .openCalendarPrivacy
        case .remindersDenied: .openRemindersPrivacy
        case .noCalendar, .noReminderList: .openSettings
        case .saveFailed: nil
        }
    }
}

/// 一次写入的回执，用于"撤销"。
struct WriteReceipt: Sendable {
    var eventIdentifiers: [String]
    var reminderIdentifiers: [String]
    var calendarTitle: String
    var reminderListTitle: String

    var totalCount: Int { eventIdentifiers.count + reminderIdentifiers.count }

    var summary: String {
        var parts: [String] = []
        if !eventIdentifiers.isEmpty { parts.append("日历「\(calendarTitle)」\(eventIdentifiers.count) 项") }
        if !reminderIdentifiers.isEmpty { parts.append("提醒事项「\(reminderListTitle)」\(reminderIdentifiers.count) 项") }
        return parts.joined(separator: " · ")
    }
}

struct WriteOptions {
    var eventCalendarID: String?
    var reminderListID: String?
    var defaultAlarmMinutes: Int?
    /// 附在备注末尾的原文（nil 表示不附）
    var sourceText: String?
}

struct CalendarChoice: Identifiable, Hashable {
    var id: String
    var title: String
    var color: NSColor?
}

/// EventKit 写入：日程 → EKEvent，待办 → EKReminder。
@MainActor
final class CalendarWriter {
    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    var onStoreChanged: (() -> Void)?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onStoreChanged?() }
        }
    }

    // MARK: - 权限

    static var hasEventAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var hasReminderAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func ensureAccess(events: Bool, reminders: Bool) async throws {
        if events, !Self.hasEventAccess {
            guard Self.canRequest(.event) else { throw CalendarAccessError.calendarDenied }
            let granted = await withCheckedContinuation { continuation in
                store.requestFullAccessToEvents { granted, _ in continuation.resume(returning: granted) }
            }
            guard granted else { throw CalendarAccessError.calendarDenied }
        }
        if reminders, !Self.hasReminderAccess {
            guard Self.canRequest(.reminder) else { throw CalendarAccessError.remindersDenied }
            let granted = await withCheckedContinuation { continuation in
                store.requestFullAccessToReminders { granted, _ in continuation.resume(returning: granted) }
            }
            guard granted else { throw CalendarAccessError.remindersDenied }
        }
    }

    /// 已经明确拒绝时系统不会再弹窗，只能引导去系统设置
    private static func canRequest(_ type: EKEntityType) -> Bool {
        switch EKEventStore.authorizationStatus(for: type) {
        case .denied, .restricted: false
        default: true
        }
    }

    // MARK: - 日历列表

    func eventCalendars() -> [CalendarChoice] {
        guard Self.hasEventAccess else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }
    }

    func reminderLists() -> [CalendarChoice] {
        guard Self.hasReminderAccess else { return [] }
        return store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }
    }

    /// 按 ID → 名为"工作"的日历 → 系统默认 的顺序选择。
    func resolveEventCalendar(id: String?) -> EKCalendar? {
        guard Self.hasEventAccess else { return nil }
        let calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        if let id, let match = calendars.first(where: { $0.calendarIdentifier == id }) { return match }
        if let work = calendars.first(where: { $0.title == "工作" || $0.title.lowercased() == "work" }) { return work }
        return store.defaultCalendarForNewEvents ?? calendars.first
    }

    func resolveReminderList(id: String?) -> EKCalendar? {
        guard Self.hasReminderAccess else { return nil }
        let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        if let id, let match = lists.first(where: { $0.calendarIdentifier == id }) { return match }
        if let work = lists.first(where: { $0.title == "工作" || $0.title.lowercased() == "work" }) { return work }
        return store.defaultCalendarForNewReminders() ?? lists.first
    }

    // MARK: - 写入 / 撤销

    func write(_ items: [ExtractedItem], options: WriteOptions) async throws -> WriteReceipt {
        let events = items.filter { $0.kind == .event }
        let todos = items.filter { $0.kind == .todo }
        try await ensureAccess(events: !events.isEmpty, reminders: !todos.isEmpty)

        let calendar = events.isEmpty ? nil : resolveEventCalendar(id: options.eventCalendarID)
        let list = todos.isEmpty ? nil : resolveReminderList(id: options.reminderListID)
        if !events.isEmpty, calendar == nil { throw CalendarAccessError.noCalendar }
        if !todos.isEmpty, list == nil { throw CalendarAccessError.noReminderList }

        var eventIDs: [String] = []
        var reminderIDs: [String] = []
        do {
            for item in events {
                let event = makeEvent(item, calendar: calendar!, options: options)
                try store.save(event, span: .thisEvent, commit: false)
                eventIDs.append(event.calendarItemIdentifier)
            }
            for item in todos {
                let reminder = makeReminder(item, list: list!, options: options)
                try store.save(reminder, commit: false)
                reminderIDs.append(reminder.calendarItemIdentifier)
            }
            try store.commit()
        } catch {
            store.reset()
            throw CalendarAccessError.saveFailed(error.localizedDescription)
        }
        return WriteReceipt(
            eventIdentifiers: eventIDs,
            reminderIdentifiers: reminderIDs,
            calendarTitle: calendar?.title ?? "",
            reminderListTitle: list?.title ?? ""
        )
    }

    func undo(_ receipt: WriteReceipt) throws {
        do {
            for id in receipt.eventIdentifiers {
                if let event = store.calendarItem(withIdentifier: id) as? EKEvent {
                    try store.remove(event, span: .thisEvent, commit: false)
                }
            }
            for id in receipt.reminderIdentifiers {
                if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                    try store.remove(reminder, commit: false)
                }
            }
            try store.commit()
        } catch {
            store.reset()
            throw CalendarAccessError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - 映射

    private func makeEvent(_ item: ExtractedItem, calendar: EKCalendar, options: WriteOptions) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = item.title
        let start = item.start?.date ?? Date()
        event.isAllDay = item.isAllDay
        event.startDate = start
        event.endDate = item.end?.date ?? start.addingTimeInterval(ExtractedItem.defaultEventDuration)
        event.location = item.location
        event.notes = notes(for: item, options: options)
        if !item.isAllDay, let minutes = item.effectiveAlarmMinutes(defaults: options.defaultAlarmMinutes) {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }
        return event
    }

    private func makeReminder(_ item: ExtractedItem, list: EKCalendar, options: WriteOptions) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = item.title
        reminder.location = item.location
        reminder.notes = notes(for: item, options: options)
        if let due = item.due {
            let calendar = Calendar.current
            if due.hasTime {
                var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due.date)
                parts.timeZone = TimeZone.current
                reminder.dueDateComponents = parts
                // 有具体时间才加闹钟，否则提醒事项不会通知；待办默认在截止时提醒
                if let minutes = item.effectiveAlarmMinutes(defaults: 0) {
                    let alarmDate = due.date.addingTimeInterval(TimeInterval(-minutes * 60))
                    reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
                }
            } else {
                reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: due.date)
            }
        }
        return reminder
    }

    private func notes(for item: ExtractedItem, options: WriteOptions) -> String? {
        var parts: [String] = []
        if let notes = item.notes { parts.append(notes) }
        if let source = options.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            parts.append("原文：\n\(source)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
