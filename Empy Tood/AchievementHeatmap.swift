import Foundation

struct AchievementHeatmap {
    struct Day: Identifiable {
        let date: Date
        let count: Int
        let isFuture: Bool
        var id: Date { date }
    }
    let weeks: [[Day]]
    let months: [Int: String]

    init(records: [CompletionRecord], now: Date, calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let month = calendar.dateInterval(of: .month, for: today)!.start
        // Keep several years available, including every recorded completion.
        let baseline = calendar.date(byAdding: .year, value: -5, to: month)!
        let earliest = records.map(\.completedAt).min() ?? baseline
        let startMonth = calendar.dateInterval(of: .month, for: min(baseline, earliest))!.start
        let offset = (calendar.component(.weekday, from: startMonth) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: startMonth)!
        let end = calendar.dateInterval(of: .month, for: today)!.end
        let counts = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.completedAt) }).mapValues(\.count)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM yy"
        var weeks: [[Day]] = []
        var months: [Int: String] = [:]
        var cursor = start
        while cursor < end {
            var week: [Day] = []
            for _ in 0..<7 {
                if cursor >= startMonth, cursor < end, calendar.component(.day, from: cursor) == 1 {
                    months[weeks.count] = formatter.string(from: cursor)
                }
                week.append(Day(date: cursor, count: counts[cursor, default: 0], isFuture: cursor > today))
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }
            weeks.append(week)
        }
        self.weeks = weeks
        self.months = months
    }

    static func level(for count: Int) -> Int {
        switch count { case ...0: return 0; case 1...2: return 1; case 3...5: return 2; case 6...9: return 3; default: return 4 }
    }
}
