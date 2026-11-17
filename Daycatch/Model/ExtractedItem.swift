import Foundation

enum ItemKind: String, Sendable, Equatable {
    /// 日程 → 日历（EKEvent）
    case event
    /// 待办 → 提醒事项（EKReminder）
    case todo
}

/// 一个时间点。原文可能只给到日期（"11 月 21 日前"），也可能精确到分钟。
struct ItemDate: Sendable, Equatable {
    var date: Date
    var hasTime: Bool
}

/// AI 推断（而不是原文明确给出）的字段名，对应 JSON 里的 `inferred`。
enum InferredField {
    static let start = "start"
    static let end = "end"
    static let due = "due"
    static let date = "date"
    static let time = "time"
    static let location = "location"
}

struct ExtractedItem: Identifiable, Sendable, Equatable {
    let id: UUID
    var kind: ItemKind
    var title: String
    /// 日程开始时间（kind == .event 时必有）
    var start: ItemDate?
    /// 日程结束时间（kind == .event 时必有）
    var end: ItemDate?
    /// 待办截止时间（可为空）
    var due: ItemDate?
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var alarmMinutesBefore: Int?
    var inferred: Set<String>

    init(
        id: UUID = UUID(),
        kind: ItemKind,
        title: String,
        start: ItemDate? = nil,
        end: ItemDate? = nil,
        due: ItemDate? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        alarmMinutesBefore: Int? = nil,
        inferred: Set<String> = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.due = due
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.alarmMinutesBefore = alarmMinutesBefore
        self.inferred = inferred
    }

    /// 日期列显示用的那一天：日程取开始，待办取截止。
    var primaryDate: ItemDate? {
        kind == .event ? start : due
    }
}

struct ExtractionResult: Sendable, Equatable {
    var summary: String?
    var items: [ExtractedItem]
}

// MARK: - 行内编辑

extension ExtractedItem {
    static let defaultEventDuration: TimeInterval = 60 * 60

    /// 改开始时间时保持原有时长。
    mutating func setStart(_ date: Date) {
        let duration = eventDuration
        start = ItemDate(date: date, hasTime: !isAllDay)
        end = ItemDate(date: date.addingTimeInterval(duration), hasTime: !isAllDay)
        inferred.subtract([InferredField.start, InferredField.time, InferredField.date])
    }

    mutating func setEnd(_ date: Date) {
        guard let start else { return }
        let minimumEnd = isAllDay ? start.date : start.date.addingTimeInterval(5 * 60)
        end = ItemDate(date: max(date, minimumEnd), hasTime: !isAllDay)
        inferred.remove(InferredField.end)
    }

    mutating func setAllDay(_ allDay: Bool, calendar: Calendar) {
        guard allDay != isAllDay, let start else { return }
        isAllDay = allDay
        if allDay {
            let day = calendar.startOfDay(for: start.date)
            let endDay = calendar.startOfDay(for: end?.date ?? start.date)
            self.start = ItemDate(date: day, hasTime: false)
            self.end = ItemDate(date: max(day, endDay), hasTime: false)
        } else {
            let base = calendar.startOfDay(for: start.date)
            let nine = calendar.date(byAdding: .hour, value: 9, to: base) ?? base
            self.start = ItemDate(date: nine, hasTime: true)
            self.end = ItemDate(date: nine.addingTimeInterval(Self.defaultEventDuration), hasTime: true)
            inferred.insert(InferredField.time)
            inferred.insert(InferredField.end)
        }
    }

    mutating func setDue(_ date: Date?, hasTime: Bool) {
        due = date.map { ItemDate(date: $0, hasTime: hasTime) }
        inferred.subtract([InferredField.due, InferredField.date, InferredField.time])
    }

    mutating func setKind(_ newKind: ItemKind, now: Date) {
        guard newKind != kind else { return }
        switch newKind {
        case .todo:
            due = start.map { ItemDate(date: $0.date, hasTime: $0.hasTime && !isAllDay) }
            start = nil
            end = nil
            isAllDay = false
        case .event:
            if let due {
                isAllDay = !due.hasTime
                start = due
                end = ItemDate(
                    date: due.hasTime ? due.date.addingTimeInterval(Self.defaultEventDuration) : due.date,
                    hasTime: due.hasTime
                )
                if due.hasTime { inferred.insert(InferredField.end) }
            } else {
                let begin = Self.nextWholeHour(after: now)
                start = ItemDate(date: begin, hasTime: true)
                end = ItemDate(date: begin.addingTimeInterval(Self.defaultEventDuration), hasTime: true)
                isAllDay = false
                inferred.formUnion([InferredField.date, InferredField.time, InferredField.end])
            }
            self.due = nil
        }
        kind = newKind
    }

    var eventDuration: TimeInterval {
        guard let start, let end else { return Self.defaultEventDuration }
        return max(0, end.date.timeIntervalSince(start.date))
    }

    static func nextWholeHour(after date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (interval / 3600).rounded(.down) * 3600 + 3600)
    }
}
