import Foundation

/// 事项行里所有展示文字的生成规则（日期列、详情行、AI 推断提示）。
struct ItemFormatter: Sendable {
    struct DateBadge: Equatable, Sendable {
        var month: String
        var day: String
        var weekday: String
    }

    var calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_CN")
        self.calendar = calendar
    }

    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    // MARK: - 日期列

    func badge(for item: ExtractedItem) -> DateBadge? {
        guard let date = item.primaryDate?.date else { return nil }
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        return DateBadge(
            month: "\(parts.month ?? 0)月",
            day: "\(parts.day ?? 0)",
            weekday: Self.weekdays[((parts.weekday ?? 1) - 1) % 7]
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
        let end = item.end?.date ?? start
        if item.isAllDay {
            if calendar.isDate(start, inSameDayAs: end) { return "全天" }
            return "全天 · 至 \(monthDay(end))"
        }
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(time(start)) – \(time(end))"
        }
        return "\(time(start)) – \(monthDay(end)) \(time(end))"
    }

    func dueText(_ item: ExtractedItem) -> String {
        guard let due = item.due else { return "无截止时间" }
        return due.hasTime ? "\(time(due.date)) 前完成" : "当天截止"
    }

    func alarmText(_ minutes: Int, isTodo: Bool = false) -> String {
        if minutes == 0 { return isTodo ? "截止时提醒" : "开始时提醒" }
        if minutes % 1440 == 0 { return "提前 \(minutes / 1440) 天提醒" }
        if minutes % 60 == 0 { return "提前 \(minutes / 60) 小时提醒" }
        return "提前 \(minutes) 分钟提醒"
    }

    // MARK: - AI 推断提示

    func warnings(for item: ExtractedItem) -> [String] {
        let fields = item.inferred
        guard !fields.isEmpty else { return [] }
        var result: [String] = []
        var handled: Set<String> = []

        if fields.contains(InferredField.date), item.primaryDate != nil {
            result.append("原文日期不明确，请核对")
            handled.insert(InferredField.date)
        }
        switch item.kind {
        case .event:
            if fields.contains(InferredField.start) || fields.contains(InferredField.time),
               let start = item.start, !item.isAllDay {
                result.append("原文未写具体时间，暂按 \(time(start.date))")
            }
            handled.formUnion([InferredField.start, InferredField.time])
            if fields.contains(InferredField.end), !item.isAllDay {
                result.append("原文未写结束时间，暂按 \(durationText(item.eventDuration))")
            }
            handled.insert(InferredField.end)
        case .todo:
            if fields.contains(InferredField.due) || fields.contains(InferredField.time), let due = item.due {
                result.append(due.hasTime ? "原文未写截止时间，暂按 \(time(due.date))" : "原文未写截止时间，暂按当天")
            }
            handled.formUnion([InferredField.due, InferredField.time, InferredField.start, InferredField.end])
        }
        if fields.contains(InferredField.location), item.location != nil {
            result.append("地点由 AI 推断，请核对")
        }
        handled.formUnion([InferredField.location, "alarmminutesbefore", "alarm", "allday", "kind", "notes"])
        if !fields.subtracting(handled).isEmpty, result.isEmpty {
            result.append("部分信息由 AI 推断，请核对")
        }
        return result
    }

    func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, let m): return "\(m) 分钟"
        case (let h, 0): return "\(h) 小时"
        case (let h, 30): return "\(h) 个半小时"
        case (let h, let m): return "\(h) 小时 \(m) 分钟"
        }
    }

    // MARK: - 基础格式

    func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    func monthDay(_ date: Date) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }
}
