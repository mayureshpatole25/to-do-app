import Foundation

@main
struct AchievementHeatmapRegression {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let parser = ISO8601DateFormatter()
        let today = parser.date(from: "2026-09-07T02:00:00Z")!
        let entries = ["2026-09-06T23:30:00Z", "2026-09-07T01:00:00Z"].map {
            CompletionRecord(id: UUID(), key: UUID().uuidString, text: "Task", color: "cream", completedAt: parser.date(from: $0)!)
        }
        let map = AchievementHeatmap(records: entries, now: today, calendar: calendar)
        assert(map.weeks.allSatisfy { $0.count == 7 && calendar.component(.weekday, from: $0[0].date) == 2 })
        assert(map.weeks.flatMap { $0 }.first { calendar.isDate($0.date, inSameDayAs: today) }!.count == 2)
        assert(map.months.values.contains("Sep 26"))
        assert(map.months.values.contains("Sep 21"))
        assert(map.weeks.count > 260)
        let oldRecord = CompletionRecord(id: UUID(), key: "old", text: "Old task", color: "cream", completedAt: parser.date(from: "2018-03-02T02:00:00Z")!)
        let extended = AchievementHeatmap(records: entries + [oldRecord], now: today, calendar: calendar)
        assert(extended.months.values.contains("Mar 18"))
        assert(extended.weeks.flatMap { $0 }.contains { $0.count == 1 })
        assert(map.weeks.flatMap { $0 }.filter { $0.isFuture }.allSatisfy { $0.date > calendar.startOfDay(for: today) })
        let days = map.weeks.flatMap { $0 }.map(\.date)
        assert(Set(days).count == days.count)
        assert((0...12).map { AchievementHeatmap.level(for: $0) } == [0,1,1,2,2,2,3,3,3,3,4,4,4])
        let leap = AchievementHeatmap(records: [], now: parser.date(from: "2024-02-29T02:00:00Z")!, calendar: calendar)
        assert(leap.weeks.flatMap { $0 }.contains { calendar.component(.day, from: $0.date) == 29 && calendar.component(.month, from: $0.date) == 2 })
        print("PASS: Monday alignment, local-day aggregation, months, future cells, unique dates, intensity, leap day")
    }
}
