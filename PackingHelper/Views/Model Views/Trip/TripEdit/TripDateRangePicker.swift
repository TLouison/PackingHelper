//
//  TripDateRangePicker.swift
//  PackingHelper
//
//  Inline month calendar for picking a trip's dates in one place. Tap the departure
//  day, then the return day. Once both are set, the next tap starts a new range
//  (like booking a hotel), so moving a whole trip is always two taps.
//  A tap before the departure while picking the return moves the departure instead.
//

import SwiftUI

struct TripDateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    /// Days before this can't be picked (new trips can't be in the past); nil allows any day
    var earliestDay: Date?

    /// The next tap sets the return day (departure was just picked)
    @State private var isPickingReturn = false
    /// First day of the month on screen
    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    init(startDate: Binding<Date>, endDate: Binding<Date>, earliestDay: Date? = nil) {
        _startDate = startDate
        _endDate = endDate
        self.earliestDay = earliestDay
        _displayedMonth = State(initialValue: Calendar.current.startOfMonth(for: startDate.wrappedValue))
    }

    private var nights: Int {
        calendar.numberOfDaysBetween(startDate, and: endDate)
    }

    var body: some View {
        VStack(spacing: 12) {
            summary
            monthHeader
            grid
            Text(nights == 0 ? "Day trip" : nights == 1 ? "1 night" : "\(nights) nights")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: nights)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 15))
    }

    // MARK: - Summary

    /// Both dates, with the one the next tap sets outlined
    private var summary: some View {
        HStack {
            summaryValue("Depart", date: startDate, isNext: !isPickingReturn, alignment: .leading)
            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer()
            summaryValue("Return", date: endDate, isNext: isPickingReturn, alignment: .trailing)
        }
    }

    private func summaryValue(_ title: String, date: Date, isNext: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.headline)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isNext ? 1 : 0)
        }
        .animation(.snappy, value: isNext)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isNext ? "Tap a day to set this date" : "")
    }

    // MARK: - Month

    private var monthHeader: some View {
        HStack {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button("Previous Month", systemImage: "chevron.left") { changeMonth(by: -1) }
                .disabled(!canGoBack)
            Button("Next Month", systemImage: "chevron.right") { changeMonth(by: 1) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .fontWeight(.semibold)
    }

    /// Stops at the month of the earliest pickable day
    private var canGoBack: Bool {
        guard let earliestDay else { return true }
        return displayedMonth > calendar.startOfMonth(for: earliestDay)
    }

    private func changeMonth(by months: Int) {
        guard let month = calendar.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        if months < 0 && !canGoBack { return }
        withAnimation(.snappy) {
            displayedMonth = month
        }
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    // Blank padding keeps every month six rows, so the form doesn't jump
                    Color.clear.frame(height: 36)
                }
            }
        }
        .contentShape(.rect)
        // Simultaneous so vertical drags still scroll the form
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    changeMonth(by: value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    /// Very short weekday names starting from the locale's first weekday
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The displayed month's days, with nil padding before the first and after the last (42 cells)
    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: displayedMonth))
        }
        cells.append(contentsOf: Array(repeating: nil, count: max(0, 42 - cells.count)))
        return cells
    }

    private func dayCell(_ day: Date) -> some View {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let isStart = calendar.isDate(day, inSameDayAs: startDay)
        let isEnd = calendar.isDate(day, inSameDayAs: endDay)
        let isInRange = day > startDay && day < endDay
        let isDisabled = earliestDay.map { day < calendar.startOfDay(for: $0) } ?? false
        let isEndpoint = isStart || isEnd

        return Button {
            select(day)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(isEndpoint ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isEndpoint ? Color.white : isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    rangeBackground(isStart: isStart, isEnd: isEnd, isInRange: isInRange)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isStart ? "Departure" : isEnd ? "Return" : isInRange ? "In trip" : "")
        .accessibilityAddTraits(isEndpoint ? .isSelected : [])
    }

    /// Filled caps on the departure and return days, joined by a tinted band between them.
    /// The band runs edge to edge in each cell so it reads as one strip across a week.
    @ViewBuilder
    private func rangeBackground(isStart: Bool, isEnd: Bool, isInRange: Bool) -> some View {
        let radius: CGFloat = 18
        if isStart && isEnd {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 36, height: 36)
        } else if isStart {
            UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
                .fill(Color.accentColor)
        } else if isEnd {
            UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius)
                .fill(Color.accentColor)
        } else if isInRange {
            Rectangle()
                .fill(Color.accentColor.opacity(0.25))
        }
    }

    // MARK: - Selection

    private func select(_ day: Date) {
        withAnimation(.snappy) {
            if isPickingReturn && day >= calendar.startOfDay(for: startDate) {
                endDate = day.keepingTime(of: endDate)
                isPickingReturn = false
            } else {
                // Start over: this is the new departure; return follows until the next tap
                startDate = day.keepingTime(of: startDate)
                endDate = day.keepingTime(of: endDate)
                isPickingReturn = true
            }
            // Same-day trips keep their times in order
            if endDate < startDate {
                endDate = startDate
            }
        }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

private extension Date {
    /// This day at `other`'s time of day. The form only edits days, so saved times are kept.
    func keepingTime(of other: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: other)
        return calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: self
        ) ?? self
    }
}

#Preview {
    @Previewable @State var start = Date.now
    @Previewable @State var end = Date.now.addingTimeInterval(4 * 86_400)
    TripDateRangePicker(startDate: $start, endDate: $end, earliestDay: .now)
        .padding()
        .background(Color(.systemGroupedBackground))
}
