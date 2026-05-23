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
    }

    private func show(_ payload: HudPayload) {
        guard let panel else { return }
        model.payload = payload
        reposition()
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.model.payload = nil
        }
        hideWork = work
        let hold = payload.duration > 0 ? payload.duration : 1350
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(hold) / 1000.0, execute: work)
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
