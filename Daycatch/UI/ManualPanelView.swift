import SwiftUI

struct ManualPanelActions {
    var recognize: () -> Void = {}
    var paste: () -> Void = {}
    var screenshot: () -> Void = {}
    var openSettings: () -> Void = {}
    /// 放弃这次识别结果并清空输入，从头开始
    var discard: () -> Void = {}
}

/// ③ 菜单栏弹窗（宽 420）：输入 → ⌘↩ 识别 → 勾选 → 添加。
struct ManualPanelView: View {
    @Bindable var model: RecognitionModel
    var actions: PanelActions
    var manualActions: ManualPanelActions

    private var t: Strings { Localization.strings }

    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                tabs
                Divider1px()
                inputArea
                resultArea
            }
            .frame(width: 420)
        }
    }

    // MARK: 顶部

    private var tabs: some View {
        HStack(alignment: .center) {
            Text(t.recognizeTab)
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.textPrimary).frame(height: 1.5)
                }
            Spacer()
            Button(action: manualActions.openSettings) {
                SlidersIcon()
                    .frame(width: 16, height: 16)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.settingsAccessibilityLabel)
            .padding(.bottom, 8)
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
    }

    // MARK: 输入

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            InputTextView(
                text: $model.inputText,
                placeholder: t.manualInputPlaceholder,
                focusToken: model.focusInputToken,
                blurToken: model.blurInputToken
            )
            .frame(height: 84)
            .accessibilityLabel(t.manualInputAccessibilityLabel)

            HStack {
                HStack(spacing: 14) {
                    Button(t.paste, action: manualActions.paste)
                    Button(t.screenshot, action: manualActions.screenshot)
                }
                .buttonStyle(TextLinkButtonStyle())
                Spacer()
                if model.isLoading {
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(t.recognizing)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        Button(t.cancel, action: manualActions.discard)
                            .buttonStyle(TextLinkButtonStyle())
                            .help(t.cancelRecognitionHelp)
                    }
                } else {
                    Button(t.recognizeShortcutButton, action: manualActions.recognize)
                        .buttonStyle(TextLinkButtonStyle())
                        .disabled(model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    // MARK: 结果

    @ViewBuilder
    private var resultArea: some View {
        switch model.phase {
        case .idle, .loading:
            EmptyView()
        case .results:
            Divider1px()
            ItemList(model: model, metrics: .manual, maxHeight: 330)
            if let error = model.addError {
                NoticeBody(notice: error, perform: actions.perform, compact: true, horizontalPadding: 22)
                    .padding(.top, 14)
            }
            VStack(spacing: 10) {
                Button(action: actions.add) {
                    Text(addTitle)
                }
                .buttonStyle(PrimaryButtonStyle(height: 42, cornerRadius: 11, fontSize: 14))
                .disabled(!model.canAdd)
                // 和 ① 一样可以行内编辑；「取消」则直接丢掉这次结果和文字，重新开始
                HStack(spacing: 14) {
                    Button(model.isEditing ? t.done : t.edit) {
                        model.isEditing.toggle()
                    }
                    .buttonStyle(TextLinkButtonStyle())
                    .disabled(model.isAdding)
                    .help(model.isEditing ? t.finishEditingHelp : t.startEditingHelp)

                    Button(t.cancel, action: manualActions.discard)
                        .buttonStyle(TextLinkButtonStyle())
                        .disabled(model.isAdding)
                        .help(t.discardResultsHelp)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        case .empty:
            Divider1px()
            NoticeBody(
                notice: Notice(title: t.emptyResultTitle, message: t.emptyResultMessageManual),
                perform: actions.perform,
                compact: false,
                horizontalPadding: 22
            )
            .padding(.vertical, 16)
        case .notice(let notice):
            Divider1px()
            NoticeBody(notice: notice, perform: actions.perform, horizontalPadding: 22)
                .padding(.vertical, 16)
        }
    }

    private var addTitle: String {
        if model.isAdding { return t.addInProgress }
        return model.checkedCount == 0 ? t.nothingSelected : t.addItems(model.checkedCount)
    }
}
