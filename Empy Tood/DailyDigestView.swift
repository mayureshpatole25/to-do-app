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

        var items: [TodoItem] = []
        var owners: [UUID: UUID] = [:]
        var sections: [StickyChecklistSection] = []
        for stickyID in manager.order {
            guard let source = manager.controllers[stickyID]?.model else { continue }
            let selected = source.items.filter { selectedIDs.contains($0.id) }
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
        let size = NSSize(
            width: 420,
            height: max(StickyWindowGeometry.minimumHeight, visible.height - 80)
        )
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + 40,
            width: size.width,
            height: size.height
        )
        model = StickyModel(data: StickyData(
            id: UUID(),
            title: Self.titleFormatter.string(from: Date()),
            emoji: nil,
            day: Date(),
            items: selection.items,
            colorID: .cream,
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

    func pickerCandidates() -> [StickyTaskPickerItem] {
        let included = Set(model.items.map(\.id))
        return manager.order.flatMap { stickyID -> [StickyTaskPickerItem] in
            guard let source = manager.controllers[stickyID]?.model else { return [] }
            let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return source.items.compactMap { item in
                guard !item.isDone, !included.contains(item.id),
                      !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return StickyTaskPickerItem(
                    id: item.id,
                    item: item,
                    stickyID: stickyID,
                    stickyTitle: title.isEmpty ? "To Do" : title
                )
            }
        }
    }

    func registerAddedTask(_ candidate: StickyTaskPickerItem) {
        if !sectionOrder.contains(candidate.stickyID) { sectionOrder.append(candidate.stickyID) }
        sourceStickyByItemID[candidate.id] = candidate.stickyID
        sectionTitles[candidate.stickyID] = candidate.stickyTitle
        DailyDigestExclusions.include(candidate.id)
    }

    func registerCreatedTask(_ candidate: StickyTaskPickerItem, beside neighborID: UUID, before: Bool) {
        guard let source = manager.controllers[candidate.stickyID]?.model,
              let index = source.items.firstIndex(where: { $0.id == neighborID }) else { return }
        registerAddedTask(candidate)
        source.items.insert(candidate.item, at: before ? index : index + 1)
        source.onChange?()
    }

    func registerRemovedTask(_ candidate: StickyTaskPickerItem) {
        DailyDigestExclusions.exclude(candidate.id)
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
            didAdd: { [weak projection] candidate in projection?.registerAddedTask(candidate) },
            didRemove: { [weak projection] candidate in projection?.registerRemovedTask(candidate) }
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
        stickyController.closeOverride = { [weak stickyController] in
            stickyController?.panel.orderOut(nil)
        }
        stickyController.archiveOverride = { [weak stickyController] in
            stickyController?.panel.orderOut(nil)
        }
    }

    func present() {
        refreshDay()
        applyTallPresentationFrame()
        NSApp.activate(ignoringOtherApps: true)
        stickyController.focusForTyping()
    }

    private func applyTallPresentationFrame() {
        guard let screen = stickyController.panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = stickyController.panel.frame
        frame.size.height = max(StickyWindowGeometry.minimumHeight, visible.height - 80)
        frame.origin.y = visible.minY + 40
        frame = StickyWindowGeometry.runtimeFrame(frame, visibleFrame: visible)
        stickyController.model.frame = frame
        stickyController.panel.setFrame(frame, display: true)
    }
}
