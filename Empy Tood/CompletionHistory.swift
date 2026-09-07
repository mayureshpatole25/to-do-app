import Foundation

struct CompletionRecord: Codable {
    var id: UUID
    var key: String
    var text: String
    var color: String
    var completedAt: Date
}

enum Celebration: Equatable {
    case milestone(Int)
    case streak(Int)
    var number: Int {
        switch self { case .milestone(let n), .streak(let n): return n }
    }
    var caption: String {
        switch self {
        case .milestone: return "tasks done"
        case .streak(let n): return n == 1 ? "day started" : "day streak"
        }
    }
    var isMilestone: Bool { if case .milestone = self { return true }; return false }
}

/// Durable completions survive deletion of a sticky. Claimed celebrations are
/// stored separately, so undo/recheck and relaunch cannot replay a milestone.
struct CompletionHistory: Codable {
    var records: [CompletionRecord] = []
    var highestCelebratedMilestone = 0
    var celebratedDays: Set<String> = []
    var createdTaskKeys: Set<String>?
    var taskStickyIDs: [String: UUID]?

    mutating func registerOwners(_ owners: [String: UUID]) {
        taskStickyIDs = (taskStickyIDs ?? [:]).merging(owners) { _, latest in latest }
    }

    func filtered(to stickyIDs: Set<UUID>) -> CompletionHistory {
        guard !stickyIDs.isEmpty else { return self }
        func includes(_ key: String) -> Bool {
            guard let taskID = key.split(separator: ":").first,
                  let owner = taskStickyIDs?[String(taskID)] else { return false }
            return stickyIDs.contains(owner)
        }
        var result = self
        result.records = records.filter { includes($0.key) }
        result.createdTaskKeys = Set((createdTaskKeys ?? []).filter(includes))
        return result
    }

    var totalCreated: Int { Set(records.map(\.key)).union(createdTaskKeys ?? []).count }
    var doneRate: Int { totalCreated == 0 ? 0 : Int((Double(records.count) / Double(totalCreated) * 100).rounded()) }

    mutating func registerCreated(_ keys: Set<String>) {
        createdTaskKeys = (createdTaskKeys ?? []).union(keys).union(records.map(\.key))
    }

    func longestStreak(calendar: Calendar = .current) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.completedAt) })
            .filter { !calendar.isDateInWeekend($0) }.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            var expected = calendar.date(byAdding: .day, value: -1, to: day)!
            while calendar.isDateInWeekend(expected) { expected = calendar.date(byAdding: .day, value: -1, to: expected)! }
            run = previous == expected ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    static func key(itemID: UUID, scheduledAt: Date?) -> String {
        itemID.uuidString + (scheduledAt.map { ":" + ISO8601DateFormatter().string(from: $0) } ?? "")
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Weekends pause the count. Completing a weekend task still contributes
    /// to the lifetime total, while Monday continues Friday's weekday streak.
    func streak(at now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.completedAt) })
        var cursor = calendar.startOfDay(for: now)
        func previous(_ day: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: day)! }
        while calendar.isDateInWeekend(cursor) { cursor = previous(cursor) }
        if !days.contains(cursor), calendar.isDate(cursor, inSameDayAs: now) {
            cursor = previous(cursor)
        }
        var count = 0
        while true {
            if calendar.isDateInWeekend(cursor) { cursor = previous(cursor); continue }
            guard days.contains(cursor) else { break }
            count += 1
            cursor = previous(cursor)
        }
        return count
    }

    mutating func seed(_ entries: [CompletionRecord], now: Date = Date()) {
        var keys = Set(records.map(\.key))
        for entry in entries where keys.insert(entry.key).inserted { records.append(entry) }
        registerCreated(keys)
        highestCelebratedMilestone = max(highestCelebratedMilestone, records.count / 50 * 50)
        for entry in records { celebratedDays.insert(Self.dayKey(entry.completedAt)) }
    }

    mutating func complete(_ entry: CompletionRecord, now: Date = Date(), calendar: Calendar = .current) -> [Celebration] {
        guard !records.contains(where: { $0.key == entry.key }) else { return [] }
        records.append(entry)
        registerCreated([entry.key])
        var result: [Celebration] = []
        let milestone = records.count / 50 * 50
        if milestone > highestCelebratedMilestone {
            highestCelebratedMilestone = milestone
            result.append(.milestone(milestone))
        }
        let day = Self.dayKey(entry.completedAt, calendar: calendar)
        if calendar.isDate(entry.completedAt, inSameDayAs: now), celebratedDays.insert(day).inserted {
            let count = streak(at: now, calendar: calendar)
            if count > 0 { result.append(.streak(count)) }
        }
        return result
    }

    mutating func reopen(key: String) { records.removeAll { $0.key == key } }
}

enum CompletionHistoryStore {
    static var url: URL { AppIdentity.dataDirectory.appendingPathComponent("completion_history.json") }
    static func load() throws -> CompletionHistory {
        guard FileManager.default.fileExists(atPath: url.path) else { return CompletionHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CompletionHistory.self, from: Data(contentsOf: url))
    }
    static func save(_ history: CompletionHistory) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: AppIdentity.dataDirectory, withIntermediateDirectories: true)
        try encoder.encode(history).write(to: url, options: .atomic)
    }
}
