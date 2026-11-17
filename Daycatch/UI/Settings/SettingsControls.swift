import SwiftUI

/// 设置页的一行：左边标签，右边控件，底部 1px 分隔线。
struct SettingsRow<Label: View, Control: View>: View {
    var verticalPadding: CGFloat = 10
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            label
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, verticalPadding)
        .frame(minHeight: 30 + verticalPadding * 2)
        .overlay(alignment: .bottom) { Divider1px() }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.44)
                .padding(.bottom, 14)
            content
        }
    }
}

struct SettingsNote: View {
    var text: String
    var color = Theme.textSecondary

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }
}

/// 无边框输入框（#F3F3F2，高 30，圆角 8）
struct FlatTextField: View {
    var placeholder: String
    @Binding var text: String
    var width: CGFloat

    var body: some View {
        TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fillControl))
    }
}

/// 密码样式输入框：默认用圆点隐藏，右侧小眼睛按钮切换明文。
struct SecretTextField: View {
    var placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    var width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRevealed ? Localization.strings.hideSecret : Localization.strings.revealSecret)
            .accessibilityLabel(isRevealed ? Localization.strings.hideAPIKey : Localization.strings.showAPIKey)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fillControl))
    }
}

/// 快捷键录制胶囊：点击后按下新组合；esc 取消，⌫ 清除。
struct ShortcutRecorder: View {
    var shortcut: Shortcut?
    var onChange: (Shortcut?) -> Void
    var onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?
    @Environment(\.dcAccent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
            }
            Button(action: toggleRecording) {
                Text(isRecording
                    ? Localization.strings.shortcutRecording
                    : (shortcut?.spacedDisplay ?? Localization.strings.shortcutUnset))
                    .foregroundStyle(isRecording ? accent : (shortcut == nil ? Theme.textSecondary : Theme.textPrimary))
                    .monospacedDigit()
            }
            .buttonStyle(CapsuleButtonStyle())
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty { // esc
            stopRecording()
            return
        }
        if (event.keyCode == 51 || event.keyCode == 117), flags.isEmpty { // ⌫ 清除
            onChange(nil)
            stopRecording()
            return
        }
        let candidate = Shortcut(keyCode: event.keyCode, flags: flags)
        guard candidate.isValidGlobalShortcut else {
            hint = Localization.strings.shortcutNeedsModifier
            return
        }
        onChange(candidate)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}
