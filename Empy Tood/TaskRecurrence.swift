import Foundation

/// Calendar-based local-time schedule. The anchor preserves month-day intent
/// (e.g. January 31 -> February 28 -> March 31) and weekly interval alignment.
struct TaskRecurrence: Codable, Equatable {
    enum Unit: String, Codable, CaseIterable { case day, week, month, year }
    var unit: Unit = .day
    var interval: Int = 1
    var weekdays: [Int] = [] // Calendar weekday: Sunday = 1
    var monthDays: [Int] = []
    var anchor: Date = Date()
    var endDate: Date?
    var occurrenceLimit: Int?

    var label: String {
        let cadence = interval == 1 ? unit.rawValue : "\(interval) \(unit.rawValue)s"
        if unit == .week, !weekdays.isEmpty {
            let names = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
            let days = [2, 3, 4, 5, 6, 7, 1].filter { weekdays.contains($0) }.compactMap { names[$0] }
            let joined = days.count <= 2 ? days.joined(separator: " and ") : days.dropLast().joined(separator: ", ") + " and " + days.last!
            return "@repeats every " + (interval == 1 ? "" : cadence + " on ") + joined
        }
        if unit == .month, !monthDays.isEmpty {
            return "@repeats every " + cadence + " on " + monthDays.sorted().map(String.init).joined(separator: ", ")
        }
        if unit == .day, interval == 1 { return "@repeats everyday" }
        return "@repeats every " + cadence
    }

    static func presets(for date: Date, calendar: Calendar = .current) -> [(String, TaskRecurrence)] {
        let weekday = calendar.component(.weekday, from: date)
        return [
            ("Every day", TaskRecurrence(anchor: date)),
            ("Every weekday", TaskRecurrence(unit: .week, weekdays: [2,3,4,5,6], anchor: date)),
            ("Every week", TaskRecurrence(unit: .week, weekdays: [weekday], anchor: date)),
            ("Every 2 weeks", TaskRecurrence(unit: .week, interval: 2, weekdays: [weekday], anchor: date)),
            ("Every month", TaskRecurrence(unit: .month, anchor: date)),
            ("Every year", TaskRecurrence(unit: .year, anchor: date))
        ]
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: anchor)
        let anchorDay = calendar.startOfDay(for: anchor)
        var day = calendar.startOfDay(for: date)
        // Covers leap-year gaps and the largest UI interval (99 years).
        for _ in 0..<37000 {
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = following
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            let anchorComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: anchor)
            let step = max(1, interval)
            let matches: Bool
            switch unit {
            case .day:
                matches = (calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0) % step == 0
            case .week:
                let start = calendar.dateInterval(of: .weekOfYear, for: anchorDay)!.start
                let current = calendar.dateInterval(of: .weekOfYear, for: day)!.start
                let weeks = (calendar.dateComponents([.day], from: start, to: current).day ?? 0) / 7
                matches = weeks % step == 0 && (weekdays.isEmpty ? [anchorComponents.weekday!] : weekdays).contains(components.weekday!)
            case .month:
                let months = (components.year! - anchorComponents.year!) * 12 + components.month! - anchorComponents.month!
                let lastDay = calendar.range(of: .day, in: .month, for: day)!.count
                let dates = monthDays.isEmpty ? [anchorComponents.day!] : monthDays
                matches = months % step == 0 && dates.map { min($0, lastDay) }.contains(components.day!)
            case .year:
                let lastDay = calendar.range(of: .day, in: .month, for: day)!.count
                matches = (components.year! - anchorComponents.year!) % step == 0 && components.month == anchorComponents.month && components.day == min(anchorComponents.day!, lastDay)
            }
            if let endDate, day > calendar.startOfDay(for: endDate) { return nil }
            if matches {
                return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
            }
        }
        return nil
    }
}

/// A closed occurrence is immutable; the current occurrence uses isDone and
/// completedAt, so unchecking and undo never inflate completion counts.
struct TaskOccurrence: Codable, Equatable {
    var scheduledAt: Date
    var completedAt: Date?
    var wasCompleted: Bool
}

extension TodoItem {
    @discardableResult
    mutating func advanceRecurrence(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let recurrence, var current = dueDate else { return false }
        var changed = false
        while let next = recurrence.next(after: current, calendar: calendar), next <= now {
            if let limit = recurrence.occurrenceLimit, (occurrenceHistory?.filter { $0.scheduledAt >= recurrence.anchor }.count ?? 0) + 1 >= limit { break }
            var history = occurrenceHistory ?? []
            history.append(TaskOccurrence(scheduledAt: current, completedAt: completedAt, wasCompleted: isDone))
            occurrenceHistory = history
            current = next
            dueDate = next
            isDone = false
            completedAt = nil
            changed = true
        }
        return changed
    }
}
