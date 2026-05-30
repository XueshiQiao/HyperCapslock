import AppKit
import SwiftUI

@MainActor
final class HudViewModel: ObservableObject {
    @Published var payload: HudPayload?
}

/// Transparent, click-through, always-on-top overlay panel for the mapping HUD.
/// Created once, repositioned bottom-center of the active screen on each show,
/// and auto-hidden after the configured duration. Wires `HudCenter.onShow`.
@MainActor
final class HudController {
    static let shared = HudController()

    private var panel: NSPanel?
    private let model = HudViewModel()
    private var hideWork: DispatchWorkItem?
    /// True while the visible HUD is a sticky (hold-modifier) one with no
    /// auto-hide timer. `dismissSticky()` only hides when this is set, so a
    /// normal transient HUD is never cut short by a stray release.
    private var currentIsSticky = false

    private static let windowSize = NSSize(width: 760, height: 240)
    private static let bottomOffset: CGFloat = 160

    func install() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HudView(model: model))
        self.panel = panel

        HudCenter.shared.onShow = { [weak self] payload in
            self?.show(payload)
        }
        HudCenter.shared.onDismiss = { [weak self] in
            self?.dismissSticky()
        }
        FileLog.shared.info("HUD panel installed and onShow/onDismiss handlers wired.")
    }

    private func show(_ payload: HudPayload) {
        guard let panel else {
            FileLog.shared.warn("HUD show called but panel is nil (install() not run?)")
            return
        }
        model.payload = payload
        reposition()
        panel.orderFrontRegardless()

        // Any show cancels a pending auto-hide. A sticky HUD (hold-modifier) then
        // schedules NO timer and stays up until dismissSticky() fires on release;
        // a transient HUD keeps the timed auto-hide.
        hideWork?.cancel()
        hideWork = nil
        currentIsSticky = payload.sticky
        if payload.sticky {
            FileLog.shared.info("HUD shown (sticky, no timer) at \(panel.frame.origin) (trigger=\(payload.trigger))")
            return
        }
        FileLog.shared.info("HUD shown on screen at \(panel.frame.origin) for \(payload.duration)ms (trigger=\(payload.trigger))")
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        let hold = payload.duration > 0 ? payload.duration : 1350
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(hold) / 1000.0, execute: work)
    }

    /// Order the panel out and clear its content. Shared by the transient
    /// auto-hide timer and the sticky dismiss.
    private func hide() {
        panel?.orderOut(nil)
        model.payload = nil
    }

    /// Hide the HUD only if the visible one is sticky (hold-modifier held).
    /// Invoked on the main thread via `HudCenter.onDismiss` when the modifier is
    /// released. A transient HUD (currentIsSticky == false) is left alone so a
    /// stray release can't cut it short.
    private func dismissSticky() {
        guard currentIsSticky else { return }
        currentIsSticky = false
        hide()
        FileLog.shared.info("HUD sticky dismissed (hold-modifier released).")
    }

    private func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let size = Self.windowSize
        let x = frame.minX + (frame.width - size.width) / 2
        let y = frame.minY + Self.bottomOffset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}
