import AppKit
import Combine

/// Menu-bar status item + menu: a disabled status line, start/stop toggle,
/// check-for-updates, more-apps, open-window, quit. Template
/// icon reflects running/paused; text is fully localized and refreshes on
/// status or locale changes.
@MainActor
final class TrayController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleService), keyEquivalent: "")
    private let checkUpdateItem = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "")
    private let moreAppsItem = NSMenuItem(title: "", action: #selector(openMoreApps), keyEquivalent: "")
    private let openItem = NSMenuItem(title: "", action: #selector(openWindow), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")

    override init() {
        super.init()
        buildMenu()
        refresh()

        AppState.shared.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        LocalizationManager.shared.$locale
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        for item in [statusLine, toggleItem, checkUpdateItem, moreAppsItem] { item.target = self }
        menu.addItem(statusLine)
        menu.addItem(toggleItem)
        menu.addItem(checkUpdateItem)
        menu.addItem(moreAppsItem)
        menu.addItem(.separator())
        openItem.target = self
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func refresh() {
        let paused = AppState.shared.isPaused
        let t = LocalizationManager.shared.t

        statusLine.title = paused ? t("status.label", [:]) + ": " + t("status.paused", [:])
                                  : t("status.label", [:]) + ": " + t("status.running", [:])
        toggleItem.title = paused ? t("status.resume", [:]) : t("status.pause", [:])
        checkUpdateItem.title = t("update.check", [:])
        moreAppsItem.title = t("tray.more_apps", [:])
        openItem.title = t("tray.open", [:])
        quitItem.title = t("tray.quit", [:])

        let imageName = paused ? "TrayPaused" : "TrayRunning"
        if let image = NSImage(named: imageName) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = image
        }
    }

    @objc private func toggleService() { AppState.shared.togglePause() }
    @objc private func checkForUpdates() { UpdaterManager.shared.checkForUpdates() }
    @objc private func openMoreApps() {
        if let url = URL(string: "https://xueshi.dev") { NSWorkspace.shared.open(url) }
    }
    @objc private func openWindow() { MainWindowController.shared?.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
