import Foundation

struct HudPayload: Equatable {
    var trigger: String
    var combo: String
    var caption: String
    var duration: Int
    /// When true the HUD stays on screen with NO auto-hide timer until an
    /// explicit `dismiss()` — used by the hold-modifier action so the HUD is
    /// visible for exactly as long as the modifier is physically held.
    var sticky: Bool = false
}

/// Routes HUD show requests from the event-tap thread to the overlay window on
/// the main thread. Port of `emit_hud`: no-op unless the user enabled the HUD,
/// and throttled per identical (trigger,combo,caption) so a held nav key
/// autorepeating doesn't flood the UI; a *different* mapping shows immediately.
final class HudCenter {
    static let shared = HudCenter()

    private static let throttleMs: UInt64 = 120

    private let lock = NSLock()
    private var enabled = false
    private var durationMs = 1350
    private var lastEmitMs: UInt64 = 0
    private var lastKey = ""

    /// Set by `HudController` on the main thread; invoked on the main thread.
    var onShow: ((HudPayload) -> Void)?
    /// Set by `HudController`; invoked on the main thread to hide a sticky HUD.
    var onDismiss: (() -> Void)?

    func updateSettings(enabled: Bool, durationMs: Int) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        self.durationMs = durationMs
    }

    func emit(trigger: String, combo: String, caption: String, sticky: Bool = false) {
        var skipReason: String?
        let payload: HudPayload? = {
            lock.lock(); defer { lock.unlock() }
            guard enabled else { skipReason = "HUD disabled (show_hud=false)"; return nil }
            let key = "\(trigger)\u{1}\(combo)\u{1}\(caption)"
            let now = nowMillis()
            // Sticky (hold-modifier) emits bypass the throttle: they fire once per
            // physical press, never autorepeat, and re-pressing the same chord
            // within the throttle window must still re-show the HUD.
            if !sticky && key == lastKey && now &- lastEmitMs < Self.throttleMs {
                skipReason = "throttled (same key within \(Self.throttleMs)ms)"
                return nil
            }
            lastKey = key
            lastEmitMs = now
            return HudPayload(trigger: trigger, combo: combo, caption: caption, duration: durationMs, sticky: sticky)
        }()
        guard let payload else {
            FileLog.shared.info("HUD emit SKIPPED: \(skipReason ?? "unknown") [trigger=\(trigger) combo=\(combo)]")
            return
        }
        let hasHandler = (onShow != nil)
        FileLog.shared.info("HUD emit → dispatch to main (onShow set=\(hasHandler)) trigger=\(trigger) combo=\(combo) caption=\(caption) dur=\(payload.duration) sticky=\(payload.sticky)")
        DispatchQueue.main.async { [weak self] in
            self?.onShow?(payload)
        }
    }

    /// Hide a currently-showing sticky HUD. Called when the hold-modifier is
    /// released (from `ActionExecutor.execute` on the `.modifierKey` key-up,
    /// which every release path funnels through). A no-op if the visible HUD
    /// isn't sticky — the controller guards that — so a normal transient HUD
    /// that happens to be on screen lives out its timer untouched.
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            self?.onDismiss?()
        }
    }
}
