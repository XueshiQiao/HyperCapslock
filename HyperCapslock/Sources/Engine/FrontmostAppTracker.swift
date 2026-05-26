import AppKit
import os

/// Snapshot of the frontmost application, as seen at activation time.
struct FrontmostApp: Equatable {
  var name: String
  var bundleID: String?
}

/// Tracks the frontmost application's bundle id behind a lock so the
/// `CGEventTap` callback thread can read it cheaply without ever touching
/// AppKit (which is unsafe off the main thread and could stall key input).
///
/// The cache is written on the main thread from `NSWorkspace`
/// activation notifications — the same producer/consumer shape as
/// `EngineState`: live runtime state behind an `OSAllocatedUnfairLock`,
/// driven from one side and read from the hot path on the other.
///
/// This is the production-shape tracker the per-app scope feature will read;
/// the diagnostic `FrontmostAppHud` is the only current consumer.
final class FrontmostAppTracker {
  static let shared = FrontmostAppTracker()

  private let _bundleID = OSAllocatedUnfairLock<String?>(initialState: nil)
  private var observers: [NSObjectProtocol] = []

  /// Diagnostic hook, invoked on the main thread whenever the frontmost app
  /// actually changes (deduped by bundle id). Single-slot on purpose — the
  /// production hot path reads `currentBundleID()`, not this callback.
  var onChange: ((FrontmostApp) -> Void)?

  /// Hot-path safe: read the cached frontmost bundle id from any thread.
  func currentBundleID() -> String? {
    _bundleID.withLock { $0 }
  }

  @MainActor
  func start() {
    guard observers.isEmpty else { return }  // idempotent: never double-register
    let nc = NSWorkspace.shared.notificationCenter

    // Register observers BEFORE seeding so a change racing into startup isn't missed.
    observers.append(nc.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      else { return }
      self?.update(app)
    })

    // Cases that change the frontmost app WITHOUT a didActivate: the frontmost
    // app quitting or hiding (focus jumps elsewhere), and Space/fullscreen
    // switches. No app object is delivered, so re-read frontmostApplication
    // once focus has settled.
    for name in [NSWorkspace.didTerminateApplicationNotification,
                 NSWorkspace.didHideApplicationNotification,
                 NSWorkspace.activeSpaceDidChangeNotification] {
      observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.reseedSoon()
      })
    }

    reseed()  // initial seed
    FileLog.shared.info("FrontmostAppTracker started.")
  }

  /// Re-read the frontmost app after a brief settle (focus transfer lags the
  /// terminate/hide notifications).
  private func reseedSoon() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.reseed() }
  }

  private func reseed() {
    if let app = NSWorkspace.shared.frontmostApplication { update(app) }
  }

  /// Update the cache and notify, at the first moment we learn of a change.
  /// Deduped by bundle id so re-activating the same app doesn't re-fire.
  private func update(_ app: NSRunningApplication) {
    let bundleID = app.bundleIdentifier
    // Ignore our own transient activation during a Switching-Focus input-source
    // round-trip, so per-app mapping resolution keeps pointing at the user's app.
    if bundleID == Bundle.main.bundleIdentifier, InputSourceFix.isSuppressingSelfActivation {
      FileLog.shared.info("FrontmostAppTracker: ignoring self-activation during input-source focus round-trip.")
      return
    }
    let changed = _bundleID.withLock { current -> Bool in
      if current == bundleID { return false }
      current = bundleID
      return true
    }
    guard changed else { return }
    let info = FrontmostApp(name: app.localizedName ?? "(unknown)", bundleID: bundleID)
    FileLog.shared.info("Frontmost app → \(info.name) [\(bundleID ?? "no bundle id")]")
    onChange?(info)
  }
}
