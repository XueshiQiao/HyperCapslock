import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: TrayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A pure-AppKit app (main.swift, no nib) has no main menu, so text fields
        // wouldn't get the standard Cmd-A/C/V/X/Z editing shortcuts. Install one.
        setupMainMenu()
        // Order matters: state/config first, then engine, then UI surfaces.
        AppState.shared.bootstrap()
        KeyboardHook.shared.start()
        HudController.shared.install()
        #if DEBUG
        // Debug-only diagnostic (gated to debug builds; toggle in Settings ▸ Debug).
        // Install the HUD (wires the callback) before starting the tracker
        // (which seeds + fires). The overlay only appears when the toggle is on.
        FrontmostAppHud.shared.install()
        FrontmostAppTracker.shared.start()
        #endif
        tray = TrayController()
        MainWindowController.shared = MainWindowController()
        MainWindowController.shared?.show()
        _ = UpdaterManager.shared   // start Sparkle's background update checker

        // Re-check permissions when the app regains focus (user may have just
        // granted them in System Settings).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            AppState.shared.refreshPermissions()
        }
    }

    // Dock-icon click / reopen → show the main window (mirrors Tauri Reopen).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainWindowController.shared?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore the original CapsLock mapping so Caps works after we quit.
        KeyboardHook.shared.cleanup()
    }

    /// Standard main menu so NSTextField gets the system editing shortcuts
    /// (Select All / Cut / Copy / Paste / Undo) and Cmd-Q quits.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Hide HyperCapslock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit HyperCapslock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }
}
