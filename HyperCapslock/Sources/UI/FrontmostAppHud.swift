import AppKit
import SwiftUI

@MainActor
final class FrontmostAppHudModel: ObservableObject {
  @Published var app: FrontmostApp?
}

/// TEMPORARY diagnostic overlay. Shows the current frontmost app's name +
/// bundle id in the bottom-right of the active screen (the one under the mouse,
/// matching `HudController`'s convention), held 3s and replaced immediately on
/// each change. Used to eyeball frontmost-app detection accuracy before
/// building per-app scoped mappings. Safe to delete once validated.
@MainActor
final class FrontmostAppHud {
  static let shared = FrontmostAppHud()

  /// UserDefaults-backed enable flag. Debug-only diagnostic, so it lives in
  /// UserDefaults (like `hc-locale`) rather than the shipped `app_config.yml`.
  /// Off by default — flip it from Settings ▸ Debug when you want to debug.
  static let defaultsKey = "hc-debug-frontmost-hud"

  private var panel: NSPanel?
  private let model = FrontmostAppHudModel()
  private var hideWork: DispatchWorkItem?

  private static let windowSize = NSSize(width: 360, height: 76)
  private static let margin: CGFloat = 24
  private static let holdSeconds: Double = 3

  /// Read live so the Settings toggle (which writes the same key) takes effect
  /// without any extra wiring.
  private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.defaultsKey) }

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
    panel.contentView = NSHostingView(rootView: FrontmostAppHudView(model: model))
    self.panel = panel

    FrontmostAppTracker.shared.onChange = { [weak self] app in
      self?.show(app)
    }
    FileLog.shared.info("FrontmostAppHud installed (diagnostic).")
  }

  /// Hide immediately (e.g. when the user toggles the diagnostic off).
  func hideNow() {
    hideWork?.cancel()
    panel?.orderOut(nil)
    model.app = nil
  }

  private func show(_ app: FrontmostApp) {
    guard isEnabled, let panel else { return }
    model.app = app
    reposition()
    panel.orderFrontRegardless()

    hideWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.panel?.orderOut(nil)
      self?.model.app = nil
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds, execute: work)
  }

  private func reposition() {
    guard let panel else { return }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    guard let vf = screen?.visibleFrame else { return }
    let size = Self.windowSize
    let x = vf.maxX - size.width - Self.margin
    let y = vf.minY + Self.margin
    panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
  }
}

private struct FrontmostAppHudView: View {
  @ObservedObject var model: FrontmostAppHudModel

  var body: some View {
    if let app = model.app {
      VStack(alignment: .leading, spacing: 3) {
        Text(app.name)
          .font(.system(size: 16, weight: .semibold))
          .lineLimit(1)
        Text(app.bundleID ?? "(no bundle id)")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(Color.primary.opacity(0.10), lineWidth: 1))
      .padding(8)
    }
  }
}
