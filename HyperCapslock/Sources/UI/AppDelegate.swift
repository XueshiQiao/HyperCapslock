import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: TrayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A pure-AppKit app (main.swift, no nib) has no main menu, so text fields
        // wouldn't get the standard Cmd-A/C/V/X/Z editing shortcuts. Install one.
        setupMainMenu()
        // Order matters: state/config first, then engine, then UI surfaces.
        AppState.shared.bootstrap()
        // Under -uitest (XCUITest), do NOT install the global keyboard hook /
        // hidutil remap — tests must never grab the host keyboard. Config is
        // already isolated to a temp dir (see ConfigStore.appDataDir).
        if !AppEnvironment.isUITest {
            KeyboardHook.shared.start()
        }
        HudController.shared.install()
        // Frontmost-app tracker feeds per-app scoped mappings — runs in all builds.
        #if DEBUG
        // Debug overlay (toggle in Settings ▸ Debug) consumes the tracker's
        // onChange; install it before start() so the initial seed is shown.
        if !AppEnvironment.isUITest { FrontmostAppHud.shared.install() }
        #endif
        FrontmostAppTracker.shared.start()
        tray = TrayController()
        MainWindowController.shared = MainWindowController()
        MainWindowController.shared?.show()
        if !AppEnvironment.isUITest {
            _ = UpdaterManager.shared   // start Sparkle's background update checker
        }

        // Re-check permissions when the app regains focus (user may have just
        // granted them in System Settings).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            AppState.shared.refreshPermissions()
        }
    }

    // Dock-icon click / reopen → show the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainWindowController.shared?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist any presses recorded since the last debounced flush before we
        // exit. Safe in -uitest too (no-op: the hook never recorded anything).
        UsageStats.shared.flushNow()
        // -uitest never installed the hook / remap, so there's nothing to tear
        // down — and we must not touch global hidutil state on test exit.
        guard !AppEnvironment.isUITest else { return }
        // Release any chord held at quit (a synthesized push-to-talk modifier
        // would otherwise stay stuck system-wide), then restore CapsLock. Pause
        // first so the tap stops claiming new chords, then drain the release
        // serialized onto the tap thread (waiting) so it can't race the tap's
        // "latch then post-down outside the lock" window.
        EngineState.shared.isPaused = true
        // If CapsLock is held at quit, end the hold synchronously so nothing
        // stays latched after we exit.
        endCapsHold()
        KeyboardHook.shared.releaseHeldChordsSerialized(wait: true)
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
