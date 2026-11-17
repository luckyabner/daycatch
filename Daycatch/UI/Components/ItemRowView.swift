import SwiftUI

/// 事项行：日期列 | 类型 + 标题 + 详情 + AI 推断提示 | 勾选按钮
struct ItemRowView: View {
    @Binding var row: ItemRowState
    var metrics: RowMetrics
    var calendarTitle: String
    var defaultAlarmMinutes: Int?
    var isEditing: Bool

    private let formatter = ItemFormatter()

    var body: some View {
        HStack(alignment: .top, spacing: metrics.columnSpacing) {
            dateColumn
            VStack(alignment: .leading, spacing: metrics.titleFontSize >= 17 ? 6 : 5) {
                kindLine
                if isEditing {
                    ItemEditor(item: $row.item, metrics: metrics)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CheckCircleButton(isChecked: row.isChecked, label: row.item.title) {
                row.isChecked.toggle()
            }
            .padding(.top, 1)
        }
        .padding(.vertical, metrics.verticalPadding)
        .padding(.horizontal, metrics.horizontalPadding)
        .overlay(alignment: .bottom) { Divider1px() }
        .opacity(row.isChecked || isEditing ? 1 : 0.55)
        .animation(.easeOut(duration: 0.12), value: row.isChecked)
    }

    private var dateColumn: some View {
        VStack(spacing: 0) {
            if let badge = formatter.badge(for: row.item) {
                Text(badge.month)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text(badge.day)
                    .font(.system(size: metrics.dateFontSize, weight: .medium))
                    .tracking(-0.03 * metrics.dateFontSize)
                    .monospacedDigit()
                    .frame(height: metrics.dateFontSize * 1.1)
                Text(badge.weekday)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("—")
                    .font(.system(size: metrics.dateFontSize * 0.7, weight: .medium))
                    .foregroundStyle(Theme.textPlaceholder)
                    .frame(height: metrics.dateFontSize * 1.1)
                    .padding(.top, 13)
                Text("无日期")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: metrics.dateWidth)
    }

    private var kindLine: some View {
        HStack(spacing: 8) {
            KindDot(kind: row.item.kind)
            Text(row.item.kind == .event ? "日程 · \(calendarTitle)" : "待办 · 提醒事项")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(height: 13)
    }

    @ViewBuilder
    private var content: some View {
        let item = row.item
        Text(item.title)
            .font(.system(size: metrics.titleFontSize, weight: .semibold))
            .tracking(metrics.titleFontSize >= 17 ? -0.17 : 0)
            .fixedSize(horizontal: false, vertical: true)

        let alarm = item.kind == .event ? (item.alarmMinutesBefore ?? defaultAlarmMinutes) : nil
        let lines = formatter.detailLines(for: item, alarmMinutes: alarm)
        if !lines.isEmpty {
            Text(lines.joined(separator: "\n"))
                .foregroundStyle(Theme.textBody)
                .lineSpacing(metrics.lineSpacing)
                .monospacedDigit()
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(formatter.warnings(for: item), id: \.self) { warning in
            Text(warning)
                .font(.system(size: 12))
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 行内编辑（⌘E）

struct ItemEditor: View {
    @Binding var item: ExtractedItem
    var metrics: RowMetrics

    private var calendar: Calendar { ItemFormatter().calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                kindChip(.event, "日程")
                kindChip(.todo, "待办")
            }
            EditorField(placeholder: "标题", text: $item.title, fontSize: metrics.titleFontSize, weight: .semibold)

            switch item.kind {
            case .event: eventFields
            case .todo: todoFields
            }
        }
    }

    @ViewBuilder
    private var eventFields: some View {
        let components: DatePickerComponents = item.isAllDay ? [.date] : [.date, .hourAndMinute]
        HStack(spacing: 8) {
            EditorLabel("开始")
            DatePicker("", selection: startBinding, displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.field)
            Toggle("全天", isOn: allDayBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
        }
        HStack(spacing: 8) {
            EditorLabel("结束")
            DatePicker("", selection: endBinding, in: (item.start?.date ?? .distantPast)..., displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.field)
        }
        EditorField(placeholder: "地点", text: optionalText(\.location), fontSize: 13)
        EditorField(placeholder: "备注", text: optionalText(\.notes), fontSize: 13)
    }

    @ViewBuilder
    private var todoFields: some View {
        HStack(spacing: 8) {
            Toggle("截止", isOn: hasDueBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            if let due = item.due {
                DatePicker("", selection: dueBinding, displayedComponents: due.hasTime ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
                    .datePickerStyle(.field)
                Toggle("具体时间", isOn: dueHasTimeBinding)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
        }
        EditorField(placeholder: "备注", text: optionalText(\.notes), fontSize: 13)
    }

    private func kindChip(_ kind: ItemKind, _ title: String) -> some View {
        Button {
            item.setKind(kind, now: Date())
        } label: {
            Text(title)
                .font(.system(size: 11, weight: item.kind == kind ? .semibold : .regular))
                .foregroundStyle(item.kind == kind ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(Capsule().fill(item.kind == kind ? Theme.fillControlPressed : Theme.fillControl))
        }
        .buttonStyle(.plain)
    }

    // MARK: 绑定

    private var startBinding: Binding<Date> {
        Binding { item.start?.date ?? Date() } set: { item.setStart($0) }
    }

    private var endBinding: Binding<Date> {
        Binding { item.end?.date ?? item.start?.date ?? Date() } set: { item.setEnd($0) }
    }

    private var allDayBinding: Binding<Bool> {
        Binding { item.isAllDay } set: { item.setAllDay($0, calendar: calendar) }
    }

    private var hasDueBinding: Binding<Bool> {
        Binding { item.due != nil } set: { enabled in
            if enabled {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
                item.setDue(tomorrow, hasTime: false)
            } else {
                item.setDue(nil, hasTime: false)
            }
        }
    }

    private var dueBinding: Binding<Date> {
        Binding { item.due?.date ?? Date() } set: { item.setDue($0, hasTime: item.due?.hasTime ?? false) }
    }

    private var dueHasTimeBinding: Binding<Bool> {
        Binding { item.due?.hasTime ?? false } set: { hasTime in
            guard let due = item.due else { return }
            let day = calendar.startOfDay(for: due.date)
            let date = hasTime ? (calendar.date(byAdding: .hour, value: 18, to: day) ?? day) : day
            item.setDue(date, hasTime: hasTime)
        }
    }

    private func optionalText(_ keyPath: WritableKeyPath<ExtractedItem, String?>) -> Binding<String> {
        Binding {
            item[keyPath: keyPath] ?? ""
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            item[keyPath: keyPath] = trimmed.isEmpty ? nil : value
            if keyPath == \ExtractedItem.location { item.inferred.remove(InferredField.location) }
        }
    }
}

private struct EditorLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 26, alignment: .leading)
    }
}

private struct EditorField: View {
    var placeholder: String
    @Binding var text: String
    var fontSize: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: weight))
            .padding(.horizontal, 8)
            .frame(height: fontSize + 14)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.fillControl))
    }
}
