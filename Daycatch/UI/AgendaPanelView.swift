import SwiftUI

struct AgendaPanelActions {
    var recognize: () -> Void = {}
    var openSettings: () -> Void = {}
    var openPrivacy: (Permissions.Pane) -> Void = { _ in }
    /// 「输入识别」按钮的提示文字（带上快捷键）
    var recognizeHint = Localization.strings.recognizeTextButton
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

    private var t: Strings { Localization.strings }

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
                Text(t.upcoming)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.44)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                CornerIconButton(label: t.recognizeTextButton, help: actions.recognizeHint, action: actions.recognize) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                }
                CornerIconButton(label: t.settingsAccessibilityLabel, help: t.settings, action: actions.openSettings) {
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
        guard model.hasLoaded else { return "\(day) · \(t.loadingAgendaSubtitle)" }
        if model.needsUnifiedPermission { return "\(day) · \(t.permissionAgendaSubtitle)" }
        var parts = [day]
        if model.eventCount > 0 { parts.append(t.eventCount(model.eventCount)) }
        if model.todoCount > 0 { parts.append(t.todoCount(model.todoCount)) }
        if parts.count == 1 { parts.append(t.nothingScheduled) }
        return parts.joined(separator: " · ")
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            placeholder {
                ProgressView().controlSize(.small)
                Text(t.readingCalendar)
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
                    title: t.eventsColumnTitle,
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
                    title: t.todosColumnTitle,
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
            Text(t.permissionTitle)
                .font(.system(size: 14, weight: .semibold))
            Text(t.permissionMessage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            HStack(spacing: 8) {
                Button(t.calendarAccessButton) { actions.openPrivacy(.calendars) }
                Button(t.remindersAccessButton) { actions.openPrivacy(.reminders) }
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
            Text(t.noAgendaTitle)
                .font(.system(size: 14, weight: .semibold))
            Text(t.noAgendaMessage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button(t.recognizeTextButton, action: actions.recognize)
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
                Text(kind == .event ? Localization.strings.noEventsInYear : Localization.strings.noOpenTodos)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .denied:
                VStack(spacing: 10) {
                    Text(Localization.strings.deniedColumnTitle(kind))
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text(Localization.strings.deniedColumnMessage(kind))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                    Button(Localization.strings.openSystemSettings, action: openPrivacy)
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
    @Environment(\.dcAccent) private var accent

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
                let countdown = AgendaText.countdown(for: entry)
                if !entry.calendarTitle.isEmpty || countdown != nil {
                    HStack(spacing: 4) {
                        if !entry.calendarTitle.isEmpty {
                            Circle()
                                .fill(entry.calendarColorHex.map { Color(hex: $0) } ?? Theme.todoRing)
                                .frame(width: 5, height: 5)
                            Text(entry.calendarTitle)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if let countdown {
                            Text(countdown.text)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(countdownColor(countdown.tone))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countdownColor(_ tone: AgendaCountdown.Tone) -> Color {
        switch tone {
        case .today: accent
        case .soon: Theme.textPrimary
        case .later: Theme.textBody
        case .overdue: Theme.warning
        }
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
                Text(entry.isOverdue ? Localization.strings.overdue : AgendaText.weekday(date))
                    .font(.system(size: 10))
                    .foregroundStyle(entry.isOverdue ? Theme.warning : Theme.textSecondary)
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPlaceholder)
                    .frame(height: 33)
                Text(Localization.strings.noDate)
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

private struct AgendaCountdown: Equatable {
    enum Tone {
        case today
        case soon
        case later
        case overdue
    }

    var text: String
    var tone: Tone
}

private enum AgendaText {
    private static var t: Strings { Localization.strings }
    private static var dateText: DateText { DateText() }

    /// "11月17日 周一" / "Mon, Nov 17"
    static func dayTitle(_ date: Date) -> String { dateText.dayTitle(date) }
    static func month(_ date: Date) -> String { dateText.month(date) }
    static func day(_ date: Date) -> String { dateText.day(date) }
    static func monthDay(_ date: Date) -> String { dateText.monthDay(date) }
    static func weekday(_ date: Date) -> String { dateText.weekday(date) }
    static func clock(_ date: Date) -> String { dateText.clock(date) }

    static func detail(for entry: AgendaEntry) -> String {
        var parts: [String] = []
        switch entry.kind {
        case .event:
            if let start = entry.date {
                let time = dateText.eventTime(start: start, end: entry.end, isAllDay: entry.isAllDay)
                if !time.isEmpty { parts.append(time) }
            }
        case .todo:
            if let date = entry.date {
                if entry.isOverdue {
                    parts.append(t.overdue)
                } else if entry.hasTime {
                    parts.append(t.dueAt(clock(date)))
                } else {
                    parts.append(t.dueThatDay)
                }
            } else {
                parts.append(t.noDueDate)
            }
        }
        if let location = entry.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    /// 距离现在还有多少天：「今天」「明天」「后天」「还有 N 天」；待办过期时显示「已过期 N 天」
    static func countdown(for entry: AgendaEntry, now: Date = Date()) -> AgendaCountdown? {
        guard let date = entry.date else { return nil }
        let days = dateText.daysBetween(now, date)
        if days < 0 {
            // 跨天的进行中日程也归到「今天」
            guard entry.kind == .todo else {
                return AgendaCountdown(text: t.today, tone: .today)
            }
            return AgendaCountdown(text: t.overdueDays(-days), tone: .overdue)
        }
        if entry.isOverdue {
            return AgendaCountdown(text: t.overdue, tone: .overdue)
        }
        switch days {
        case 0: return AgendaCountdown(text: t.today, tone: .today)
        case 1: return AgendaCountdown(text: t.tomorrow, tone: .soon)
        case 2: return AgendaCountdown(text: t.dayAfterTomorrow, tone: .soon)
        default: return AgendaCountdown(text: t.countdownDays(days), tone: .later)
        }
    }
}
