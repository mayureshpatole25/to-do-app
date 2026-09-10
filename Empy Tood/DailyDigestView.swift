import AppKit
import Foundation

private struct DailyDigestEntry: Codable {
    let day: Date
    var note: String
    var items: [TodoItem]
    var owners: [UUID: UUID]
    var sections: [StickyChecklistSection]
}

private enum DailyDigestHistory {
    static func entries() -> [DailyDigestEntry] {
        guard let data = UserDefaults.standard.data(forKey: "today.digestHistory") else { return [] }
        return (try? JSONDecoder().decode([DailyDigestEntry].self, from: data)) ?? []
    }

    static func save(_ entry: DailyDigestEntry) {
        var history = entries().filter { $0.day != entry.day }
        history.append(entry)
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: "today.digestHistory")
    }
}

/// Today is a recurring workspace, so its paper choice belongs to the view
/// itself instead of one dated digest entry. This keeps both preset and custom
/// colours stable across closes, relaunches, and day rollover.
private enum DailyDigestAppearance {
    private static let colorKey = "today.digestColorID"
    private static let customColorKey = "today.digestCustomColorHex"

    static var colorID: StickyColor {
        UserDefaults.standard.string(forKey: colorKey)
            .flatMap(StickyColor.init(rawValue:)) ?? .cream
    }

    static var customColorHex: String? {
        UserDefaults.standard.string(forKey: customColorKey)
    }

    static func save(colorID: StickyColor, customColorHex: String?) {
        UserDefaults.standard.set(colorID.rawValue, forKey: colorKey)
        if let customColorHex {
            UserDefaults.standard.set(customColorHex, forKey: customColorKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customColorKey)
        }
    }
}

private enum DailyDigestWindowGeometry {
    private static let defaultsKey = "today.dailyDigestWindowFrame"
    private static let defaultHeight: CGFloat = 680

    static func initialFrame(in visibleFrame: CGRect) -> CGRect {
        if let savedValue = UserDefaults.standard.string(forKey: defaultsKey) {
            let savedFrame = NSRectFromString(savedValue)
            if savedFrame.width > 0, savedFrame.height > 0 {
                return StickyWindowGeometry.runtimeFrame(savedFrame, visibleFrame: visibleFrame)
            }
        }

        let size = CGSize(
            width: 420,
            height: min(defaultHeight, visibleFrame.height - 80)
        )
        return StickyWindowGeometry.runtimeFrame(
            CGRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            visibleFrame: visibleFrame
        )
    }

    static func save(_ frame: CGRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: defaultsKey)
    }
}

private enum DailyDigestExclusions {
    private static let defaultsKey = "today.dailyDigestExclusions"
    private static let dayKey = "today.dailyDigestExclusionsDay"

    static func ids(now: Date = Date(), calendar: Calendar = .current) -> Set<UUID> {
        let currentDay = dayIdentifier(now, calendar: calendar)
        guard UserDefaults.standard.string(forKey: dayKey) == currentDay else {
            UserDefaults.standard.set(currentDay, forKey: dayKey)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return []
        }
        return Set((UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []).compactMap(UUID.init))
    }

    static func exclude(_ id: UUID) {
        var values = ids()
        values.insert(id)
        save(values)
    }

    static func include(_ id: UUID) {
        var values = ids()
        values.remove(id)
        save(values)
    }

    private static func save(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: defaultsKey)
    }

    private static func dayIdentifier(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

@MainActor
private struct DailyDigestSelection {
    let items: [TodoItem]
    let sourceStickyByItemID: [UUID: UUID]
    let sections: [StickyChecklistSection]

    static func make(
        manager: StickyManager,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyDigestSelection {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(86_400)
        var selectedIDs = Set<UUID>()
        let excludedIDs = DailyDigestExclusions.ids(now: now, calendar: calendar)
        let history = DailyDigestHistory.entries()
        let saved = history.first { calendar.isDate($0.day, inSameDayAs: today) }
        let previous = history.filter { $0.day < today }.max { $0.day < $1.day }
        let carriedIDs = Set((previous?.items ?? []).filter { !$0.isDone }.map(\.id))
        let savedIDs = Set((saved?.items ?? []).map(\.id))

        for stickyID in manager.order {
            guard let model = manager.controllers[stickyID]?.model else { continue }
            for item in model.items where !item.isDone && hasText(item) {
                if !excludedIDs.contains(item.id), carriedIDs.contains(item.id) || savedIDs.contains(item.id) {
                    selectedIDs.insert(item.id)
                }
                if !excludedIDs.contains(item.id),
                   let dueDate = item.dueDate, dueDate >= today && dueDate < tomorrow {
                    selectedIDs.insert(item.id)
                }
            }
        }

        var priorityIDs = Set<UUID>()
        for stickyID in manager.order where priorityIDs.count < 3 {
            guard let model = manager.controllers[stickyID]?.model,
                  let item = model.items.first(where: {
                      !$0.isDone && $0.priority == .high && !selectedIDs.contains($0.id)
                          && !excludedIDs.contains($0.id) && hasText($0)
                  }) else { continue }
            priorityIDs.insert(item.id)
        }
        if priorityIDs.count < 3 {
            for stickyID in manager.order where priorityIDs.count < 3 {
                guard let model = manager.controllers[stickyID]?.model else { continue }
                for item in model.items where priorityIDs.count < 3
                    && !item.isDone && item.priority == .high
                    && !selectedIDs.contains(item.id) && !priorityIDs.contains(item.id)
                    && !excludedIDs.contains(item.id)
                    && hasText(item) {
                    priorityIDs.insert(item.id)
                }
            }
        }
        selectedIDs.formUnion(priorityIDs)
        if saved != nil {
            // Membership is fixed for a saved day, including completed tasks.
            selectedIDs = savedIDs.subtracting(excludedIDs)
        }

        // The Today digest is selected at sticky level. Existing saved days
        // retain their section choices; a fresh day promotes the automatic
        // task suggestions to their owning stickies, then shows every task in
        // each chosen sticky.
        let selectedStickyIDs: Set<UUID>
        if let saved {
            selectedStickyIDs = Set(saved.sections.map(\.id))
        } else {
            selectedStickyIDs = Set(manager.order.filter { stickyID in
                guard let source = manager.controllers[stickyID]?.model else { return false }
                return source.items.contains { selectedIDs.contains($0.id) }
            })
        }

        var items: [TodoItem] = []
        var owners: [UUID: UUID] = [:]
        var sections: [StickyChecklistSection] = []
        for stickyID in manager.order where selectedStickyIDs.contains(stickyID) {
            guard let source = manager.controllers[stickyID]?.model else { continue }
            let selected = source.items.filter(hasText)
            guard !selected.isEmpty else { continue }
            items.append(contentsOf: selected)
            for item in selected { owners[item.id] = stickyID }
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(StickyChecklistSection(
                id: stickyID,
                title: title.isEmpty ? "To Do" : title,
                itemIDs: selected.map(\.id)
            ))
        }
        if let saved {
            let order = saved.sections.map(\.id)
            sections.sort { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
        }
        return DailyDigestSelection(items: items, sourceStickyByItemID: owners, sections: sections)
    }

    private static func hasText(_ item: TodoItem) -> Bool {
        !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Keeps the temporary Today projection and its original sticky tasks in sync.
/// The UI and interaction stack remain the real StickyRootView/StickyController.
@MainActor
private final class DailyDigestProjection {
    let model: StickyModel
    private let manager: StickyManager
    private var sourceStickyByItemID: [UUID: UUID]
    private let day = Calendar.current.startOfDay(for: Date())
    private var sectionTitles: [UUID: String]
    private var sectionOrder: [UUID]

    init(manager: StickyManager, selection: DailyDigestSelection) {
        self.manager = manager
        self.sourceStickyByItemID = selection.sourceStickyByItemID
        self.sectionTitles = Dictionary(uniqueKeysWithValues: selection.sections.map { ($0.id, $0.title) })
        self.sectionOrder = selection.sections.map(\.id)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = DailyDigestWindowGeometry.initialFrame(in: visible)
        model = StickyModel(data: StickyData(
            id: UUID(),
            title: Self.titleFormatter.string(from: Date()),
            emoji: nil,
            day: Date(),
            items: selection.items,
            colorID: DailyDigestAppearance.colorID,
            customColorHex: DailyDigestAppearance.customColorHex,
            fontID: .helvetica,
            frame: frame,
            isVisible: false,
            showsPriorities: true
        ))
        model.dailyNote = DailyDigestHistory.entries().first {
            Calendar.current.isDate($0.day, inSameDayAs: day)
        }?.note ?? ""
        save()
    }

    func save() {
        DailyDigestAppearance.save(colorID: model.colorID, customColorHex: model.customColorHex)
        let sections = sectionOrder.compactMap { stickyID -> StickyChecklistSection? in
            let ids = model.items.filter { sourceStickyByItemID[$0.id] == stickyID }.map(\.id)
            guard !ids.isEmpty else { return nil }
            return StickyChecklistSection(id: stickyID, title: sectionTitles[stickyID] ?? "To Do", itemIDs: ids)
        }
        DailyDigestHistory.save(DailyDigestEntry(day: day, note: model.dailyNote,
            items: model.items, owners: sourceStickyByItemID, sections: sections))
    }

    func syncToSources() {
        for item in model.items {
            guard let stickyID = sourceStickyByItemID[item.id],
                  let source = manager.controllers[stickyID]?.model,
                  let index = source.items.firstIndex(where: { $0.id == item.id }),
                  source.items[index] != item else { continue }
            source.items[index] = item
            source.onChange?()
        }
    }

    func sourceController(for itemID: UUID) -> StickyController? {
        sourceStickyByItemID[itemID].flatMap { manager.controllers[$0] }
    }

    func pickerCandidates() -> [StickyPickerItem] {
        manager.order.compactMap { stickyID -> StickyPickerItem? in
            guard let source = manager.controllers[stickyID]?.model else { return nil }
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = source.items.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard !items.isEmpty else { return nil }
            return StickyPickerItem(
                id: stickyID,
                title: title.isEmpty ? "To Do" : title,
                items: items
            )
        }
    }

    func setIncluded(_ candidate: StickyPickerItem, included: Bool) {
        if included {
            if !sectionOrder.contains(candidate.id) { sectionOrder.append(candidate.id) }
            sectionTitles[candidate.id] = candidate.title
            for item in candidate.items { sourceStickyByItemID[item.id] = candidate.id }
        } else {
            sectionOrder.removeAll { $0 == candidate.id }
            sectionTitles.removeValue(forKey: candidate.id)
            for item in candidate.items { sourceStickyByItemID.removeValue(forKey: item.id) }
        }
    }

    func registerCreatedTask(_ candidate: StickyTaskPickerItem, beside neighborID: UUID, before: Bool) {
        guard let source = manager.controllers[candidate.stickyID]?.model,
              let index = source.items.firstIndex(where: { $0.id == neighborID }) else { return }
        if !sectionOrder.contains(candidate.stickyID) { sectionOrder.append(candidate.stickyID) }
        sourceStickyByItemID[candidate.id] = candidate.stickyID
        sectionTitles[candidate.stickyID] = candidate.stickyTitle
        source.items.insert(candidate.item, at: before ? index : index + 1)
        source.onChange?()
    }

    func updateSections(_ sections: [StickyChecklistSection]) {
        sectionOrder = sections.map(\.id)
        for section in sections {
            if sectionTitles[section.id] != section.title {
                manager.controllers[section.id]?.model.setTitle(section.title)
            }
            sectionTitles[section.id] = section.title
        }
        save()
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

@MainActor
final class DailyDigestWindowController {
    private var projection: DailyDigestProjection!
    private var stickyController: StickyController!
    private let manager: StickyManager
    private var day = Calendar.current.startOfDay(for: Date())
    private var rolloverTimer: Timer?

    init(manager: StickyManager) {
        self.manager = manager
        rebuild()
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDay() }
        }
    }

    deinit { rolloverTimer?.invalidate() }

    private func refreshDay() {
        let today = Calendar.current.startOfDay(for: Date())
        guard day != today else { return }
        let wasVisible = stickyController.panel.isVisible
        projection.save()
        stickyController.panel.orderOut(nil)
        day = today
        rebuild()
        if wasVisible { stickyController.focusForTyping() }
    }

    private func rebuild() {
        let selection = DailyDigestSelection.make(manager: manager)
        let projection = DailyDigestProjection(manager: manager, selection: selection)
        self.projection = projection
        let taskPicker = StickyTaskPickerConfiguration(
            sectionsChanged: { [weak projection] sections in projection?.updateSections(sections) },
            didCreate: { [weak projection] candidate, neighborID, before in
                projection?.registerCreatedTask(candidate, beside: neighborID, before: before)
            },
            candidates: { [weak projection] in projection?.pickerCandidates() ?? [] },
            didSetIncluded: { [weak projection] candidate, included in
                projection?.setIncluded(candidate, included: included)
            }
        )
        stickyController = StickyController(
            model: projection.model,
            manager: manager,
            checklistSections: selection.sections,
            taskPicker: taskPicker
        )

        projection.model.onChange = { [weak projection, weak manager] in
            projection?.syncToSources()
            projection?.save()
            manager?.scheduleSave()
        }
        stickyController.completionReportingController = { [weak projection] itemID in
            projection?.sourceController(for: itemID)
        }
        stickyController.onFrameChange = { frame in
            DailyDigestWindowGeometry.save(frame)
        }
        stickyController.closeOverride = { [weak stickyController] in
            stickyController?.panel.orderOut(nil)
        }
        stickyController.archiveOverride = { [weak stickyController] in
            stickyController?.panel.orderOut(nil)
        }
    }

    func present() {
        refreshDay()
        NSApp.activate(ignoringOtherApps: true)
        stickyController.focusForTyping()
    }
}
