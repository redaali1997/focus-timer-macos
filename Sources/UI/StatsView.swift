import SwiftUI
import Charts

enum StatsRange: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        }
    }
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

struct StatsView: View {
    @ObservedObject private var stats = StatsStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var range: StatsRange = .day
    @State private var anchor = Date()

    private let cal = Calendar.current
    private var interval: DateInterval { cal.dateInterval(of: range.component, for: anchor)! }
    private var blocks: [TimeBlock] { stats.blocks(in: interval) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summary
                chart
                    .frame(height: 200)
                if range == .month { heatmap }
                tasks
                if range == .day { timeline }
            }
            .padding(24)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(interval.end > Date())
            }
            .buttonStyle(.borderless)
        }
    }

    private var title: String {
        let f = DateFormatter()
        switch range {
        case .day:
            if cal.isDateInToday(anchor) { return String(localized: "Today") }
            if cal.isDateInYesterday(anchor) { return String(localized: "Yesterday") }
            f.setLocalizedDateFormatFromTemplate("EEEEdMMMyyyy")
            return f.string(from: anchor)
        case .week:
            f.setLocalizedDateFormatFromTemplate("dMMM")
            return "\(f.string(from: interval.start)) – \(f.string(from: interval.end.addingTimeInterval(-1)))"
        case .month:
            f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return f.string(from: anchor)
        }
    }

    private func move(_ step: Int) {
        anchor = cal.date(byAdding: range.component, value: step, to: anchor)!
    }

    // MARK: Summary

    private var summary: some View {
        let focus = blocks.filter { $0.phase == .pomodoro }
        let breaks = blocks.filter { $0.phase.isBreak }
        let interrupted = focus.filter { !$0.completed }.count
        return HStack(spacing: 12) {
            StatCard(title: "Focus time", value: formatDuration(focus.reduce(0) { $0 + $1.elapsed }), color: Phase.pomodoro.color)
            StatCard(title: "Pomodoros", value: "\(focus.filter(\.completed).count)", color: Phase.pomodoro.color)
            StatCard(title: "Break time", value: formatDuration(breaks.reduce(0) { $0 + $1.elapsed }), color: Phase.shortBreak.color)
            StatCard(title: "Interrupted", value: "\(interrupted)", color: .secondary)
        }
    }

    // MARK: Chart

    private struct Bucket: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    private var buckets: [Bucket] {
        let unit: Calendar.Component = range == .day ? .hour : .day
        var result: [Bucket] = []
        var cursor = interval.start
        while cursor < interval.end {
            let next = cal.date(byAdding: unit, value: 1, to: cursor)!
            let minutes = blocks
                .filter { $0.phase == .pomodoro && $0.start >= cursor && $0.start < next }
                .reduce(0) { $0 + $1.elapsed } / 60
            result.append(Bucket(date: cursor, minutes: minutes))
            cursor = next
        }
        return result
    }

    private var chart: some View {
        let goalMinutes = Double(settings.dailyGoal * settings.pomodoroDuration) / 60
        return Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Time", bucket.date, unit: range == .day ? .hour : .day),
                        y: .value("Minutes", bucket.minutes))
                    .foregroundStyle(Phase.pomodoro.color.gradient)
                    .cornerRadius(3)
            }
            if range != .day {
                RuleMark(y: .value("Goal", goalMinutes))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Daily goal").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYAxisLabel("minutes")
        .chartXAxis {
            switch range {
            case .day: AxisMarks(values: .stride(by: .hour, count: 3)) { AxisValueLabel(format: .dateTime.hour()) ; AxisGridLine() }
            case .week: AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
            case .month: AxisMarks(values: .stride(by: .day, count: 5)) { AxisValueLabel(format: .dateTime.day()) }
            }
        }
    }

    // MARK: Month heatmap

    private var heatmap: some View {
        let days = buckets
        let maxMinutes = max(1, days.map(\.minutes).max() ?? 1)
        let leading = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        return VStack(alignment: .leading, spacing: 8) {
            Text("Activity").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 28) }
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(day.minutes == 0 ? Color.secondary.opacity(0.12)
                              : Phase.pomodoro.color.opacity(0.25 + 0.75 * day.minutes / maxMinutes))
                        .frame(height: 28)
                        .overlay(Text("\(cal.component(.day, from: day.date))").font(.caption2))
                        .help("\(formatDuration(day.minutes * 60)) focus")
                        .onTapGesture { anchor = day.date; range = .day }
                }
            }
        }
    }

    // MARK: Tasks

    private var tasks: some View {
        let grouped = Dictionary(grouping: blocks.filter { $0.phase == .pomodoro }) { $0.task ?? String(localized: "Untitled") }
            .map { (name: $0.key, time: $0.value.reduce(0) { $0 + $1.elapsed }) }
            .sorted { $0.time > $1.time }
        return Group {
            if !grouped.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tasks").font(.headline)
                    ForEach(grouped, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(formatDuration(item.time)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: Day timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sessions").font(.headline)
                Spacer()
                Button("Export CSV…") { stats.exportCSV() }
                    .buttonStyle(.borderless)
            }
            if blocks.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            }
            ForEach(blocks.sorted { $0.start > $1.start }) { block in
                HStack {
                    Circle().fill(block.phase.color).frame(width: 8, height: 8)
                    Text(block.start, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(block.task ?? block.phase.title)
                    if !block.completed {
                        Text("interrupted").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(formatDuration(block.elapsed)).monospacedDigit()
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { stats.delete(block) }
                }
            }
        }
    }
}

struct StatCard: View {
    var title: LocalizedStringKey
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(color).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }
}
