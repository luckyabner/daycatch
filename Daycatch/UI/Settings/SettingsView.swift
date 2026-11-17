import ServiceManagement
import SwiftUI

/// 设置页里需要调用 App 能力的地方，由 SettingsWindowController 注入。
struct SettingsEnvironment {
    var calendars: () -> [CalendarChoice]
    var reminderLists: () -> [CalendarChoice]
    var requestCalendarAccess: () async -> Void
    var testConnection: () async -> Result<String, Error>
    var shortcutsChanged: () -> Void
    var accentChanged: () -> Void
    var languageChanged: () -> Void
    var setRecordingShortcut: (Bool) -> Void
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, ai, targets, privacy
    var id: String { rawValue }

    var title: String {
        let t = Localization.strings
        return switch self {
        case .general: t.paneGeneral
        case .ai: t.paneAI
        case .targets: t.paneCalendar
        case .privacy: t.panePrivacy
        }
    }
}

/// ④ 设置：左侧 200 宽导航，右侧分组（快捷键 / AI 服务 / 默认写入 / 隐私）。
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var env: SettingsEnvironment
    @State private var selectedPane: SettingsPane = .general

    private var t: Strings { Localization.strings }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.divider).frame(width: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        GeneralSection(settings: settings, env: env).id(SettingsPane.general)
                        AISection(settings: settings, env: env).id(SettingsPane.ai)
                        TargetsSection(settings: settings, env: env).id(SettingsPane.targets)
                        PrivacySection(settings: settings).id(SettingsPane.privacy)
                    }
                    .padding(.vertical, 36)
                    .padding(.horizontal, 56)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: selectedPane) { _, pane in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(pane, anchor: .top) }
                }
            }
        }
        .background(Theme.surface)
        .ignoresSafeArea()
        .daycatchStyle(accent: settings.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 留出交通灯的位置
            Color.clear.frame(height: 32)
            Text("Daycatch")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.15)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selectedPane = pane
                } label: {
                    Text(pane.title)
                        .font(.system(size: 13, weight: selectedPane == pane ? .semibold : .regular))
                        .foregroundStyle(selectedPane == pane ? Theme.textPrimary : Theme.textBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedPane == pane ? Theme.fillControl : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(width: 200)
    }
}

// MARK: - 通用

private struct GeneralSection: View {
    @Bindable var settings: SettingsStore
    var env: SettingsEnvironment
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var conflict: String?

    private var t: Strings { Localization.strings }

    var body: some View {
        SettingsSection(title: t.sectionShortcuts) {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                SettingsRow(verticalPadding: 12) {
                    Text(action.title)
                } control: {
                    ShortcutRecorder(
                        shortcut: settings.shortcut(for: action),
                        onChange: { update($0, for: action) },
                        onRecordingChange: { env.setRecordingShortcut($0) }
                    )
                }
            }
            if let conflict {
                SettingsNote(text: conflict).foregroundStyle(Theme.warning)
            }
            SettingsNote(text: t.shortcutsNote)
            SettingsRow {
                Text(t.accessibilityRow)
            } control: {
                if accessibilityTrusted {
                    Text(t.accessibilityEnabled).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    Button(t.accessibilityTurnOn) {
                        Permissions.promptAccessibility()
                        Permissions.openSystemSettings(.accessibility)
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
            }
            SettingsRow {
                Text(t.accentColorRow)
            } control: {
                HStack(spacing: 10) {
                    ForEach(Theme.accentOptions, id: \.self) { hex in
                        Button {
                            settings.accentHex = hex
                            env.accentChanged()
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex) ?? Theme.defaultAccent)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .opacity(settings.accentHex == hex ? 1 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Theme.uncheckedRing, lineWidth: 1)
                                        .padding(-3)
                                        .opacity(settings.accentHex == hex ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 3)
            }
            SettingsRow {
                Text(t.languageRow)
            } control: {
                DropdownPicker(
                    selection: $settings.language,
                    options: AppLanguage.allCases.map { .init(value: $0, title: t.languageName($0)) },
                    width: 200
                )
                .onChange(of: settings.language) { _, _ in env.languageChanged() }
            }
            SettingsRow {
                Text(t.launchAtLoginRow)
            } control: {
                HStack(spacing: 8) {
                    if let launchError {
                        Text(launchError).font(.system(size: 11)).foregroundStyle(Theme.warning).lineLimit(1)
                    }
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
    }

    private func update(_ shortcut: Shortcut?, for action: HotkeyAction) {
        if let shortcut, let other = HotkeyAction.allCases.first(where: { $0 != action && settings.shortcut(for: $0) == shortcut }) {
            conflict = t.shortcutConflict(shortcut.spacedDisplay, action: other.title)
            return
        }
        conflict = nil
        settings.setShortcut(shortcut, for: action)
        env.shortcutsChanged()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = t.launchFailed(error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - AI 服务

private struct AISection: View {
    @Bindable var settings: SettingsStore
    var env: SettingsEnvironment
    @State private var apiKey = ""
    @State private var isKeyRevealed = false
    @State private var testState: TestState = .idle

    private var t: Strings { Localization.strings }

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        SettingsSection(title: t.sectionAIService) {
            SettingsRow {
                Text(t.providerRow)
            } control: {
                DropdownPicker(
                    selection: $settings.provider,
                    options: ProviderKind.allCases.map { .init(value: $0, title: $0.displayName) },
                    width: 240
                )
            }
            SettingsRow {
                Text("API Key")
            } control: {
                // 这一行的右侧控件都是固定宽度，必须声明 fixedSize：否则窗口变窄时
                // SwiftUI 会先压缩「测试」这串弹性文字（先掉行、再被压成 0 宽直接消失）
                HStack(spacing: 10) {
                    testStatus
                    Button(t.testButton) { runTest() }
                        .buttonStyle(TextLinkButtonStyle())
                        .lineLimit(1)
                        .fixedSize()
                        .disabled(testState == .running)
                    SecretTextField(placeholder: t.apiKeyPlaceholder, text: $apiKey, isRevealed: $isKeyRevealed, width: 240)
                        .onChange(of: apiKey) { _, value in
                            CredentialStore.shared.setAPIKey(value, for: settings.provider)
                            testState = .idle
                        }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsRow {
                Text(t.modelRow)
            } control: {
                FlatTextField(placeholder: settings.provider.defaultModel.isEmpty ? t.modelPlaceholder : settings.provider.defaultModel, text: $settings.model, width: 240)
                    .onChange(of: settings.model) { testState = .idle }
            }
            if !settings.provider.usesAnthropicAPI {
                SettingsRow {
                    Text("Base URL")
                } control: {
                    FlatTextField(placeholder: settings.provider.defaultBaseURL.isEmpty ? "https://example.com/v1" : settings.provider.defaultBaseURL, text: $settings.baseURL, width: 240)
                        .onChange(of: settings.baseURL) { testState = .idle }
                }
            }
            if case .failure(let message) = testState {
                SettingsNote(text: message, color: Theme.error)
            }
            SettingsNote(text: t.apiKeyNote)
        }
        .onAppear { apiKey = CredentialStore.shared.apiKey(for: settings.provider) }
        .onChange(of: settings.provider) { _, provider in
            apiKey = CredentialStore.shared.apiKey(for: provider)
            isKeyRevealed = false
            testState = .idle
        }
    }

    /// 紧挨"测试"按钮的结果：绿点 = 正常，红点 = 失败（原因显示在下方）
    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(t.testRunning).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .font(.system(size: 12))
        case .success(let message):
            HStack(spacing: 6) {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                Text(t.testConnected).foregroundStyle(Theme.successText).lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .help(message)
        case .failure:
            HStack(spacing: 6) {
                Circle().fill(Theme.error).frame(width: 7, height: 7)
                Text(t.testFailed).foregroundStyle(Theme.error).lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    private func runTest() {
        testState = .running
        Task {
            switch await env.testConnection() {
            case .success(let message):
                testState = .success(message)
            case .failure(let error):
                let notice = AppController.notice(for: error)
                testState = .failure("\(notice.title)\(t.colonSeparator)\(notice.message)")
            }
        }
    }
}

// MARK: - 默认写入

private struct TargetsSection: View {
    @Bindable var settings: SettingsStore
    var env: SettingsEnvironment
    @State private var calendars: [CalendarChoice] = []
    @State private var lists: [CalendarChoice] = []

    private var t: Strings { Localization.strings }

    private var alarmOptions: [DropdownPicker<Int>.Option] {
        [
            .init(value: 0, title: t.alertOption(0)),
            .init(value: 5, title: t.alertOption(5)),
            .init(value: 10, title: t.alertOption(10)),
            .init(value: 15, title: t.alertOption(15)),
            .init(value: 30, title: t.alertOption(30)),
            .init(value: 60, title: t.alertOption(60)),
            .init(value: -1, title: t.noAlert),
        ]
    }

    var body: some View {
        SettingsSection(title: t.sectionDefaultTargets) {
            SettingsRow {
                HStack(spacing: 10) {
                    KindDot(kind: .event)
                    Text(t.eventsTargetRow)
                }
            } control: {
                if CalendarWriter.hasEventAccess {
                    DropdownPicker(
                        selection: Binding(
                            get: { settings.eventCalendarID ?? calendars.first(where: { isWorkCalendar($0.title) })?.id ?? "" },
                            set: { settings.eventCalendarID = $0 }
                        ),
                        options: calendars.map { .init(value: $0.id, title: $0.title) },
                        width: 200,
                        placeholder: t.systemDefault
                    )
                } else {
                    grantButton
                }
            }
            SettingsRow {
                HStack(spacing: 10) {
                    KindDot(kind: .todo, ringColor: Theme.textPrimary)
                    Text(t.todosTargetRow)
                }
            } control: {
                if CalendarWriter.hasReminderAccess {
                    DropdownPicker(
                        selection: Binding(
                            get: { settings.reminderListID ?? lists.first(where: { isWorkCalendar($0.title) })?.id ?? "" },
                            set: { settings.reminderListID = $0 }
                        ),
                        options: lists.map { .init(value: $0.id, title: $0.title) },
                        width: 200,
                        placeholder: t.systemDefault
                    )
                } else {
                    grantButton
                }
            }
            SettingsRow {
                Text(t.defaultAlertRow)
            } control: {
                DropdownPicker(
                    selection: Binding(
                        get: { settings.defaultAlarmMinutes ?? -1 },
                        set: { settings.defaultAlarmMinutes = $0 < 0 ? nil : $0 }
                    ),
                    options: alarmOptions,
                    width: 200
                )
            }
            SettingsNote(text: t.defaultAlertNote)
        }
        .onAppear(perform: reload)
    }

    /// 和 CalendarWriter 的兜底逻辑一致：优先选名为「工作 / Work」的列表
    private func isWorkCalendar(_ title: String) -> Bool {
        title == "工作" || title.lowercased() == "work"
    }

    private var grantButton: some View {
        Button(t.grantAccessButton) {
            Task {
                await env.requestCalendarAccess()
                reload()
            }
        }
        .buttonStyle(CapsuleButtonStyle())
    }

    private func reload() {
        calendars = env.calendars()
        lists = env.reminderLists()
    }
}

// MARK: - 隐私

private struct PrivacySection: View {
    @Bindable var settings: SettingsStore

    private var t: Strings { Localization.strings }

    var body: some View {
        SettingsSection(title: t.sectionPrivacy) {
            SettingsRow {
                Text(t.privacyLocalRecognitionRow)
            } control: {
                Text(t.privacyAlwaysOn).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            SettingsRow {
                Text(t.privacyAttachSourceRow)
            } control: {
                Toggle("", isOn: $settings.attachSourceToNotes)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            SettingsRow {
                Text(t.privacyDiscardSourceRow)
            } control: {
                Toggle("", isOn: $settings.discardSourceAfterAdd)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            SettingsNote(text: t.privacyNote)
        }
    }
}
