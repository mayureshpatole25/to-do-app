import SwiftUI
import Observation

/// Transient UI state belongs to its sticky and is never persisted with tasks.
@MainActor @Observable
final class StickyAchievementNotice {
    var celebration: Celebration?
}

@MainActor
final class CelebrationPresenter {
    private weak var state: StickyAchievementNotice?
    private var timeout: Task<Void, Never>?

    func dismiss() {
        timeout?.cancel()
        timeout = nil
        state?.celebration = nil
        state = nil
    }

    func show(_ celebrations: [Celebration], in target: StickyAchievementNotice) {
        dismiss()
        guard let celebration = celebrations.first(where: \.isMilestone) ?? celebrations.first else { return }
        state = target
        target.celebration = celebration
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

struct AchievementNotice: View {
    let celebration: Celebration
    let close: () -> Void
    let open: () -> Void

    static func message(_ celebration: Celebration) -> String {
        switch celebration {
        case .milestone(let count): return "🥳 Congrats you just marked \(count.formatted()) tasks done!"
        case .streak(let count): return count == 1 ? "🥳 First task done. Nice start!" : "🥳 You’re on a \(count)-day streak!"
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                message.fixedSize()
                Spacer(minLength: 0)
                actions
            }
            VStack(alignment: .leading, spacing: 7) {
                message.fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(minLength: 0); actions }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
    }

    private var message: some View {
        Text(Self.message(celebration)).font(.system(size: 12))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Achievements ↗", action: open)
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.55))
                .fixedSize()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.55))
            .accessibilityLabel("Dismiss achievement notification")
        }
    }
}
