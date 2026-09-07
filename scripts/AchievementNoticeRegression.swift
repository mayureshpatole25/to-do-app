import Foundation

@main
struct AchievementNoticeRegression {
    @MainActor static func main() async throws {
        let presenter = CelebrationPresenter()
        let first = StickyAchievementNotice()
        let second = StickyAchievementNotice()
        presenter.show([.streak(2), .milestone(150)], in: first)
        assert(first.celebration == .milestone(150))
        presenter.show([.streak(3)], in: second)
        assert(first.celebration == nil && second.celebration == .streak(3))
        presenter.dismiss()
        assert(second.celebration == nil)
        presenter.show([.milestone(200)], in: first)
        try await Task.sleep(for: .seconds(3))
        assert(first.celebration == .milestone(200))
        presenter.show([.milestone(250)], in: first)
        try await Task.sleep(for: .seconds(2.5))
        assert(first.celebration == .milestone(250), "An older timer must not dismiss a newer notice")
        try await Task.sleep(for: .seconds(2.7))
        assert(first.celebration == nil)
        print("PASS: milestone priority, sticky ownership, close, replacement and five-second timeout")
    }
}
