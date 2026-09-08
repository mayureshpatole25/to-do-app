import Foundation

@main
struct TaskPriorityRegression {
    static func main() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","text":"Legacy task","isDone":false,"indentLevel":0}
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(TodoItem.self, from: legacy)
        assert(decodedLegacy.priority == .none)

        let high = TodoItem(text: "Focus task", priority: .high)
        let roundTrip = try JSONDecoder().decode(
            TodoItem.self,
            from: JSONEncoder().encode(high)
        )
        assert(roundTrip.priority == .high)
        assert(TaskPriority.allCases.map(\.label) == [
            "No priority", "Low priority", "Medium priority", "High priority"
        ])
        assert([TaskPriority.low, .medium, .high].map(\.sortRank) == [1, 2, 3])

        print("PASS: legacy default, persistence, menu copy and sort ranks")
    }
}
