import AppKit
import SwiftUI

/// Owns the single main settings window. Hosts `ContentView` via SwiftUI, and
/// hides (rather than closes) on the red button so the app keeps running in the
/// menu bar.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static var shared: MainWindowController?

    let window: NSWindow

    override init() {
        let root = ContentView()
            .environmentObject(AppState.shared)
            .environmentObject(AppState.shared.config)
            .environmentObject(AppState.shared.loc)
            .environmentObject(SecureInputMonitor.shared)
        let hosting = NSHostingController(rootView: root)

        window = NSWindow(contentViewController: hosting)
        // Keep the title visible (do NOT set titleVisibility = .hidden): in the unified
        // toolbar the title is what pushes the page's toolbar items to the trailing
        // edge. With it hidden, the items sat on the left on first open, and jumped
        // right only after SwiftUI rebuilt the toolbar (style switch, button click).
        // Start with the first page's name; each page's navigationTitle takes over.
        window.title = AppState.shared.loc.t("nav.mappings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        // Wide enough for the Mappings keyboard style to show a full Magic
        // Keyboard without scaling down or crowding the sidebar; other pages just
        // get more breathing room.
        window.setContentSize(NSSize(width: 990, height: 640))
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
