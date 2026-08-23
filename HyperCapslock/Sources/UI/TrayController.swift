import AppKit
import Combine

/// Menu-bar status item + menu: a disabled status line, start/stop toggle,
/// check-for-updates, more-apps, open-window, quit. Template
/// icon reflects running/paused; text is fully localized and refreshes on
/// status or locale changes.
///
/// It also surfaces macOS **Secure Input** (see `SecureInput`): while that is on
/// the app is deaf through no fault of its own, so the icon gets a warning badge
/// and the menu gains a row at the top explaining it — otherwise the user just
/// sees every mapping stop working and blames the app.
@MainActor
final class TrayController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()

    private let secureInputItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let secureInputSeparator = NSMenuItem.separator()
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

        // DispatchQueue.main, not RunLoop.main: the main queue drains in every
        // run-loop mode, so a change that lands while the menu is open still
        // reaches the icon. (The hop itself is load-bearing either way —
        // @Published fires in willSet, so refresh() must run after the property
        // has actually been updated.)
        SecureInputMonitor.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        // Informational: there is nothing we can do about secure input from
        // here, so the row explains rather than offers a (fake) fix.
        secureInputItem.isEnabled = false
        for item in [statusLine, toggleItem, checkUpdateItem, moreAppsItem] { item.target = self }
        // Kept at the very top so a blocked app is the first thing the menu says.
        menu.addItem(secureInputItem)
        menu.addItem(secureInputSeparator)
        menu.addItem(statusLine)
        menu.addItem(toggleItem)
        menu.addItem(checkUpdateItem)
        menu.addItem(moreAppsItem)
        menu.addItem(.separator())
        openItem.target = self
        quitItem.target = self
        menu.addItem(openItem)
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityIdentifier("tray.status_item")
        secureInputItem.setAccessibilityIdentifier("tray.secure_input_warning")
        toggleItem.setAccessibilityIdentifier("tray.toggle_service")
        openItem.setAccessibilityIdentifier("tray.open_window")
        quitItem.setAccessibilityIdentifier("tray.quit")
    }

    private func refresh() {
        let paused = AppState.shared.isPaused
        let secureInputActive = SecureInputMonitor.shared.isActive
        let t = LocalizationManager.shared.t

        statusLine.title = paused ? t("status.label", [:]) + ": " + t("status.paused", [:])
                                  : t("status.label", [:]) + ": " + t("status.running", [:])
        toggleItem.title = paused ? t("status.resume", [:]) : t("status.pause", [:])
        checkUpdateItem.title = t("update.check", [:])
        moreAppsItem.title = t("tray.more_apps", [:])
        openItem.title = t("tray.open", [:])
        quitItem.title = t("tray.quit", [:])

        secureInputItem.isHidden = !secureInputActive
        secureInputSeparator.isHidden = !secureInputActive
        if secureInputActive { secureInputItem.attributedTitle = secureInputTitle() }

        statusItem.button?.image = trayImage(paused: paused, warning: secureInputActive)
    }

    /// Sample Secure Input synchronously as the menu opens. The 2s poll can
    /// still be up to one interval behind at this instant, and the menu is the
    /// one surface a user consults precisely *because* their mappings just died
    /// — it must never be the stale one.
    func menuWillOpen(_ menu: NSMenu) {
        SecureInputMonitor.shared.refresh()
        refresh()
    }

    // MARK: - Secure Input presentation

    /// Two lines: what is wrong, then what to look for. It names the *kind* of
    /// prompt rather than an app — see `SecureInput` on why the system's holder
    /// pid can't be trusted to identify one.
    private func secureInputTitle() -> NSAttributedString {
        let t = LocalizationManager.shared.t
        let detail = t("secure_input.tray_detail", [:])
        let title = NSMutableAttributedString(
            string: "⚠︎ " + t("secure_input.tray_title", [:]),
            attributes: [.font: NSFont.menuFont(ofSize: 0),
                         .foregroundColor: NSColor.systemOrange])
        title.append(NSAttributedString(
            string: "\n" + detail,
            attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        return title
    }

    /// The menu-bar glyph, with a warning badge while Secure Input is blocking
    /// us. The canvas widens rather than the badge sitting on top of the arrow:
    /// punching the badge into an 18pt glyph eats the arrow's right wing and the
    /// result reads as a broken icon, not a badged one. It still overlaps by a
    /// hair (with a cleared ring) so it reads as one badged icon rather than two
    /// separate status items.
    private func trayImage(paused: Bool, warning: Bool) -> NSImage? {
        guard let base = NSImage(named: paused ? "TrayPaused" : "TrayRunning") else { return nil }
        let glyph: CGFloat = 18
        guard warning else {
            base.isTemplate = true
            base.size = NSSize(width: glyph, height: glyph)
            return base
        }
        let badgeSide: CGFloat = 8.5
        let overlap: CGFloat = 1.5
        let size = NSSize(width: glyph - overlap + badgeSide, height: glyph)
        let badgeRect = NSRect(x: size.width - badgeSide, y: 0, width: badgeSide, height: badgeSide)
        let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: badgeSide, weight: .bold))
        let badged = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: 0, width: glyph, height: glyph))
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -0.8, dy: -0.8)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge?.draw(in: badgeRect)
            return true
        }
        badged.isTemplate = true
        return badged
    }

    @objc private func toggleService() { AppState.shared.togglePause() }
    @objc private func checkForUpdates() { UpdaterManager.shared.checkForUpdates() }
    @objc private func openMoreApps() {
        if let url = URL(string: "https://xueshi.dev") { NSWorkspace.shared.open(url) }
    }
    @objc private func openWindow() { MainWindowController.shared?.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
