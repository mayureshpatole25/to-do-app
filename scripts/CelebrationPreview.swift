import AppKit
import SwiftUI

@main
struct CelebrationPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 280, y: 260, width: 360, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tood · Celebration preview"
        window.contentView = NSHostingView(rootView:
            VStack(spacing: 12) {
                AchievementNotice(celebration: CommandLine.arguments.contains("--streak") ? .streak(6) : .milestone(150), ink: Color(red: 0.125, green: 0.129, blue: 0.118), close: {}, open: {})
                    .environment(\.accessibilityReduceMotion, CommandLine.arguments.contains("--reduced-motion"))
                Text("Milestone preview").font(.system(size: 16))
            }.frame(width: 360, height: 300).background(Color(red: 0.93, green: 0.92, blue: 0.88)))
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        print("WINDOW_ID=\(window.windowNumber)")
        fflush(stdout)
        app.run()
    }
}
