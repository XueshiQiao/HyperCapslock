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
    /// True while the visible HUD is showing with no auto-hide timer (an
    /// `.untilDismissed` HUD). `dismiss()` only hides when this is set, so a
    /// timed HUD is never cut short by a stray dismiss call.
    private var awaitingDismiss = false

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
            self?.dismiss()
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

        // Any show cancels a pending auto-hide. An `.untilDismissed` HUD then
        // schedules NO timer and stays up until `dismiss()`; a `.timed` HUD keeps
        // the auto-hide.
        hideWork?.cancel()
        hideWork = nil
        switch payload.duration {
        case .untilDismissed:
            awaitingDismiss = true
            FileLog.shared.info("HUD shown (until-dismissed, no timer) at \(panel.frame.origin) (trigger=\(payload.trigger))")
        case .timed(let ms):
            awaitingDismiss = false
            let hold = ms > 0 ? ms : 1350
            FileLog.shared.info("HUD shown on screen at \(panel.frame.origin) for \(hold)ms (trigger=\(payload.trigger))")
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(hold) / 1000.0, execute: work)
        }
    }

    /// Order the panel out and clear its content. Shared by the timed auto-hide
    /// and the until-dismissed `dismiss()`.
    private func hide() {
        panel?.orderOut(nil)
        model.payload = nil
    }

    /// Hide the HUD only if the visible one is `.untilDismissed`. Invoked on the
    /// main thread via `HudCenter.onDismiss`. A timed HUD (awaitingDismiss ==
    /// false) is left alone so a stray dismiss can't cut it short.
    private func dismiss() {
        guard awaitingDismiss else { return }
        awaitingDismiss = false
        hide()
        FileLog.shared.info("HUD until-dismissed hidden.")
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
