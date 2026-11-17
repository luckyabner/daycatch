import Observation
import SwiftUI

@MainActor
@Observable
final class ToastModel {
    enum State: Equatable {
        case added
        case undoing
        case undone
        case failed(String)
        /// 引导类提示（如缺少系统权限）：不需要确认，也不会抢系统授权弹窗的焦点
        case hint
    }

    var title = ""
    var detail = ""
    var state: State = .added
    /// 卡片右侧按钮的文案：默认「撤销」，引导提示时换成「去设置」之类
    var actionTitle = "撤销"
    var isHovering = false
}

/// 右下角的白色通知卡片（宽 340）：添加成功后带"撤销"，引导提示时带"去设置"。
struct ToastView: View {
    @Bindable var model: ToastModel
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            dot
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.state == .added || model.state == .hint {
                Button(model.actionTitle, action: action)
                    .buttonStyle(CapsuleButtonStyle())
            } else if model.state == .undoing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(width: 340)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
                .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 16)
        )
        .onHover { model.isHovering = $0 }
    }

    @ViewBuilder
    private var dot: some View {
        switch model.state {
        case .failed: Circle().fill(Theme.error).frame(width: 7, height: 7)
        case .undone: Circle().strokeBorder(Theme.todoRing, lineWidth: 1.5).frame(width: 7, height: 7)
        case .hint: KindDot(kind: .todo)
        default: KindDot(kind: .event)
        }
    }

    private var title: String {
        switch model.state {
        case .added, .undoing, .hint: model.title
        case .undone: "已撤销"
        case .failed: "操作失败"
        }
    }

    private var detail: String {
        switch model.state {
        case .added, .undoing, .hint: model.detail
        case .undone: "刚写入的事项已删除"
        case .failed(let message): message
        }
    }
}
