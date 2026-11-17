import Foundation
import Observation
import SwiftUI

/// 所有非敏感设置，存 UserDefaults。API Key 不在这里（见 CredentialStore）。
@MainActor
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    // MARK: AI 服务
    var provider: ProviderKind { didSet { save(provider.rawValue, .provider) } }
    private var models: [String: String] { didSet { save(models, .models) } }
    private var baseURLs: [String: String] { didSet { save(baseURLs, .baseURLs) } }

    // MARK: 默认写入
    var eventCalendarID: String? { didSet { save(eventCalendarID, .eventCalendarID) } }
    var reminderListID: String? { didSet { save(reminderListID, .reminderListID) } }
    /// nil = 不提醒
    var defaultAlarmMinutes: Int? { didSet { save(defaultAlarmMinutes ?? -1, .defaultAlarm) } }

    // MARK: 通用
    /// 界面语言；`.system` 跟随系统首选语言
    var language: AppLanguage { didSet { save(language.rawValue, .language) } }
    var accentHex: String { didSet { save(accentHex, .accent) } }
    private var shortcutStorage: [String: Data] { didSet { save(shortcutStorage, .shortcuts) } }

    // MARK: 隐私
    var attachSourceToNotes: Bool { didSet { save(attachSourceToNotes, .attachSource) } }
    var discardSourceAfterAdd: Bool { didSet { save(discardSourceAfterAdd, .discardSource) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.string(forKey: Key.provider.rawValue).flatMap(ProviderKind.init) ?? .anthropic
        models = defaults.dictionary(forKey: Key.models.rawValue) as? [String: String] ?? [:]
        baseURLs = defaults.dictionary(forKey: Key.baseURLs.rawValue) as? [String: String] ?? [:]
        eventCalendarID = defaults.string(forKey: Key.eventCalendarID.rawValue)
        reminderListID = defaults.string(forKey: Key.reminderListID.rawValue)
        if defaults.object(forKey: Key.defaultAlarm.rawValue) == nil {
            defaultAlarmMinutes = 15
        } else {
            let value = defaults.integer(forKey: Key.defaultAlarm.rawValue)
            defaultAlarmMinutes = value < 0 ? nil : value
        }
        language = defaults.string(forKey: Key.language.rawValue).flatMap(AppLanguage.init) ?? .system
        accentHex = defaults.string(forKey: Key.accent.rawValue) ?? Theme.accentOptions[0]
        shortcutStorage = defaults.dictionary(forKey: Key.shortcuts.rawValue) as? [String: Data] ?? [:]
        attachSourceToNotes = defaults.bool(forKey: Key.attachSource.rawValue)
        discardSourceAfterAdd = defaults.bool(forKey: Key.discardSource.rawValue)
    }

    // MARK: - AI

    var model: String {
        get { models[provider.rawValue] ?? provider.defaultModel }
        set { models[provider.rawValue] = newValue }
    }

    var baseURL: String {
        get { baseURLs[provider.rawValue] ?? provider.defaultBaseURL }
        set { baseURLs[provider.rawValue] = newValue }
    }

    func aiConfiguration() -> AIConfiguration {
        AIConfiguration(provider: provider, apiKey: CredentialStore.shared.apiKey(for: provider), model: model, baseURL: baseURL)
    }

    // MARK: - 快捷键

    /// nil 表示用户清除了该快捷键
    func shortcut(for action: HotkeyAction) -> Shortcut? {
        guard let data = shortcutStorage[action.rawValue] else { return action.defaultShortcut }
        if data.isEmpty { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    func setShortcut(_ shortcut: Shortcut?, for action: HotkeyAction) {
        shortcutStorage[action.rawValue] = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
    }

    var shortcuts: [HotkeyAction: Shortcut] {
        var result: [HotkeyAction: Shortcut] = [:]
        for action in HotkeyAction.allCases {
            if let shortcut = shortcut(for: action) { result[action] = shortcut }
        }
        return result
    }

    // MARK: - 外观

    var accent: Color { Color(hexString: accentHex) ?? Theme.defaultAccent }

    // MARK: - 存储

    private enum Key: String {
        case provider = "ai.provider"
        case models = "ai.models"
        case baseURLs = "ai.baseURLs"
        case eventCalendarID = "write.eventCalendarID"
        case reminderListID = "write.reminderListID"
        case defaultAlarm = "write.defaultAlarmMinutes"
        case language = "general.language"
        case accent = "general.accent"
        case shortcuts = "general.shortcuts"
        case attachSource = "privacy.attachSourceToNotes"
        case discardSource = "privacy.discardSourceAfterAdd"
    }

    private func save(_ value: Any?, _ key: Key) {
        if let value { defaults.set(value, forKey: key.rawValue) } else { defaults.removeObject(forKey: key.rawValue) }
    }
}
