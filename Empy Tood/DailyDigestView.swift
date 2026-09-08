import AppKit
import Foundation

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

        for stickyID in manager.order {
            guard let model = manager.controllers[stickyID]?.model else { continue }
            for item in model.items where !item.isDone && hasText(item) {
                if let dueDate = item.dueDate, dueDate >= today && dueDate < tomorrow {
                    selectedIDs.insert(item.id)
                }
            }
        }

        var priorityIDs = Set<UUID>()
        for stickyID in manager.order where priorityIDs.count < 3 {
            guard let model = manager.controllers[stickyID]?.model,
                  let item = model.items.first(where: {
                      !$0.isDone && $0.priority == .high && !selectedIDs.contains($0.id) && hasText($0)
                  }) else { continue }
            priorityIDs.insert(item.id)
        }
        if priorityIDs.count < 3 {
            for stickyID in manager.order where priorityIDs.count < 3 {
                guard let model = manager.controllers[stickyID]?.model else { continue }
                for item in model.items where priorityIDs.count < 3
                    && !item.isDone && item.priority == .high
                    && !selectedIDs.contains(item.id) && !priorityIDs.contains(item.id)
                    && hasText(item) {
                    priorityIDs.insert(item.id)
                }
            }
        }
        selectedIDs.formUnion(priorityIDs)

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

    init(manager: StickyManager, selection: DailyDigestSelection) {
        self.manager = manager
        self.sourceStickyByItemID = selection.sourceStickyByItemID
        let size = NSSize(width: 420, height: 700)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
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
        sourceStickyByItemID[candidate.id] = candidate.stickyID
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

@MainActor
final class DailyDigestWindowController {
    private let projection: DailyDigestProjection
    private let stickyController: StickyController

    init(manager: StickyManager) {
        let selection = DailyDigestSelection.make(manager: manager)
        let projection = DailyDigestProjection(manager: manager, selection: selection)
        self.projection = projection
        let taskPicker = StickyTaskPickerConfiguration(
            candidates: { [weak projection] in projection?.pickerCandidates() ?? [] },
            didAdd: { [weak projection] candidate in projection?.registerAddedTask(candidate) }
        )
        stickyController = StickyController(
            model: projection.model,
            manager: manager,
            checklistSections: selection.sections,
            taskPicker: taskPicker
        )

        projection.model.onChange = { [weak projection] in
            projection?.syncToSources()
            manager.scheduleSave()
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
        NSApp.activate(ignoringOtherApps: true)
        stickyController.focusForTyping()
    }
}
