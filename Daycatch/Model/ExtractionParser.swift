import Foundation

enum ExtractionError: Error, Equatable, LocalizedError {
    case emptyResponse
    case notJSON
    case invalidStructure(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse: "AI 没有返回任何内容"
        case .notJSON: "AI 返回的内容不是有效的 JSON"
        case .invalidStructure(let detail): "AI 返回的结构不符合要求：\(detail)"
        }
    }
}

/// 把 AI 的原始文本回复解析成 `ExtractionResult`（DESIGN_SPEC §6）。
///
/// 解析是宽容的：能剥掉 ```json 代码块和前后说明文字，单个事项字段不合法时跳过该事项，
/// 只有整体无法理解时才抛错。永远不会因为 AI 返回的内容而崩溃。
struct ExtractionParser: Sendable {
    var timeZone: TimeZone
    var defaultEventDuration: TimeInterval = ExtractedItem.defaultEventDuration

    func parse(_ raw: String) throws -> ExtractionResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExtractionError.emptyResponse }
        guard let jsonText = Self.extractJSON(from: trimmed),
              let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { throw ExtractionError.notJSON }

        let rawItems: [Any]
        var summary: String?
        if let dict = object as? [String: Any] {
            summary = Self.string(dict["summary"])
            if let items = dict["items"] as? [Any] {
                rawItems = items
            } else if dict["items"] == nil || dict["items"] is NSNull {
                // 只有 summary 也算合法：没有识别到事项
                guard dict["kind"] != nil || dict["title"] != nil else {
                    return ExtractionResult(summary: summary, items: [])
                }
                rawItems = [dict]
                summary = nil
            } else {
                throw ExtractionError.invalidStructure("items 不是数组")
            }
        } else if let array = object as? [Any] {
            rawItems = array
        } else {
            throw ExtractionError.invalidStructure("顶层不是对象")
        }

        let items = rawItems.compactMap { ($0 as? [String: Any]).flatMap(parseItem) }
        if items.isEmpty && !rawItems.isEmpty {
            throw ExtractionError.invalidStructure("没有一个事项包含可用的标题和时间")
        }
        return ExtractionResult(summary: summary, items: items)
    }

    // MARK: - 单个事项

    private func parseItem(_ dict: [String: Any]) -> ExtractedItem? {
        guard let title = Self.string(dict["title"]) else { return nil }
        let dates = ISODateParser(timeZone: timeZone)
        let kindText = (Self.string(dict["kind"]) ?? Self.string(dict["type"]) ?? "").lowercased()
        var inferred = Set(((dict["inferred"] as? [Any]) ?? []).compactMap { Self.string($0)?.lowercased() })

        let start = Self.string(dict["start"]).flatMap(dates.parse)
        let end = Self.string(dict["end"]).flatMap(dates.parse)
        let due = Self.string(dict["due"]).flatMap(dates.parse)
        let location = Self.string(dict["location"])
        let notes = Self.string(dict["notes"])
        let alarm = Self.int(dict["alarmMinutesBefore"]).flatMap { $0 >= 0 ? $0 : nil }

        let isTodo = ["todo", "task", "reminder", "待办"].contains(kindText)

        // 未知 kind 且有开始时间时按日程处理；没有开始时间的"日程"无法写进日历，退化为待办
        if isTodo || start == nil {
            return ExtractedItem(
                kind: .todo,
                title: title,
                due: due ?? start,
                location: location,
                notes: notes,
                alarmMinutesBefore: alarm,
                inferred: inferred
            )
        }

        guard let start else { return nil }
        let allDay = (Self.bool(dict["allDay"]) ?? false) || !start.hasTime
        var resolvedEnd: ItemDate
        if allDay {
            let startDay = ItemDate(date: start.date, hasTime: false)
            if let end, end.date >= start.date {
                resolvedEnd = ItemDate(date: end.date, hasTime: false)
            } else {
                resolvedEnd = startDay
            }
            return ExtractedItem(
                kind: .event, title: title, start: startDay, end: resolvedEnd, isAllDay: true,
                location: location, notes: notes, alarmMinutesBefore: alarm, inferred: inferred
            )
        }

        if let end, end.hasTime, end.date > start.date {
            resolvedEnd = end
        } else {
            resolvedEnd = ItemDate(date: start.date.addingTimeInterval(defaultEventDuration), hasTime: true)
            inferred.insert(InferredField.end)
        }
        return ExtractedItem(
            kind: .event, title: title, start: start, end: resolvedEnd, isAllDay: false,
            location: location, notes: notes, alarmMinutesBefore: alarm, inferred: inferred
        )
    }

    // MARK: - 工具

    /// 从回复中找出 JSON：去掉 ``` 代码块，截取第一个 { 到最后一个 }（或 [ ... ]）。
    static func extractJSON(from text: String) -> String? {
        var body = text
        if let fenceStart = body.range(of: "```") {
            let afterFence = body[fenceStart.upperBound...]
            let contentStart = afterFence.firstIndex(of: "\n") ?? afterFence.startIndex
            if let fenceEnd = body[contentStart...].range(of: "```") {
                body = String(body[contentStart..<fenceEnd.lowerBound])
            }
        }
        if let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close {
            return String(body[open...close])
        }
        if let open = body.firstIndex(of: "["), let close = body.lastIndex(of: "]"), open < close {
            return String(body[open...close])
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let text as String: Int(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber: number.boolValue
        case let text as String: ["true", "yes", "1"].contains(text.lowercased())
        default: nil
        }
    }
}
