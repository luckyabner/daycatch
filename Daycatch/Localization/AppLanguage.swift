import Foundation

/// 界面语言。`.system` 跟随系统首选语言（中文环境用中文，其余用英文）。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    /// 把 `.system` 解析成真正使用的语言
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    var isEnglish: Bool { resolved == .english }

    /// 日期 / 时间格式化用的 locale（DatePicker、月份、星期几）
    var locale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "zh_CN")
    }
}
