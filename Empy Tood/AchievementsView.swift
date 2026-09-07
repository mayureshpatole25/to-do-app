import SwiftUI

struct AchievementsView: View {
    let manager: StickyManager

    var body: some View {
        HomeAchievementsView(manager: manager)
            .padding(28)
            .background(Color(red: 0.985, green: 0.978, blue: 0.958))
    }
}

/// Shared live activity display for Home and the achievements window.
struct HomeAchievementsView: View {
    let manager: StickyManager
    var selectedStickyIDs: Set<UUID> = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let history = (manager.completionHistory ?? CompletionHistory()).filtered(to: selectedStickyIDs)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    ActivityHeatmapView(map: AchievementHeatmap(records: history.records, now: context.date))
                        .frame(minWidth: 300)
                    metrics(history, at: context.date)
                        .frame(width: 198)
                }
                VStack(spacing: 24) {
                    ActivityHeatmapView(map: AchievementHeatmap(records: history.records, now: context.date))
                        .frame(height: 160)
                    metrics(history, at: context.date)
                }
            }
        }
        .foregroundStyle(Color(white: 0.14))
    }

    private func metrics(_ history: CompletionHistory, at date: Date) -> some View {
        VStack(spacing: 0) {
            metric(history.records.count.formatted(), label: "Total tasks done")
            rule
            metric(history.doneRate.formatted(), unit: "%", label: "Task done rate")
            rule
            metric(String(format: "%02d", history.longestStreak()), label: "Longest streak (days)")
            rule
            metric(String(format: "%02d", history.streak(at: date)), label: "Current streak")
        }
    }

    private var rule: some View {
        Rectangle().fill(Color(white: 0.14).opacity(0.09)).frame(height: 0.5)
    }

    private func metric(_ value: String, unit: String = "", label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.custom("HelveticaNeue", size: 24)).tracking(-0.8)
                if !unit.isEmpty { Text(unit).font(.system(size: 13)) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 48, alignment: .leading)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 0)
        }
        .frame(height: 42)
    }
}

struct ActivityHeatmapView: View {
    let map: AchievementHeatmap
    private let muted = Color(white: 0.43)
    private let bodyFont = Font.system(size: 12)
    private let shades: [Color] = [
        Color(red: 0.92, green: 0.90, blue: 0.87),
        Color(red: 0.99, green: 0.84, blue: 0.67),
        Color(red: 0.98, green: 0.66, blue: 0.36),
        Color(red: 0.92, green: 0.44, blue: 0.13),
        Color(red: 0.72, green: 0.28, blue: 0.06)
    ]

    @State private var hoveredDay: AchievementHeatmap.Day?
    @State private var hoverPoint = CGPoint.zero
    @Namespace private var heatmapSpace

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 3
            let targetSize = max(10, min(21, (geometry.size.height - 27 - 6 * gap) / 7))
            let availableWidth = max(10, geometry.size.width - 20)
            let visibleColumns = max(1, ceil((availableWidth + gap) / (targetSize + gap)))
            let size = (availableWidth - (visibleColumns - 1) * gap) / visibleColumns
            let columnWidth = size + gap
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: gap) {
                    Color.clear.frame(height: 24)
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                        Text(day).font(.system(size: 11)).foregroundStyle(muted)
                            .frame(width: 14, height: size, alignment: .leading)
                    }
                }
                .frame(width: 14)

                ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: gap) {
                        ForEach(map.weeks.indices, id: \.self) { column in
                            VStack(spacing: gap) {
                                Color.clear.frame(height: 24)
                                    .overlay(alignment: .topLeading) {
                                        if let month = map.months[column] {
                                            Text(month).font(bodyFont).foregroundStyle(muted).fixedSize()
                                        }
                                    }
                                ForEach(map.weeks[column]) { day in
                                    RoundedRectangle(cornerRadius: min(4, size * 0.23))
                                        .fill(shades[AchievementHeatmap.level(for: day.count)])
                                        .opacity(day.isFuture ? 0.28 : 1)
                                        .frame(width: size, height: size)
                                        .contentShape(Rectangle())
                                        .onContinuousHover(coordinateSpace: .named(heatmapSpace)) { phase in
                                            switch phase {
                                            case .active(let location):
                                                hoveredDay = day
                                                hoverPoint = location
                                            case .ended:
                                                if hoveredDay?.id == day.id { hoveredDay = nil }
                                            }
                                        }
                                        .accessibilityLabel(tooltip(for: day))
                                }
                            }
                            .frame(width: size)
                            .id(column)
                        }
                    }
                    .frame(width: CGFloat(map.weeks.count) * columnWidth - gap, alignment: .leading)
                }
                .modifier(RecentActivityScrollAnchor())
                .scrollIndicators(.hidden)
                .onChange(of: geometry.size.width) { _, _ in
                    hoveredDay = nil
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(map.weeks.count - 1, anchor: .trailing)
                    }
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: heatmapSpace)
            .overlay(alignment: .topLeading) {
                if let day = hoveredDay {
                    Text(tooltip(for: day))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.25))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(red: 0.985, green: 0.978, blue: 0.958), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.08)))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .fixedSize()
                        .position(x: min(max(105, hoverPoint.x), geometry.size.width - 105), y: max(13, hoverPoint.y - 28))
                        .allowsHitTesting(false)
                }
            }
            .onHover { inside in if !inside { hoveredDay = nil } }
        }
    }

    private func tooltip(for day: AchievementHeatmap.Day) -> String {
        "\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(day.count) \(day.count == 1 ? "task" : "tasks") done"
    }
}

/// Keep the trailing calendar edge stable through viewport and cell-size changes.
private struct RecentActivityScrollAnchor: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .defaultScrollAnchor(.trailing)
                .defaultScrollAnchor(.trailing, for: .sizeChanges)
        } else {
            content.defaultScrollAnchor(.trailing)
        }
    }
}
