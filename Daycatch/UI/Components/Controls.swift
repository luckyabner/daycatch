import SwiftUI

// MARK: - 图标（按设计稿 24×24 viewBox 的 SVG 路径绘制）

/// 对勾 `M5 12.5l4.5 4.5L19 7.5`
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 5 * s, y: 12.5 * s))
        path.addLine(to: CGPoint(x: 9.5 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 7.5 * s))
        return path
    }
}

/// 叉号 `M6 6l12 12M18 6L6 18`
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 6 * s, y: 6 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 18 * s))
        path.move(to: CGPoint(x: 18 * s, y: 6 * s))
        path.addLine(to: CGPoint(x: 6 * s, y: 18 * s))
        return path
    }
}

/// 下拉箭头 `M6 9l6 6 6-6`
struct ChevronDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 6 * s, y: 9 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 15 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 9 * s))
        return path
    }
}

/// 设置图标（两条滑杆）
struct SlidersIcon: View {
    var color = Theme.textSecondary

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            var lines = Path()
            lines.move(to: CGPoint(x: 4 * s, y: 7 * s)); lines.addLine(to: CGPoint(x: 14 * s, y: 7 * s))
            lines.move(to: CGPoint(x: 18 * s, y: 7 * s)); lines.addLine(to: CGPoint(x: 20 * s, y: 7 * s))
            lines.move(to: CGPoint(x: 4 * s, y: 17 * s)); lines.addLine(to: CGPoint(x: 8 * s, y: 17 * s))
            lines.move(to: CGPoint(x: 12 * s, y: 17 * s)); lines.addLine(to: CGPoint(x: 20 * s, y: 17 * s))
            lines.addEllipse(in: CGRect(x: 14 * s, y: 5 * s, width: 4 * s, height: 4 * s))
            lines.addEllipse(in: CGRect(x: 8 * s, y: 15 * s, width: 4 * s, height: 4 * s))
            context.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        }
    }
}

// MARK: - 勾选按钮

/// 22×22 圆形勾选：选中为点缀色填充 + 白色对勾 + 柔和阴影；未选中为 1.5px #CFCFCC 细圈。
struct CheckCircleButton: View {
    var isChecked: Bool
    var label: String
    var action: () -> Void
    @Environment(\.dcAccent) private var accent

    var body: some View {
        Button(action: action) {
            ZStack {
                if isChecked {
                    Circle()
                        .fill(accent)
                        .shadow(color: accent.opacity(0.25), radius: 3, x: 0, y: 2)
                    CheckmarkShape()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .strokeBorder(Theme.uncheckedRing, lineWidth: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.12), value: isChecked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加 \(label)")
        .accessibilityValue(isChecked ? "已选中" : "未选中")
    }
}

/// 类型圆点：实心点缀色 = 日程，空心灰圈 = 待办
struct KindDot: View {
    var kind: ItemKind
    var ringColor = Theme.todoRing
    @Environment(\.dcAccent) private var accent

    var body: some View {
        Group {
            switch kind {
            case .event: Circle().fill(accent)
            case .todo: Circle().strokeBorder(ringColor, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
    }
}

// MARK: - 按钮

/// 主按钮："添加 N 项 ↩"
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 46
    var cornerRadius: CGFloat = 12
    var fontSize: CGFloat = 15
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight { hovering in
            configuration.label
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textPlaceholder)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(configuration.isPressed || (hovering && isEnabled) ? Theme.fillPrimaryButtonHover : Theme.fillPrimaryButton)
                )
                .contentShape(Rectangle())
        }
    }
}

/// 胶囊按钮：撤销、重新框选、快捷键
struct CapsuleButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(Capsule().fill(configuration.isPressed ? Theme.fillControlPressed : Theme.fillControl))
            .contentShape(Capsule())
    }
}

/// 文字按钮：粘贴、截图、查看原文
struct TextLinkButtonStyle: ButtonStyle {
    var color = Theme.textSecondary
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight { hovering in
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(hovering || configuration.isPressed ? Theme.textPrimary : color)
                .contentShape(Rectangle())
        }
    }
}

/// 28×28 圆形关闭按钮
struct CloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CrossShape()
                .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: 10, height: 10)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.fillControl))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}

struct HoverHighlight<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering).onHover { hovering = $0 }
    }
}

// MARK: - 容器

/// 白色面板：圆角 + 设计稿的双层阴影
struct PanelSurface<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var shadowOpacity: Double = 0.16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
                    .shadow(color: .black.opacity(shadowOpacity), radius: 35, x: 0, y: 30)
            )
    }
}

struct Divider1px: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}
