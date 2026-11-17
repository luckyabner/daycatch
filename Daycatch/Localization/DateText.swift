import Foundation

/// 日期 / 时间的显示文案：月份、星期几、时间段、日期徽标。
/// 中文是「11月19日 周四」「15:00」，英文是「Thu, Nov 19」「3:00 PM」。
struct DateText: Sendable {
    var language: AppLanguage
    var calendar: Calendar

    init(language: AppLanguage = Localization.language, timeZone: TimeZone = .current) {
        let language = language.resolved
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = language.locale
        self.calendar = calendar
        self.language = language
    }

    private var strings: Strings { Strings(language: language) }

    // MARK: - 单个日期

    /// "11月" / "Nov"
    func month(_ date: Date) -> String {
        formatted(date, template: "MMM")
    }

    /// "19"
    func day(_ date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }

    /// "周四" / "Thu"
    func weekday(_ date: Date) -> String {
        formatted(date, template: "EEE")
    }

    /// "11月19日" / "Nov 19"
    func monthDay(_ date: Date) -> String {
        formatted(date, template: "MMMd")
    }

    /// "11月17日 周一" / "Mon, Nov 17"
    func dayTitle(_ date: Date) -> String {
        language.isEnglish ? "\(weekday(date)), \(monthDay(date))" : "\(monthDay(date)) \(weekday(date))"
    }

    /// "15:00" / "3:00 PM"
    func clock(_ date: Date) -> String {
        let formatter = makeFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - 时间段

    /// 日程时间；跨天时带上结束日期（"15:00 – 11月20日 01:00"）
    func eventTime(start: Date, end: Date?, isAllDay: Bool) -> String {
        let end = end ?? start
        if isAllDay {
            return calendar.isDate(start, inSameDayAs: end) ? strings.allDay : strings.allDayUntil(monthDay(end))
        }
        if calendar.isDate(start, inSameDayAs: end) {
            return strings.timeRange(clock(start), clock(end))
        }
        return "\(clock(start)) – \(monthDay(end)) \(clock(end))"
    }

    // MARK: - 工具

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = makeFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = calendar.timeZone
        formatter.calendar = calendar
        return formatter
    }
}
