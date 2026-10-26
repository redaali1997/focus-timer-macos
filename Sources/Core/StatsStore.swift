import Foundation
import AppKit
import UniformTypeIdentifiers

/// History of time blocks, stored as JSON in Application Support.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var blocks: [TimeBlock] = []

    static let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let file = StatsStore.directory.appendingPathComponent("history.json")

    private init() {
        if let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            blocks = (try? decoder.decode([TimeBlock].self, from: data)) ?? []
        }
    }

    func add(_ block: TimeBlock) {
        blocks.append(block)
        save()
    }

    func delete(_ block: TimeBlock) {
        blocks.removeAll { $0.id == block.id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(blocks) {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: - Queries

    func blocks(in interval: DateInterval) -> [TimeBlock] {
        blocks.filter { interval.contains($0.start) }
    }

    func focusTime(in interval: DateInterval) -> TimeInterval {
        blocks(in: interval).filter { $0.phase == .pomodoro }.reduce(0) { $0 + $1.elapsed }
    }

    func pomodoros(in interval: DateInterval) -> Int {
        blocks(in: interval).filter { $0.phase == .pomodoro && $0.completed }.count
    }

    var pomodorosToday: Int {
        pomodoros(in: Calendar.current.dateInterval(of: .day, for: Date())!)
    }

    /// Consecutive days (ending today or yesterday) with at least one completed pomodoro.
    var streak: Int {
        let cal = Calendar.current
        let days = Set(blocks.filter { $0.phase == .pomodoro && $0.completed }.map { cal.startOfDay(for: $0.start) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    // MARK: - Export

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "focus-timer-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iso = ISO8601DateFormatter()
        var csv = "type,start,end,planned_seconds,elapsed_seconds,completed,task,profile\n"
        for b in blocks.sorted(by: { $0.start < $1.start }) {
            let task = (b.task ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(b.phase.rawValue),\(iso.string(from: b.start)),\(iso.string(from: b.end)),\(Int(b.planned)),\(Int(b.elapsed)),\(b.completed),\"\(task)\",\"\(b.profile ?? "")\"\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
