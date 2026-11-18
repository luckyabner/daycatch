import Foundation

/// 事项行里所有展示文字的生成规则（日期列、详情行、AI 推断提示）。
struct ItemFormatter: Sendable {
    struct DateBadge: Equatable, Sendable {
        var month: String
        var day: String
        var weekday: String
    }

    var calendar: Calendar
    private let dateText: DateText
    private let strings: Strings

    init(timeZone: TimeZone = .current, language: AppLanguage = Localization.language) {
        let dateText = DateText(language: language, timeZone: timeZone)
        self.dateText = dateText
        self.calendar = dateText.calendar
        self.strings = Strings(language: language)
    }

    // MARK: - 日期列

    func badge(for item: ExtractedItem) -> DateBadge? {
        guard let date = item.primaryDate?.date else { return nil }
        return DateBadge(
            month: dateText.month(date),
            day: dateText.day(date),
            weekday: dateText.weekday(date)
        )
    }

    // MARK: - 详情行

    /// - Parameter alarmMinutes: 实际会写入的提醒（AI 给的优先，否则用设置里的默认值）
    func detailLines(for item: ExtractedItem, alarmMinutes: Int?) -> [String] {
        var lines: [String] = []
        switch item.kind {
        case .event:
            var first = [eventTimeText(item)]
            if let location = item.location { first.append(location) }
            lines.append(first.joined(separator: " · "))

            var second: [String] = []
            if let notes = item.notes { second.append(notes) }
            if !item.isAllDay, let alarmMinutes { second.append(alarmText(alarmMinutes)) }
            if !second.isEmpty { lines.append(second.joined(separator: " · ")) }
        case .todo:
            var first = [dueText(item)]
            if let location = item.location { first.append(location) }
            lines.append(first.joined(separator: " · "))
            var second: [String] = []
            if let notes = item.notes { second.append(notes) }
            // 待办只有具体到时间才会写闹钟
            if item.due?.hasTime == true, let alarmMinutes { second.append(alarmText(alarmMinutes, isTodo: true)) }
            if !second.isEmpty { lines.append(second.joined(separator: " · ")) }
        }
        return lines
    }

    func eventTimeText(_ item: ExtractedItem) -> String {
        guard let start = item.start?.date else { return "" }
        return dateText.eventTime(start: start, end: item.end?.date, isAllDay: item.isAllDay)
    }

    func dueText(_ item: ExtractedItem) -> String {
        guard let due = item.due else { return strings.noDueTime }
        return due.hasTime ? strings.dueAt(dateText.clock(due.date)) : strings.dueThatDay
    }

    func alarmText(_ minutes: Int, isTodo: Bool = false) -> String {
        strings.alertReminder(minutes, isTodo: isTodo)
    }

    // MARK: - AI 推断提示

    func warnings(for item: ExtractedItem) -> [String] {
        let fields = item.inferred
        guard !fields.isEmpty else { return [] }
        var result: [String] = []
        var handled: Set<String> = []

        if fields.contains(InferredField.date), item.primaryDate != nil {
            result.append(strings.inferredDateWarning)
            handled.insert(InferredField.date)
        }
        switch item.kind {
        case .event:
            if fields.contains(InferredField.start) || fields.contains(InferredField.time),
               let start = item.start, !item.isAllDay {
                result.append(strings.inferredTimeWarning(dateText.clock(start.date)))
            }
            handled.formUnion([InferredField.start, InferredField.time])
            if fields.contains(InferredField.end), !item.isAllDay {
                result.append(strings.inferredEndWarning(durationText(item.eventDuration)))
            }
            handled.insert(InferredField.end)
        case .todo:
            if fields.contains(InferredField.due) || fields.contains(InferredField.time), let due = item.due {
                result.append(due.hasTime
                    ? strings.inferredDueTimeWarning(dateText.clock(due.date))
                    : strings.inferredDueDayWarning)
            }
            handled.formUnion([InferredField.due, InferredField.time, InferredField.start, InferredField.end])
        }
        if fields.contains(InferredField.location), item.location != nil {
            result.append(strings.inferredLocationWarning)
        }
        handled.formUnion([InferredField.location, "alarmminutesbefore", "alarm", "allday", "kind", "notes"])
        if !fields.subtracting(handled).isEmpty, result.isEmpty {
            result.append(strings.inferredSomeWarning)
        }
        return result
    }

    func durationText(_ interval: TimeInterval) -> String {
        strings.duration(Int((interval / 60).rounded()))
    }

    // MARK: - 基础格式

    func time(_ date: Date) -> String {
        dateText.clock(date)
    }

    func monthDay(_ date: Date) -> String {
        dateText.monthDay(date)
    }
}
