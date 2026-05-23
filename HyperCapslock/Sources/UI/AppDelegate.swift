import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: TrayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Order matters: state/config first, then engine, then UI surfaces.
        AppState.shared.bootstrap()
        KeyboardHook.shared.start()
        HudController.shared.install()
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
}
