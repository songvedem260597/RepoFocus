import RepoFocusCore
import SwiftUI

enum FocusButtonRole {
    case primary
    case secondary
    case destructive
    case icon
}

struct FocusButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let role: FocusButtonRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, role == .icon ? 8 : 11)
            .frame(minHeight: 32)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch role {
        case .primary: .white
        case .secondary, .icon: .primary
        case .destructive: .red
        }
    }

    private var borderColor: Color {
        switch role {
        case .primary: .clear
        case .secondary, .icon: .quietBorder
        case .destructive: .red.opacity(0.25)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .primary:
            return Color.accentColor.opacity(isPressed ? 0.78 : 1)
        case .secondary, .icon:
            return Color.primary.opacity(isPressed ? 0.09 : 0.045)
        case .destructive:
            return Color.red.opacity(isPressed ? 0.14 : 0.075)
        }
    }
}

struct FocusTextInput: View {
    @EnvironmentObject private var preferences: AppPreferences
    let placeholder: String
    @Binding var text: String
    var leadingSymbol: String?
    var isSecure = false
    var showsClearButton = false

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Layout.compact) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isFocused)

            if showsClearButton && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(preferences.language.text("Xóa nội dung", "Clear"))
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(isFocused ? Color.elevatedBackground : Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(isFocused ? Color.accentColor : Color.quietBorder, lineWidth: isFocused ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

struct FocusTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 104

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .focused($isFocused)
        }
        .frame(minHeight: minHeight)
        .background(isFocused ? Color.elevatedBackground : Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(isFocused ? Color.accentColor : Color.quietBorder, lineWidth: isFocused ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

struct FocusStatusSelect: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var selection: WorkStatus
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: Layout.compact) {
                Image(systemName: selection.symbolName)
                    .foregroundStyle(selection.color)
                Text(selection.localizedTitle(preferences.language))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(width: 172, height: 32)
            .background(isOpen ? Color.elevatedBackground : Color.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .stroke(isOpen ? Color.accentColor : Color.quietBorder, lineWidth: isOpen ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 3) {
                ForEach(WorkStatus.allCases) { status in
                    FocusOptionRow(
                        title: status.localizedTitle(preferences.language),
                        symbol: status.symbolName,
                        color: status.color,
                        isSelected: status == selection
                    ) {
                        selection = status
                        isOpen = false
                    }
                }
            }
            .padding(6)
            .frame(width: 188)
        }
    }
}

private struct FocusOptionRow: View {
    let title: String
    let symbol: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.compact) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(isSelected || isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct FocusPriorityControl: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var selection: WorkPriority

    var body: some View {
        HStack(spacing: 3) {
            ForEach(WorkPriority.allCases) { priority in
                Button {
                    selection = priority
                } label: {
                    Text(priority.localizedTitle(preferences.language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == priority ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(selection == priority ? priority.color.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(width: 174, height: 32)
        .background(Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }
}

struct FocusProgressSlider: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var value: Int
    var tint: Color

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let usableWidth = max(proxy.size.width - 14, 1)
            let fraction = CGFloat(value) / 100
            let thumbX = 7 + usableWidth * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.strongBorder.opacity(0.7))
                    .frame(height: 5)
                    .padding(.horizontal, 7)

                Capsule()
                    .fill(tint)
                    .frame(width: max(usableWidth * fraction, 5), height: 5)
                    .padding(.leading, 7)

                Circle()
                    .fill(Color.elevatedBackground)
                    .frame(width: isDragging ? 16 : 14, height: isDragging ? 16 : 14)
                    .overlay {
                        Circle().stroke(tint.opacity(0.65), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .position(x: thumbX, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = min(max((gesture.location.x - 7) / usableWidth, 0), 1)
                        value = Int((fraction * 100 / 5).rounded() * 5)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(preferences.language.text("Tiến độ", "Progress"))
        .accessibilityValue(preferences.language.text("\(value) phần trăm", "\(value) percent"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 5, 100)
            case .decrement: value = max(value - 5, 0)
            @unknown default: break
            }
        }
    }
}

struct FocusCheckbox: View {
    @EnvironmentObject private var preferences: AppPreferences
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Layout.compact) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color.subtleFill)
                    .frame(width: 18, height: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isOn ? Color.accentColor : Color.quietBorder, lineWidth: 1)
                    }
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn
            ? preferences.language.text("Bật", "On")
            : preferences.language.text("Tắt", "Off"))
    }
}

struct FocusDateInput: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var date: Date
    @State private var showsCalendar = false

    var body: some View {
        VStack(alignment: .trailing, spacing: Layout.compact) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsCalendar.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(dayText)
                        .frame(width: 18)
                    separator
                    Text(monthText)
                        .frame(width: 18)
                    separator
                    Text(yearText)
                        .frame(width: 36)

                    Rectangle()
                        .fill(Color.quietBorder)
                        .frame(width: 1, height: 17)
                        .padding(.horizontal, 3)

                    Image(systemName: showsCalendar ? "calendar.badge.minus" : "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(showsCalendar ? Color.accentColor : Color.secondary)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(showsCalendar ? Color.elevatedBackground : Color.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                        .stroke(showsCalendar ? Color.accentColor : Color.quietBorder, lineWidth: showsCalendar ? 1.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(showsCalendar
                ? preferences.language.text("Đóng lịch", "Close calendar")
                : preferences.language.text("Mở lịch", "Open calendar"))

            if showsCalendar {
                FocusCalendar(date: $date) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsCalendar = false
                    }
                }
                .padding(10)
                .background(Color.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                        .stroke(Color.quietBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var separator: some View {
        Text("/")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    private var components: DateComponents {
        Calendar.current.dateComponents([.day, .month, .year], from: date)
    }

    private var dayText: String {
        String(format: "%02d", components.day ?? 1)
    }

    private var monthText: String {
        String(format: "%02d", components.month ?? 1)
    }

    private var yearText: String {
        String(components.year ?? Calendar.current.component(.year, from: .now))
    }
}

private struct FocusCalendar: View {
    @Environment(\.locale) private var locale
    @Binding var date: Date
    let onSelection: () -> Void

    @State private var displayedMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    private var calendar: Calendar {
        var value = Calendar.current
        value.locale = locale
        return value
    }

    init(date: Binding<Date>, onSelection: @escaping () -> Void) {
        _date = date
        self.onSelection = onSelection
        _displayedMonth = State(initialValue: Calendar.current.dateInterval(of: .month, for: date.wrappedValue)?.start ?? date.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 22)
                }

                ForEach(0..<leadingBlankCount, id: \.self) { _ in
                    Color.clear.frame(width: 28, height: 28)
                }

                ForEach(daysInDisplayedMonth, id: \.self) { dayNumber in
                    dayButton(dayNumber)
                }
            }
        }
        .frame(width: 224)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[start...] + symbols[..<start])
    }

    private var leadingBlankCount: Int {
        let weekday = calendar.component(.weekday, from: displayedMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var daysInDisplayedMonth: Range<Int> {
        calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<1
    }

    private func dayButton(_ dayNumber: Int) -> some View {
        let dayDate = calendar.date(byAdding: .day, value: dayNumber - 1, to: displayedMonth) ?? displayedMonth
        let selected = calendar.isDate(dayDate, inSameDayAs: date)
        let today = calendar.isDateInToday(dayDate)

        return Button {
            date = dayDate
            onSelection()
        } label: {
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(selected ? Color.accentColor : (today ? Color.accentColor.opacity(0.1) : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if today && !selected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func moveMonth(_ amount: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: amount, to: displayedMonth) ?? displayedMonth
    }
}
