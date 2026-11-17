import SwiftUI

struct ManualPanelActions {
    var recognize: () -> Void = {}
    var paste: () -> Void = {}
    var screenshot: () -> Void = {}
    var openSettings: () -> Void = {}
}

/// ③ 菜单栏弹窗（宽 420）：输入 → ⌘↩ 识别 → 勾选 → 添加。
struct ManualPanelView: View {
    @Bindable var model: RecognitionModel
    var actions: PanelActions
    var manualActions: ManualPanelActions

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
            Text("识别")
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
            .accessibilityLabel("设置")
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
                placeholder: "粘贴或输入包含时间安排的文字",
                focusToken: model.focusInputToken,
                blurToken: model.blurInputToken
            )
            .frame(height: 84)
            .accessibilityLabel("输入包含时间安排的文字")

            HStack {
                HStack(spacing: 14) {
                    Button("粘贴", action: manualActions.paste)
                    Button("截图", action: manualActions.screenshot)
                }
                .buttonStyle(TextLinkButtonStyle())
                Spacer()
                if model.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("识别中…")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    Button("⌘↩ 识别", action: manualActions.recognize)
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
                if model.isEditing {
                    Text("⌘E 完成编辑")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        case .empty:
            Divider1px()
            NoticeBody(
                notice: Notice(title: "没有识别到日程或待办", message: "可以补充时间、地点等信息后再识别一次。"),
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
        if model.isAdding { return "正在添加…" }
        return model.checkedCount == 0 ? "未选择事项" : "添加 \(model.checkedCount) 项"
    }
}
