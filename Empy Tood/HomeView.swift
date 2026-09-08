import AppKit
import SwiftUI

/// Shared sizing so the fan layout math and the card itself never drift
/// apart. Narrower/taller than the first pass — closer to the real
/// floating sticky's portrait proportions (378×490-ish) instead of the
/// landscape-ish 200×178 it started as. The inline archive row reuses these
/// same numbers so archived and live stickies remain visually identical.
enum DeskCardMetrics {
    static let width: CGFloat = 178
    static let height: CGFloat = 200
    static let cornerRadius: CGFloat = 5
}

/// The Home screen: greeting and activity heatmap up top,
/// the intentionally messy sticky fan bottom-left, and a direct new-list
/// action bottom-right. No chrome at all — settings lives in the status-bar
/// menu set up during onboarding.
///
/// Reads directly off `StickyManager`, the same source of truth the floating
/// stickies use, so it updates live.
struct HomeView: View {
    // The fixed card fan, focus control, greeting, actions, and a two-line
    // announcement all fit without compression at this content size.
    static let minimumSize = CGSize(width: 720, height: 770)

    let manager: StickyManager
    var onShowDailyDigest: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var locationLabel: String?
    @State private var overviewStickyIDs: Set<UUID> = []
    @State private var showingStickyFilter = false
    @State private var stickySearch = ""
    private var archivedEntries: [ArchivedSticky] { manager.archivedStickies }

    private let desk = Color(hex: 0xFBF8F1)
    private static let archiveSectionID = "home-archive-section"

    var body: some View {
        ZStack {
            // Keep the paper fixed while the dashboard and archive row move
            // across it as one continuous scroll surface.
            desk.ignoresSafeArea()
            PaperDotsBackground().ignoresSafeArea()

            GeometryReader { viewport in
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            dashboard(scrollProxy: scrollProxy)
                                .frame(
                                    width: viewport.size.width
                                )
                            archivedSection
                                .frame(width: viewport.size.width)
                                .id(Self.archiveSectionID)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
        // AppKit owns the actual window minimum. Keeping SwiftUI flexible here
        // prevents NSHostingView from adding the hidden-titlebar safe-area to
        // that minimum (which used to turn a declared 520pt limit into 552pt).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Home is ambient UI, so opening the app must never trigger a
            // system permission dialog. If access was granted previously,
            // we can still show the quiet location next to today's date.
            LocationStamper.shared.requestLabelIfAuthorized { locationLabel = $0 }
        }
    }

    private func dashboard(scrollProxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                announcementBanner
                topRow
                VStack(spacing: 18) {
                    overviewHeader.zIndex(2)
                    sectionDivider
                    HomeAchievementsView(manager: manager, selectedStickyIDs: overviewStickyIDs)
                        .frame(height: 190)
                }
                .padding(.top, 58)
                .zIndex(2)
                Color.clear.frame(height: 58)
                bottomRow
            }
            .animation(.easeInOut(duration: 0.25), value: AnnouncementService.shared.current)
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .padding(.bottom, 44)


        }
    }

    private var overviewStickies: [(id: UUID, title: String)] {
        let live = manager.order.compactMap { id -> (id: UUID, title: String)? in
            guard let model = manager.controllers[id]?.model else { return nil }
            return (id, model.title.isEmpty ? "To Do" : model.title)
        }
        return live + manager.archivedStickies.map { ($0.data.id, $0.data.title.isEmpty ? "To Do" : $0.data.title) }
    }

    private var overviewFilterLabel: String {
        if overviewStickyIDs.isEmpty { return "All stickies" }
        if overviewStickyIDs.count == 1 {
            return overviewStickies.first { overviewStickyIDs.contains($0.id) }?.title ?? "1 sticky"
        }
        return "\(overviewStickyIDs.count) stickies"
    }

    private var overviewHeader: some View {
        HStack {
            Text("Overview").font(.system(size: 20, weight: .medium))
            Spacer()
            HStack(spacing: 6) {
                Button { showingStickyFilter = true } label: {
                    HStack(spacing: 8) {
                        Text(overviewFilterLabel).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, overviewStickyIDs.isEmpty ? 12 : 0)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !overviewStickyIDs.isEmpty {
                    Button { overviewStickyIDs.removeAll() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear sticky filter")
                }
            }
            .font(.system(size: 12))
            .background(desk, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .frame(maxWidth: 240, alignment: .trailing)
            .overlay(alignment: .topTrailing) {
                if showingStickyFilter {
                    stickyFilterMenu
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
                        .background(StickyFilterDismissTarget { showingStickyFilter = false })
                        .offset(y: 38)
                        .onExitCommand { showingStickyFilter = false }
                }
            }
        }
    }

    private var stickyFilterMenu: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search stickies…", text: $stickySearch).textFieldStyle(.plain)
                if !overviewStickyIDs.isEmpty {
                    Button { overviewStickyIDs.removeAll() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear sticky filter")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.2)))
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(overviewStickies.filter { stickySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(stickySearch) }, id: \.id) { sticky in
                        Button {
                            if overviewStickyIDs.contains(sticky.id) { overviewStickyIDs.remove(sticky.id) }
                            else { overviewStickyIDs.insert(sticky.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Text(sticky.title).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "checkmark")
                                    .opacity(overviewStickyIDs.contains(sticky.id) ? 1 : 0)
                                    .frame(width: 12)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(overviewStickyIDs.contains(sticky.id) ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(overviewStickyIDs.contains(sticky.id) ? "Selected" : "Not selected")
                    }
                    if !stickySearch.isEmpty && !overviewStickies.contains(where: { $0.title.localizedCaseInsensitiveContains(stickySearch) }) {
                        Text("No matching stickies").foregroundStyle(.secondary).padding(12)
                    }
                }
            }
            .frame(height: 240)
        }
        .font(.system(size: 13))
        .padding(8)
        .frame(width: 250)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { stickySearch = "" }
    }

    // MARK: - Announcement banner (see AnnouncementService)

    @ViewBuilder
    private var announcementBanner: some View {
        if let announcement = AnnouncementService.shared.current {
            HStack(spacing: 12) {
                Text(announcement.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x20211E))
                    .fixedSize(horizontal: false, vertical: true)
                if let urlString = announcement.url, let url = URL(string: urlString) {
                    Link(announcement.linkLabel ?? "Learn more", destination: url)
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer(minLength: 12)
                Button { AnnouncementService.shared.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0x94F48F).opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Greeting and date

    private var topRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 24) {
                Text(greeting)
                    .font(.system(size: 40, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    newToDoListButton.fixedSize()
                    dailyDigestButton
                }
            }
            Text(dateLine)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Inline archive

    /// Lives immediately below the normal dashboard. Aligning its bottom to
    /// the viewport makes Archive scroll only far enough to reveal this row,
    /// leaving the lower part of Home visible above it for spatial context.
    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Archived Stickies")
                    .font(.system(size: 20, weight: .medium))
                Text("\(archivedEntries.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Click a sticky to restore and open it")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            sectionDivider
            archivedStickiesFan.padding(.top, 54)
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .padding(.bottom, 44)
        .frame(minHeight: 330, alignment: .topLeading)
    }

    private var archivedStickiesFan: some View {
        Group {
            if archivedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing archived yet")
                        .font(.system(size: 15, weight: .medium))
                    Text("Archived stickies will appear here when you need them again.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 24)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        let positions = StickyFanLayout.positions(
                            count: max(manager.order.count, archivedEntries.count),
                            availableWidth: proxy.size.width,
                            cardWidth: DeskCardMetrics.width
                        )
                        ForEach(Array(archivedEntries.enumerated()), id: \.element.id) { index, entry in
                            let model = StickyModel(data: entry.data)
                            StickyDeskCard(model: model, hoverHint: "Restore") {
                                manager.restoreArchived(entry)
                            }
                            .rotationEffect(.degrees(rotation(for: index)))
                            .offset(x: positions[index], y: verticalOffset(for: index))
                            .zIndex(Double(index))
                            .contextMenu {
                                Button("Delete Permanently", role: .destructive) {
                                    requestDeleteArchived(entry)
                                }
                            }
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: DeskCardMetrics.height + 45)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: archivedEntries.map(\.id))
    }

    private func requestDeleteArchived(_ entry: ArchivedSticky) {
        let alert = NSAlert()
        alert.messageText = "Delete this archived sticky for good?"
        let title = entry.data.title.isEmpty ? "To Do" : entry.data.title
        alert.informativeText = "\"\(title)\" will be gone for good, and can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.deleteArchived(entry.id)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        return "Good \(part), \(Self.firstName)."
    }

    /// "Friday, July 31 · Noe Valley" — quiet, only appears once Location
    /// Services actually resolves something (never blocks or shows an error).
    private var dateLine: String {
        let date = Self.dateFormatter.string(from: Date())
        guard let locationLabel else { return date }
        return "\(date) · \(locationLabel)"
    }

    private static var firstName: String {
        let override = AppSettings.shared.userName
        if !override.isEmpty { return override }
        let full = NSFullUserName()
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    // MARK: - Bottom stickies

    private var bottomRow: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("All stickies")
                    .font(.system(size: 20, weight: .medium))
                Text("\(manager.order.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            sectionDivider
            stickiesFan.padding(.top, 54)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color(hex: 0x20211E).opacity(0.1))
            .frame(height: 1)
    }

    /// No scroll view, no clipping, no fade — the fan just gets denser as
    /// more stickies are added, always fitting the
    /// available width instead of needing to scroll past an edge. That also
    /// means shadows render in full; nothing's there to cut them off.
    private var stickiesFan: some View {
        Group {
            if manager.order.isEmpty {
                emptyStickyState
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        let positions = StickyFanLayout.positions(
                            count: max(manager.order.count, archivedEntries.count),
                            availableWidth: proxy.size.width,
                            cardWidth: DeskCardMetrics.width
                        )
                        ForEach(Array(manager.order.enumerated()), id: \.element) { index, id in
                            if let controller = manager.controllers[id] {
                                StickyDeskCard(
                                    model: controller.model,
                                    onShow: { manager.bringToFront(id) }
                                )
                                    .rotationEffect(.degrees(rotation(for: index)))
                                    .offset(x: positions[index], y: verticalOffset(for: index))
                                    // Preserve the fan's existing overlap order while
                                    // hovering; the card itself supplies the small lift.
                                    .zIndex(Double(index))
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: DeskCardMetrics.height + 45) // card height + rotation/hover/shadow headroom
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.order)
    }

    /// Zero stickies — a real sticky (same paper/title look as
    /// `StickyDeskCard`, in whatever the default color is), not a generic
    /// dashed placeholder, with its own invitation to create the first one.
    private var emptyStickyState: some View {
        let color = StickyColor.defaultColor ?? .pink
        return Button { manager.newSticky() } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("To Do")
                    .font(.custom("HelveticaNeue", size: 17))
                    .foregroundStyle(color.titleInk)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(color.ink.opacity(0.6))
                    Text("Create your first")
                        .font(.system(size: 12.5))
                        .foregroundStyle(color.ink.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: DeskCardMetrics.width, height: DeskCardMetrics.height, alignment: .topLeading)
            .background(color.paper, in: RoundedRectangle(cornerRadius: DeskCardMetrics.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 13, y: 8)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rotation(for index: Int) -> Double {
        [-3, 1.5, -1.5, 2.5, -2][index % 5]
    }

    private func verticalOffset(for index: Int) -> Double {
        [8, 16, 4, 12, 6][index % 5] // modest stagger
    }

    private var newToDoListButton: some View {
        Button { manager.newSticky() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New To Do List")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(desk)
            .padding(.horizontal, 14)
            .frame(width: 158, height: 30)
            .background(Color(hex: 0x20211E), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .help("Create a new to-do list")
    }

    private var dailyDigestButton: some View {
        Button(action: onShowDailyDigest) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.system(size: 11, weight: .semibold))
                Text("Today's List")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color(hex: 0x20211E))
            .frame(width: 158, height: 30)
            .background(desk, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Open today's focused task list")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

/// One sticky on the desk — same paper color/type as the real sticky, sized
/// up to be the clear focal point, with a hover hint that appears when
/// hovering its corner specifically (not the whole card). Defaults to "Pop
/// out", foreshadowing the real floating window it becomes when clicked.
/// The inline archive row overrides that hint with "Restore" but still opens
/// that same real window through `StickyManager.restoreArchived`.
struct StickyDeskCard: View {
    let model: StickyModel
    var hoverHint: String = "Pop out"
    var hoverLiftDistance: CGFloat = 66
    var onShow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var hoveringCorner = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.title.isEmpty ? "To Do" : model.title)
                    .font(.custom("HelveticaNeue", size: 17))
                    .foregroundStyle(model.color.titleInk)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.items.prefix(3)) { item in
                        HStack(spacing: 8) {
                            // Same shape/values as the real sticky's checkbox
                            // (StickyRootView.checkbox), just not interactive here.
                            ZStack {
                                if item.isDone {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(model.color.ink.opacity(0.3))
                                        .frame(width: 11, height: 11)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(model.color.paper)
                                } else {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .stroke(model.color.ink.opacity(0.3), lineWidth: 1.1)
                                        .frame(width: 11, height: 11)
                                }
                            }
                            .frame(width: 11, height: 11)
                            Text(item.text.isEmpty ? " " : item.text)
                                .font(model.font.body(12.5))
                                .foregroundStyle(item.isDone ? model.color.inkSecondary : model.color.ink.opacity(0.8))
                                .strikethrough(item.isDone, color: model.color.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: DeskCardMetrics.width, height: DeskCardMetrics.height, alignment: .topLeading)
            .background(model.color.paper, in: RoundedRectangle(cornerRadius: DeskCardMetrics.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(hovering ? 0.28 : 0.2), radius: hovering ? 20 : 13, y: hovering ? 12 : 8)
            .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
            .offset(y: hoverLift)

            if hoveringCorner {
                Text(hoverHint)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.8), in: Capsule())
                    .foregroundStyle(.white)
                    .offset(x: -10, y: hoverLift + 10)
                    .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DeskCardMetrics.cornerRadius, style: .continuous))
        .onTapGesture(perform: onShow)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open sticky"), onShow)
        .onHover { isHovering in
            hovering = isHovering
            if !isHovering { hoveringCorner = false }
        }
        .overlay(alignment: .topTrailing) {
            // A dedicated hover target just for the corner, matching the
            // request that "Pop out" only appears there, not the whole card.
            Color.clear
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .onHover { hoveringCorner = $0 }
                .offset(y: hoverLift)
        }
        .animation(.easeOut(duration: 0.2), value: hovering)
    }

    private var hoverLift: CGFloat {
        hovering && !reduceMotion ? -hoverLiftDistance : 0
    }
}

/// Dismiss the arrowless filter on outside clicks, without intercepting its rows.
private struct StickyFilterDismissTarget: NSViewRepresentable {
    let dismiss: () -> Void

    func makeNSView(context: Context) -> Target {
        let view = Target()
        view.dismiss = dismiss
        return view
    }
    func updateNSView(_ nsView: Target, context: Context) { nsView.dismiss = dismiss }
    static func dismantleNSView(_ nsView: Target, coordinator: ()) { nsView.stop() }

    final class Target: NSView {
        var dismiss: (() -> Void)?
        private var local: Any?
        private var global: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.dismiss?()
                }
                return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismiss?()
            }
        }
        func stop() {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
            local = nil
            global = nil
        }
        deinit { stop() }
    }
}
