import SwiftUI

/// 面板上的用户操作，由 AppController 实现。
struct PanelActions {
    var add: () -> Void = {}
    var close: () -> Void = {}
    var perform: (RecoveryAction) -> Void = { _ in }
}

/// ① 选中识别 / ② 截图识别 的浮动结果面板（宽 480 / 520）。
struct ResultPanelView: View {
    @Bindable var model: RecognitionModel
    var actions: PanelActions
    var footerHint: String

    private var width: CGFloat { model.source == .screenshot ? 520 : 480 }
    private var metrics: RowMetrics { model.source.metrics }

    var body: some View {
        PanelSurface(shadowOpacity: model.source == .screenshot ? 0.22 : 0.16) {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch model.phase {
                case .idle, .loading:
                    loadingBody
                case .results:
                    resultsBody
                case .empty:
                    NoticeBody(
                        notice: Notice(
                            title: "没有识别到日程或待办",
                            message: "AI 没有在这段文字里找到时间安排。",
                            actions: [.retry]
                        ),
                        perform: actions.perform
                    )
                    sourceTextSection
                    footer(showsLink: !model.sourceText.isEmpty, showsButton: false)
                case .notice(let notice):
                    NoticeBody(notice: notice, perform: actions.perform)
                    sourceTextSection
                    footer(showsLink: !model.sourceText.isEmpty, showsButton: false)
                }
            }
            .frame(width: width)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.source.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.52)
            }
            Spacer(minLength: 16)
            CloseButton(action: actions.close)
        }
        .padding(.top, 24)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    private var title: String {
        switch model.phase {
        case .idle, .loading: "正在识别…"
        case .results: "识别到 \(model.rows.count) 项"
        case .empty: "识别到 0 项"
        case .notice: model.source == .screenshot ? "截图识别" : "选中识别"
        }
    }

    // MARK: 加载

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(loadingMessage)
                    .foregroundStyle(Theme.textBody)
            }
            if !model.sourceText.isEmpty {
                Text(model.sourceText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private var loadingMessage: String {
        if case .loading(let message) = model.phase { return message }
        return "正在识别…"
    }

    // MARK: 结果

    @ViewBuilder
    private var resultsBody: some View {
        if model.source == .selection, let summary = model.summary {
            Text(summary)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        Divider1px()
        ItemList(model: model, metrics: metrics, maxHeight: 440)
        if let error = model.addError {
            NoticeBody(notice: error, perform: actions.perform, compact: true)
                .padding(.top, 16)
        }
        sourceTextSection
        footer(showsLink: true, showsButton: true)
    }

    @ViewBuilder
    private var sourceTextSection: some View {
        if model.showsSourceText, !model.sourceText.isEmpty {
            SourceTextBox(text: model.sourceText)
                .padding(.horizontal, 28)
                .padding(.top, 16)
        }
    }

    // MARK: 底部

    private func footer(showsLink: Bool, showsButton: Bool) -> some View {
        VStack(spacing: 14) {
            if showsButton {
                Button(action: actions.add) {
                    HStack(spacing: 10) {
                        Text(addTitle)
                        Text("↩")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPlaceholder)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canAdd)
            }
            HStack {
                if showsLink {
                    Button(model.showsSourceText ? "收起原文" : sourceLinkTitle) {
                        model.showsSourceText.toggle()
                    }
                    .buttonStyle(TextLinkButtonStyle())
                    if model.source == .screenshot {
                        Text("·").foregroundStyle(Theme.textSecondary).font(.system(size: 12))
                        Button("重新框选") { actions.perform(.recapture) }
                            .buttonStyle(TextLinkButtonStyle())
                    }
                }
                Spacer()
                Text(model.isEditing ? "⌘E 完成编辑 · esc 关闭" : footerHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private var sourceLinkTitle: String {
        model.source == .screenshot ? "查看识别文字" : "查看原文"
    }

    private var addTitle: String {
        if model.isAdding { return "正在添加…" }
        return model.checkedCount == 0 ? "未选择事项" : "添加 \(model.checkedCount) 项"
    }
}

// MARK: - 共享子视图

/// 事项列表；超过最大高度时滚动。
struct ItemList: View {
    @Bindable var model: RecognitionModel
    var metrics: RowMetrics
    var maxHeight: CGFloat
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach($model.rows) { $row in
                    ItemRowView(
                        row: $row,
                        metrics: metrics,
                        calendarTitle: model.eventCalendarTitle,
                        defaultAlarmMinutes: model.defaultAlarmMinutes,
                        isEditing: model.isEditing
                    )
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
        .scrollDisabled(contentHeight <= maxHeight)
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}

/// 失败、引导、空结果的说明区。
struct NoticeBody: View {
    var notice: Notice
    var perform: (RecoveryAction) -> Void
    var compact = false
    var horizontalPadding: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text(notice.title)
                .font(.system(size: compact ? 13 : 17, weight: .semibold))
                .foregroundStyle(compact ? Theme.error : Theme.textPrimary)
            if !notice.message.isEmpty {
                Text(notice.message)
                    .font(.system(size: compact ? 12 : 13))
                    .foregroundStyle(Theme.textBody)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !notice.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(notice.actions, id: \.self) { action in
                        Button(action.title) { perform(action) }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }
                .padding(.top, compact ? 2 : 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, compact ? 0 : 4)
    }
}

extension RecoveryAction: Hashable {}

struct SourceTextBox: View {
    var text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textBody)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: 140)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fillControl))
    }
}
