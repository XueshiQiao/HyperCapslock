import AppKit
import SwiftUI

/// Owns the single main settings window. Hosts `ContentView` via SwiftUI, and
/// hides (rather than closes) on the red button so the app keeps running in the
/// menu bar — matching the Tauri `prevent_close` + hide behavior.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static var shared: MainWindowController?

    let window: NSWindow

    override init() {
        let root = ContentView()
            .environmentObject(AppState.shared)
            .environmentObject(AppState.shared.config)
            .environmentObject(AppState.shared.loc)
        let hosting = NSHostingController(rootView: root)

        window = NSWindow(contentViewController: hosting)
        window.title = "HyperCapslock"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 666, height: 1000))
        window.center()
        super.init()
        window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }
}
