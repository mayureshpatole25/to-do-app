import AppKit
import Combine
import SwiftUI

@MainActor
final class SpotifyPlaybackController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPlaying = false
    @Published private(set) var trackName = "Open Spotify"
    @Published private(set) var artistName = "Play something to get started"
    @Published private(set) var artworkURL: URL?
    @Published private(set) var duration: Double = 0
    @Published private(set) var position: Double = 0

    private var refreshTimer: Timer?
    private var pendingPlaybackState: Bool?
    private var pendingPlaybackDeadline: Date?
    private var refreshGeneration = 0
    private let commandQueue = DispatchQueue(label: "com.empy.EmpyTood.spotify-commands", qos: .userInitiated)

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    func start() {
        guard refreshTimer == nil else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func togglePlayback() {
        guard isRunning else {
            openSpotify()
            return
        }
        let intendedState = !isPlaying
        pendingPlaybackState = intendedState
        pendingPlaybackDeadline = Date().addingTimeInterval(1.5)
        isPlaying = intendedState
        runInBackground(command: intendedState ? "play" : "pause")
    }

    func previousTrack() {
        runInBackground(command: "previous track")
    }

    func nextTrack() {
        runInBackground(command: "next track")
    }

    func openSpotify() {
        guard let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            return
        }
        NSWorkspace.shared.openApplication(at: spotifyURL, configuration: .init()) { [weak self] _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                self?.refresh()
            }
        }
    }

    private func runInBackground(command: String) {
        let source = """
        tell application id "com.spotify.client"
            \(command)
        end tell
        """
        commandQueue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        let source = """
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client"
                try
                    set currentTrack to current track
                    set trackTitle to name of currentTrack
                    set trackArtist to artist of currentTrack
                    set trackArtwork to artwork url of currentTrack
                    set trackDuration to duration of currentTrack
                    set trackPosition to player position
                    set playbackState to player state as string
                    return trackTitle & "|||" & trackArtist & "|||" & trackArtwork & "|||" & trackDuration & "|||" & trackPosition & "|||" & playbackState
                on error
                    return "__RUNNING__"
                end try
            end tell
        else
            return "__CLOSED__"
        end if
        """

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var error: NSDictionary?
            guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
                return
            }
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == generation else { return }
                self.applyRefreshResult(result)
            }
        }
    }

    private func applyRefreshResult(_ result: String) {
        if result == "__CLOSED__" {
            pendingPlaybackState = nil
            pendingPlaybackDeadline = nil
            isRunning = false
            isPlaying = false
            trackName = "Open Spotify"
            artistName = "Play something to get started"
            artworkURL = nil
            duration = 0
            position = 0
            return
        }

        isRunning = true
        guard result != "__RUNNING__" else {
            if pendingPlaybackState == nil { isPlaying = false }
            trackName = "Spotify is ready"
            artistName = "Choose something to play"
            artworkURL = nil
            duration = 0
            position = 0
            return
        }

        let fields = result.components(separatedBy: "|||")
        guard fields.count == 6 else { return }
        trackName = fields[0]
        artistName = fields[1]
        artworkURL = URL(string: fields[2])
        duration = Double(fields[3]) ?? 0
        position = Double(fields[4]) ?? 0
        let reportedState = fields[5] == "playing"
        if let intendedState = pendingPlaybackState {
            if reportedState == intendedState {
                pendingPlaybackState = nil
                pendingPlaybackDeadline = nil
                isPlaying = reportedState
            } else if let deadline = pendingPlaybackDeadline, Date() >= deadline {
                pendingPlaybackState = nil
                pendingPlaybackDeadline = nil
                isPlaying = reportedState
            }
        } else {
            isPlaying = reportedState
        }
    }
}

struct SpotifyMiniPlayer: View {
    @ObservedObject var player: SpotifyPlaybackController
    let isPresented: Bool
    let ink: Color
    let paper: Color
    let font: (CGFloat) -> Font

    @State private var isHovering = false
    @State private var occupiesSpace = false
    @State private var baseVisible = false
    @State private var expanded = false
    @State private var metadataVisible = false
    @State private var controlsVisible = false
    @State private var revealTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Capsule()
                .fill(ink.opacity(isHovering ? 0.085 : 0.065))
                .overlay {
                    Capsule().stroke(paper.opacity(0.45), lineWidth: 0.75)
                }
                .shadow(color: ink.opacity(0.08), radius: 8, y: 3)
                .frame(width: expanded ? 286 : 72, height: 72)
                .opacity(baseVisible ? 1 : 0)
                .scaleEffect(baseVisible ? 1 : 0.94)
                .offset(y: baseVisible ? 0 : 10)

            VinylArtwork(
                artworkURL: player.artworkURL,
                isPlaying: player.isPlaying,
                ink: ink,
                paper: paper
            )
            .offset(x: expanded ? -107 : 0)
            .offset(y: baseVisible ? 0 : 10)
            .opacity(baseVisible ? 1 : 0)
            .scaleEffect(baseVisible ? 1 : 0.94)

            HStack(spacing: 10) {
                Color.clear.frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(text: player.trackName, font: font(12), color: ink.opacity(0.82))
                    Text(player.artistName)
                        .font(font(10))
                        .foregroundStyle(ink.opacity(0.46))
                        .lineLimit(1)
                }
                .opacity(metadataVisible ? 1 : 0)

                HStack(spacing: 1) {
                    controlButton("backward.fill", label: "Previous track") {
                        player.previousTrack()
                    }
                    .disabled(!player.isRunning)

                    controlButton(player.isPlaying ? "pause.fill" : "play.fill",
                                  label: player.isPlaying ? "Pause" : "Play") {
                        player.togglePlayback()
                    }
                    .background(ink.opacity(0.10), in: Circle())

                    controlButton("forward.fill", label: "Next track") {
                        player.nextTrack()
                    }
                    .disabled(!player.isRunning)
                }
                .opacity(controlsVisible ? 1 : 0)
            }
            .padding(9)
            .frame(width: 286, height: 72)
        }
        .frame(width: 286, height: 72)
        .padding(.top, 14)
        .frame(height: occupiesSpace ? 86 : 0, alignment: .bottom)
        .clipped()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { player.openSpotify() }
        .accessibilityElement(children: .contain)
        .allowsHitTesting(isPresented)
        .onAppear { setPresented(isPresented) }
        .onChange(of: isPresented) { _, presented in setPresented(presented) }
        .onDisappear { revealTask?.cancel() }
    }

    private func setPresented(_ presented: Bool) {
        revealTask?.cancel()
        guard !reduceMotion else {
            occupiesSpace = presented
            baseVisible = presented
            expanded = presented
            metadataVisible = presented
            controlsVisible = presented
            return
        }

        revealTask = Task { @MainActor in
            if presented {
                occupiesSpace = true
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.4)) { baseVisible = true }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.6)) { expanded = true }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) { metadataVisible = true }
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) { controlsVisible = true }
            } else {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) { controlsVisible = false }
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) { metadataVisible = false }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.6)) { expanded = false }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.4)) { baseVisible = false }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                occupiesSpace = false
            }
        }
    }

    private func controlButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ink.opacity(isHovering ? 0.68 : 0.52))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct MusicEqualizerIcon: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    bar(scale: reduceMotion ? [0.48, 0.72, 0.38][index] : level(at: timeline.date, index: index))
                }
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    private func bar(scale: CGFloat) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 2.5, height: 11)
            .scaleEffect(x: 1, y: scale, anchor: .bottom)
    }

    private func level(at date: Date, index: Int) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate
        let frequencies = [3.7, 4.9, 4.15]
        let phases = [0.2, 2.1, 4.4]
        let primary = abs(sin(time * frequencies[index] + phases[index]))
        let drift = abs(sin(time * 0.73 + Double(index) * 1.9))
        return 0.2 + CGFloat(primary * 0.58 + drift * 0.22)
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let textWidth = measuredWidth
            if textWidth <= proxy.size.width || reduceMotion {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let cycle = textWidth + 28
                    let offset = -(timeline.date.timeIntervalSinceReferenceDate * 16)
                        .truncatingRemainder(dividingBy: cycle)
                    HStack(spacing: 28) {
                        tickerCopy
                        tickerCopy
                    }
                    .offset(x: offset)
                }
            }
        }
        .frame(height: 16)
        .clipped()
        .accessibilityLabel(text)
    }

    private var tickerCopy: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var measuredWidth: CGFloat {
        (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12)
        ]).width
    }
}

private struct VinylArtwork: View {
    let artworkURL: URL?
    let isPlaying: Bool
    let ink: Color
    let paper: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accumulatedRotation = 0.0
    @State private var rotationStartedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { timeline in
            disc
                .rotationEffect(.degrees(rotation(at: timeline.date)))
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
        .onAppear {
            if isPlaying, !reduceMotion { rotationStartedAt = Date() }
        }
        .onChange(of: isPlaying) { _, isPlaying in
            if isPlaying, !reduceMotion {
                rotationStartedAt = Date()
            } else {
                captureRotation()
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                captureRotation()
            } else if isPlaying {
                rotationStartedAt = Date()
            }
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.84))

            Group {
                if let artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                .frame(width: 56, height: 56)
            Circle()
                .fill(Color.black.opacity(0.86))
                .frame(width: 9, height: 9)
            Circle()
                .fill(paper.opacity(0.72))
                .frame(width: 2.5, height: 2.5)
        }
        .shadow(color: ink.opacity(0.14), radius: 3, y: 1)
    }

    private var placeholder: some View {
        ZStack {
            paper.opacity(0.82)
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink.opacity(0.42))
        }
    }

    private func rotation(at date: Date) -> Double {
        guard !reduceMotion, let rotationStartedAt else { return accumulatedRotation }
        return accumulatedRotation + date.timeIntervalSince(rotationStartedAt) / 8 * 360
    }

    private func captureRotation() {
        guard let rotationStartedAt else { return }
        accumulatedRotation = (
            accumulatedRotation + Date().timeIntervalSince(rotationStartedAt) / 8 * 360
        ).truncatingRemainder(dividingBy: 360)
        self.rotationStartedAt = nil
    }
}
