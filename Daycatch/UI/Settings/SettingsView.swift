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
    var setRecordingShortcut: (Bool) -> Void
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, ai, targets, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .ai: "AI 服务"
        case .targets: "日历"
        case .privacy: "隐私"
        }
    }
}

/// ④ 设置：左侧 200 宽导航，右侧分组（快捷键 / AI 服务 / 默认写入 / 隐私）。
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var env: SettingsEnvironment
    @State private var selectedPane: SettingsPane = .general

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

    var body: some View {
        SettingsSection(title: "快捷键") {
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
            SettingsNote(text: "选中识别需开启“辅助功能”权限，读取失败时自动改用 ⌘C。如果开关已打开仍提示无权限，在列表里用「−」移除 Daycatch 后重新添加。")
            SettingsRow {
                Text("辅助功能权限")
            } control: {
                if accessibilityTrusted {
                    Text("已开启").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else {
                    Button("去开启") {
                        Permissions.promptAccessibility()
                        Permissions.openSystemSettings(.accessibility)
                    }
                    .buttonStyle(CapsuleButtonStyle())
                }
            }
            SettingsRow {
                Text("点缀色")
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
                Text("登录时启动")
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
            conflict = "\(shortcut.spacedDisplay) 已用于「\(other.title)」，请换一个组合。"
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
            launchError = "设置失败：\(error.localizedDescription)"
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

    enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        SettingsSection(title: "AI 服务") {
            SettingsRow {
                Text("服务商")
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
                    Button("测试") { runTest() }
                        .buttonStyle(TextLinkButtonStyle())
                        .lineLimit(1)
                        .fixedSize()
                        .disabled(testState == .running)
                    SecretTextField(placeholder: "粘贴 API Key", text: $apiKey, isRevealed: $isKeyRevealed, width: 240)
                        .onChange(of: apiKey) { _, value in
                            CredentialStore.shared.setAPIKey(value, for: settings.provider)
                            testState = .idle
                        }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            SettingsRow {
                Text("模型")
            } control: {
                FlatTextField(placeholder: settings.provider.defaultModel.isEmpty ? "模型名称" : settings.provider.defaultModel, text: $settings.model, width: 240)
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
            SettingsNote(text: "API Key 只保存在这台 Mac 上，仅你的账户可读。")
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
                Text("测试中…").foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .font(.system(size: 12))
        case .success(let message):
            HStack(spacing: 6) {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                Text("连接正常").foregroundStyle(Theme.successText).lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .help(message)
        case .failure:
            HStack(spacing: 6) {
                Circle().fill(Theme.error).frame(width: 7, height: 7)
                Text("连接失败").foregroundStyle(Theme.error).lineLimit(1)
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
                testState = .failure("\(notice.title)：\(notice.message)")
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

    private static let alarmOptions: [DropdownPicker<Int>.Option] = [
        .init(value: 0, title: "开始时"),
        .init(value: 5, title: "提前 5 分钟"),
        .init(value: 10, title: "提前 10 分钟"),
        .init(value: 15, title: "提前 15 分钟"),
        .init(value: 30, title: "提前 30 分钟"),
        .init(value: 60, title: "提前 1 小时"),
        .init(value: -1, title: "不提醒"),
    ]

    var body: some View {
        SettingsSection(title: "默认写入") {
            SettingsRow {
                HStack(spacing: 10) {
                    KindDot(kind: .event)
                    Text("日程 → 日历")
                }
            } control: {
                if CalendarWriter.hasEventAccess {
                    DropdownPicker(
                        selection: Binding(
                            get: { settings.eventCalendarID ?? calendars.first(where: { $0.title == "工作" })?.id ?? "" },
                            set: { settings.eventCalendarID = $0 }
                        ),
                        options: calendars.map { .init(value: $0.id, title: $0.title) },
                        width: 200,
                        placeholder: "系统默认"
                    )
                } else {
                    grantButton
                }
            }
            SettingsRow {
                HStack(spacing: 10) {
                    KindDot(kind: .todo, ringColor: Theme.textPrimary)
                    Text("待办 → 提醒事项")
                }
            } control: {
                if CalendarWriter.hasReminderAccess {
                    DropdownPicker(
                        selection: Binding(
                            get: { settings.reminderListID ?? lists.first(where: { $0.title == "工作" })?.id ?? "" },
                            set: { settings.reminderListID = $0 }
                        ),
                        options: lists.map { .init(value: $0.id, title: $0.title) },
                        width: 200,
                        placeholder: "系统默认"
                    )
                } else {
                    grantButton
                }
            }
            SettingsRow {
                Text("默认提醒")
            } control: {
                DropdownPicker(
                    selection: Binding(
                        get: { settings.defaultAlarmMinutes ?? -1 },
                        set: { settings.defaultAlarmMinutes = $0 < 0 ? nil : $0 }
                    ),
                    options: Self.alarmOptions,
                    width: 200
                )
            }
            SettingsNote(text: "原文写明提醒时间时以原文为准；默认提醒只用于有具体时间的日程。")
        }
        .onAppear(perform: reload)
    }

    private var grantButton: some View {
        Button("授权访问") {
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

    var body: some View {
        SettingsSection(title: "隐私") {
            SettingsRow {
                Text("截图只在本机识别文字")
            } control: {
                Text("始终开启").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            SettingsRow {
                Text("在日程备注里附上原文")
            } control: {
                Toggle("", isOn: $settings.attachSourceToNotes)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            SettingsRow {
                Text("添加后不保留原文")
            } control: {
                Toggle("", isOn: $settings.discardSourceAfterAdd)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            SettingsNote(text: "只有识别出的文字会发送给你选择的 AI 服务商；截图图片不会离开这台 Mac，识别后立即删除。")
        }
    }
}
