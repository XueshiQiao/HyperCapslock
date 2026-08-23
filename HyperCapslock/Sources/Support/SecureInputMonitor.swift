import AppKit
import Combine
import Foundation

/// Watches `SecureInput` and publishes it, so the menu-bar icon and the
/// Settings page can tell the user "macOS is blocking your mappings" instead of
/// leaving them to conclude the app broke.
///
/// macOS ships no notification for a secure-input change, so polling is the only
/// option (the same thing every other event-tap app does). One CGS call every
/// couple of seconds is far below the noise floor, and the interval is short
/// enough that the icon reacts while the user is still looking at the password
/// box that caused it.
@MainActor
final class SecureInputMonitor: ObservableObject {
  static let shared = SecureInputMonitor()

  @Published private(set) var isActive = false

  private static let pollInterval: TimeInterval = 2.0
  private var timer: Timer?

  private init() {}

  /// Begin polling. No-op under -uitest: the tests must not react to whatever
  /// password prompt happens to be open on the machine running them.
  func start() {
    guard !AppEnvironment.isUITest, timer == nil else { return }
    refresh()
    let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    t.tolerance = 0.5
    // .common, NOT the default mode Timer.scheduledTimer would use: AppKit puts
    // the run loop in event-tracking mode while a menu is open, which would
    // freeze polling for exactly as long as the tray menu is on screen — i.e.
    // while the user is staring at the menu that is supposed to explain the
    // problem. Timer(…) + RunLoop.add is the only way to choose the mode.
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  /// Sample the current state and publish it if it changed.
  ///
  /// Guarded for -uitest here and not only in `start()`: this is also reachable
  /// from the Settings "Refresh" button, and a test clicking it would otherwise
  /// pull in whatever Secure Input state the host machine happens to be in,
  /// making the settings row, footer and tray icon nondeterministic.
  func refresh() {
    guard !AppEnvironment.isUITest else { return }
    let active = SecureInput.isEnabled
    guard active != isActive else { return }
    isActive = active

    if active {
      // The frontmost app is only a hint — it is often, but by no means always,
      // the one that raised the password prompt (see SecureInput's note on why
      // the system's own pid field can't be trusted). Logged for diagnosis, and
      // deliberately NOT shown in the UI, where a wrong name would misdirect.
      let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
      FileLog.shared.warn("⚠️ macOS Secure Input turned ON (frontmost app at the time: \(front) — a hint, not proof of who enabled it). macOS is withholding key events from our event tap: ALL CapsLock/F18 mappings are dead until it turns off, while modifier double-taps keep firing. Not fixable from here; the open password prompt must be dismissed.")
    } else {
      FileLog.shared.info("macOS Secure Input turned OFF — key events reach the tap again; mappings work.")
    }
  }
}
