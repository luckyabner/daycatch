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
    }

    var title = ""
    var detail = ""
    var state: State = .added
    var isHovering = false
}

/// 添加成功后右下角的白色通知卡片（宽 340），带"撤销"。
struct ToastView: View {
    @Bindable var model: ToastModel
    var undo: () -> Void

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
            if model.state == .added {
                Button("撤销", action: undo)
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
        default: KindDot(kind: .event)
        }
    }

    private var title: String {
        switch model.state {
        case .added, .undoing: model.title
        case .undone: "已撤销"
        case .failed: "操作失败"
        }
    }

    private var detail: String {
        switch model.state {
        case .added, .undoing: model.detail
        case .undone: "刚写入的事项已删除"
        case .failed(let message): message
        }
    }
}
