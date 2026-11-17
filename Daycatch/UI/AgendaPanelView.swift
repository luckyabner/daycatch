import SwiftUI

struct AgendaPanelActions {
    var recognize: () -> Void = {}
    var openSettings: () -> Void = {}
    var openPrivacy: (Permissions.Pane) -> Void = { _ in }
    /// 「输入识别」按钮的提示文字（带上快捷键）
    var recognizeHint = "输入文字识别"
}

/// 点击菜单栏图标打开的日程面板：左栏日程、右栏待办，都按时间由近到远排列，
/// 列表填满容器，超出的部分滚动。某一栏为空时只显示另一栏。
struct AgendaPanelView: View {
    @Bindable var model: AgendaModel
    var actions: AgendaPanelActions

    /// 两栏时单栏的宽度
    static let columnWidth: CGFloat = 296
    static let singleWidth: CGFloat = 360
    static let height: CGFloat = 430
    private static let horizontalPadding: CGFloat = 16

    /// 面板宽度：两栏 / 一栏
    static func width(columns: Int) -> CGFloat {
        columns == 2
            ? horizontalPadding * 4 + columnWidth * 2 + 1
            : singleWidth
    }

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                header
                Divider1px()
                content
            }
            .frame(width: Self.width(columns: model.columnCount), height: Self.height)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("接下来")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.44)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                CornerIconButton(label: "输入文字识别", help: actions.recognizeHint, action: actions.recognize) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                }
                CornerIconButton(label: "设置", help: "设置", action: actions.openSettings) {
                    SlidersIcon()
                        .frame(width: 15, height: 15)
                        .frame(width: 26, height: 26)
                }
            }
            .padding(.top, 1)
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var subtitle: String {
        let day = AgendaText.dayTitle(Date())
        guard model.hasLoaded else { return "\(day) · 正在读取…" }
        if model.needsUnifiedPermission { return "\(day) · 需要访问权限" }
        var parts = [day]
        if model.eventCount > 0 { parts.append("\(model.eventCount) 个日程") }
        if model.todoCount > 0 { parts.append("\(model.todoCount) 个待办") }
        if parts.count == 1 { parts.append("没有安排") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            placeholder {
                ProgressView().controlSize(.small)
                Text("正在读取日历和提醒事项…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if model.needsUnifiedPermission {
            unifiedPermission
        } else if model.isEmpty {
            emptyState
        } else {
            columns
        }
    }

    private var columns: some View {
        let twoColumns = model.showsEvents && model.showsTodos
        let width = twoColumns ? Self.columnWidth : Self.singleWidth - Self.horizontalPadding * 2
        return HStack(spacing: 0) {
            if model.showsEvents {
                AgendaColumnView(
                    title: "日程",
                    kind: .event,
                    column: model.eventsColumn,
                    itemCount: model.eventCount,
                    width: width,
                    openPrivacy: { actions.openPrivacy(.calendars) }
                )
                .padding(.horizontal, Self.horizontalPadding)
            }
            if twoColumns {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            if model.showsTodos {
                AgendaColumnView(
                    title: "待办",
                    kind: .todo,
                    column: model.todosColumn,
                    itemCount: model.todoCount,
                    width: width,
                    openPrivacy: { actions.openPrivacy(.reminders) }
                )
                .padding(.horizontal, Self.horizontalPadding)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var unifiedPermission: some View {
        placeholder {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textSecondary)
            Text("需要访问「日历」和「提醒事项」")
                .font(.system(size: 14, weight: .semibold))
            Text("在系统设置的「隐私与安全性」中允许 Daycatch 访问后，这里会显示接下来的日程和未完成的待办。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            HStack(spacing: 8) {
                Button("日历权限") { actions.openPrivacy(.calendars) }
                Button("提醒事项权限") { actions.openPrivacy(.reminders) }
            }
            .buttonStyle(CapsuleButtonStyle())
            .padding(.top, 4)
        }
    }

    private var emptyState: some View {
        placeholder {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textSecondary)
            Text("最近没有安排")
                .font(.system(size: 14, weight: .semibold))
            Text("未来一年没有日程，也没有未完成的待办。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("识别一段文字", action: actions.recognize)
                .buttonStyle(CapsuleButtonStyle())
                .padding(.top, 4)
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
    }
}

// MARK: - 一栏

private struct AgendaColumnView: View {
    var title: String
    var kind: ItemKind
    var column: AgendaModel.Column
    var itemCount: Int
    var width: CGFloat
    var openPrivacy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                KindDot(kind: kind)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .frame(height: 14)
            .padding(.horizontal, 18)
            .padding(.top, 11)
            .padding(.bottom, 9)

            Divider1px()

            switch column {
            case .loading:
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .items(let entries):
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            AgendaRowView(entry: entry)
                            if index < entries.count - 1 {
                                Divider1px().padding(.leading, 18)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

            case .empty:
                Text(kind == .event ? "未来一年没有日程" : "没有未完成的待办")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .denied:
                VStack(spacing: 10) {
                    Text(kind == .event ? "没有「日历」的访问权限" : "没有「提醒事项」的访问权限")
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("在系统设置的「隐私与安全性」中允许 Daycatch 访问后，这里会显示\(kind == .event ? "日程" : "待办")。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                    Button("打开系统设置", action: openPrivacy)
                        .buttonStyle(CapsuleButtonStyle())
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 一行

private struct AgendaRowView: View {
    var entry: AgendaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dateBadge
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                let detail = AgendaText.detail(for: entry)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(entry.isOverdue ? Theme.warning : Theme.textBody)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                if !entry.calendarTitle.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.calendarColorHex.map { Color(hex: $0) } ?? Theme.todoRing)
                            .frame(width: 5, height: 5)
                        Text(entry.calendarTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            if let date = entry.date {
                Text(AgendaText.month(date))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Text(AgendaText.day(date))
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .frame(height: 23)
                Text(entry.isOverdue ? "已过期" : AgendaText.weekday(date))
                    .font(.system(size: 10))
                    .foregroundStyle(entry.isOverdue ? Theme.warning : Theme.textSecondary)
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPlaceholder)
                    .frame(height: 33)
                Text("无日期")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 40)
    }
}

// MARK: - 角落按钮

private struct CornerIconButton<Icon: View>: View {
    var label: String
    var help: String
    var action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon
                .background(Circle().fill(hovering ? Theme.fillControl : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(help)
    }
}

// MARK: - 文案

private enum AgendaText {
    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    private static var calendar: Calendar { .current }

    /// "11月17日 周一"
    static func dayTitle(_ date: Date) -> String {
        "\(month(date))\(day(date))日 \(weekday(date))"
    }

    static func month(_ date: Date) -> String {
        "\(calendar.component(.month, from: date))月"
    }

    static func day(_ date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }

    static func monthDay(_ date: Date) -> String {
        "\(month(date))\(day(date))日"
    }

    static func weekday(_ date: Date) -> String {
        weekdays[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    static func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func timeRange(_ entry: AgendaEntry) -> String {
        guard let start = entry.date else { return "" }
        if entry.isAllDay {
            if let end = entry.end, !calendar.isDate(start, inSameDayAs: end) {
                return "全天 · 至 \(monthDay(end))"
            }
            return "全天"
        }
        guard let end = entry.end else { return clock(start) }
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(clock(start)) – \(clock(end))"
        }
        return "\(clock(start)) – \(monthDay(end)) \(clock(end))"
    }

    static func detail(for entry: AgendaEntry) -> String {
        var parts: [String] = []
        switch entry.kind {
        case .event:
            let time = timeRange(entry)
            if !time.isEmpty { parts.append(time) }
        case .todo:
            if let date = entry.date {
                if entry.isOverdue {
                    parts.append("已过期")
                } else if entry.hasTime {
                    parts.append("\(clock(date)) 前完成")
                } else {
                    parts.append("当天截止")
                }
            } else {
                parts.append("无截止日期")
            }
        }
        if let location = entry.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }
}
