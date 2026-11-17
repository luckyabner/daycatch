import Foundation

/// 解析 AI 返回的时间字符串。
///
/// 支持：
/// - `2026-11-19T15:00:00+08:00` / `...Z` / 带毫秒 / 不带秒
/// - 不带时区的 `2026-11-19T15:00:00`、`2026-11-19 15:00`（按传入时区解释）
/// - 只有日期的 `2026-11-19`（hasTime = false，取该时区当天 00:00）
struct ISODateParser: Sendable {
    var timeZone: TimeZone

    private static let offsetFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mmXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXX",
        "yyyy-MM-dd'T'HH:mmXX",
    ]

    private static let localFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
    ]

    func parse(_ raw: String) -> ItemDate? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.count == 10, let date = parse(text, format: "yyyy-MM-dd") {
            return ItemDate(date: date, hasTime: false)
        }
        for format in Self.offsetFormats {
            if let date = parse(text, format: format) {
                return ItemDate(date: date, hasTime: true)
            }
        }
        for format in Self.localFormats {
            if let date = parse(text, format: format) {
                return ItemDate(date: date, hasTime: true)
            }
        }
        return nil
    }

    private func parse(_ text: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter.date(from: text)
    }
}
