import Foundation

@main
struct TaskRecurrenceRegression {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let start = date(2026, 9, 7)
        var task = TodoItem(text: "Read", isDone: true, completedAt: start, dueDate: start)
        task.recurrence = TaskRecurrence(anchor: start)
        assert(!task.advanceRecurrence(now: date(2026, 9, 8, 8), calendar: calendar))
        assert(task.advanceRecurrence(now: date(2026, 9, 10), calendar: calendar))
        assert(task.dueDate == date(2026, 9, 10) && !task.isDone)
        assert(task.occurrenceHistory?.map(\.wasCompleted) == [true, false, false])
        assert(!task.advanceRecurrence(now: date(2026, 9, 10), calendar: calendar))
        let decoded = try JSONDecoder().decode(TodoItem.self, from: JSONEncoder().encode(task))
        assert(decoded == task)
        let old = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"Old\",\"isDone\":false}"
        let legacy = try JSONDecoder().decode(TodoItem.self, from: Data(old.utf8))
        assert(legacy.recurrence == nil)
        let weekly = TaskRecurrence(unit: .week, weekdays: [2,4], anchor: start)
        assert(weekly.next(after: start, calendar: calendar) == date(2026, 9, 9))
        assert(weekly.next(after: date(2026, 9, 9), calendar: calendar) == date(2026, 9, 14))
        let fortnight = TaskRecurrence(unit: .week, interval: 2, weekdays: [2,4], anchor: start)
        assert(fortnight.next(after: date(2026, 9, 9), calendar: calendar) == date(2026, 9, 21))
        let monthly = TaskRecurrence(unit: .month, anchor: date(2026, 1, 31))
        let feb = monthly.next(after: date(2026, 1, 31), calendar: calendar)!
        assert(feb == date(2026, 2, 28))
        assert(monthly.next(after: feb, calendar: calendar) == date(2026, 3, 31))
        let dates = TaskRecurrence(unit: .month, monthDays: [1,15], anchor: start)
        assert(dates.next(after: start, calendar: calendar) == date(2026, 9, 15))
        let dst = TaskRecurrence(anchor: date(2026, 10, 3))
        assert(dst.next(after: date(2026, 10, 3), calendar: calendar) == date(2026, 10, 4))
        let end = TaskRecurrence(anchor: start, endDate: date(2026, 9, 8, 0))
        assert(end.next(after: start, calendar: calendar) == date(2026, 9, 8))
        assert(end.next(after: date(2026, 9, 8), calendar: calendar) == nil)
        task = TodoItem(dueDate: start)
        task.recurrence = TaskRecurrence(anchor: start, occurrenceLimit: 2)
        task.advanceRecurrence(now: date(2026, 9, 30), calendar: calendar)
        assert(task.dueDate == date(2026, 9, 8))
        assert(task.occurrenceHistory?.count == 1)
        print("Recurring-task regression checks passed")
    }
}
