import Foundation

/// How long a shown HUD stays up. The HUD's own vocabulary — it has no notion of
/// *why* a caller wants persistent display, only of the two stay-up behaviors it
/// must implement.
enum HudDuration: Equatable {
    /// Auto-hide after the given milliseconds (≤0 falls back to a default).
    case timed(ms: Int)
    /// Stay up with no timer until the caller invokes `HudCenter.dismiss()`.
    case untilDismissed

    var isUntilDismissed: Bool { self == .untilDismissed }
}

struct HudPayload: Equatable {
    var trigger: String
    var combo: String
    var caption: String
    var duration: HudDuration
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
    /// Set by `HudController`; invoked on the main thread to hide an
    /// `.untilDismissed` HUD.
    var onDismiss: (() -> Void)?

    func updateSettings(enabled: Bool, durationMs: Int) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        self.durationMs = durationMs
    }

    /// Show the HUD. `duration` defaults to `.timed(ms: 0)`, which resolves to the
    /// user-configured auto-hide time; pass `.untilDismissed` for a HUD that
    /// stays until `dismiss()`.
    func emit(trigger: String, combo: String, caption: String, duration: HudDuration = .timed(ms: 0)) {
        var skipReason: String?
        let payload: HudPayload? = {
            lock.lock(); defer { lock.unlock() }
            guard enabled else { skipReason = "HUD disabled (show_hud=false)"; return nil }
            let key = "\(trigger)\u{1}\(combo)\u{1}\(caption)"
            let now = nowMillis()
            // An until-dismissed HUD bypasses the throttle: it fires once per
            // physical press (never autorepeat), and re-triggering the same key
            // within the throttle window must still re-show it.
            if !duration.isUntilDismissed && key == lastKey && now &- lastEmitMs < Self.throttleMs {
                skipReason = "throttled (same key within \(Self.throttleMs)ms)"
                return nil
            }
            lastKey = key
            lastEmitMs = now
            // Resolve a 0/negative timed request to the configured default.
            let resolved: HudDuration
            switch duration {
            case .timed(let ms): resolved = .timed(ms: ms > 0 ? ms : durationMs)
            case .untilDismissed: resolved = .untilDismissed
            }
            return HudPayload(trigger: trigger, combo: combo, caption: caption, duration: resolved)
        }()
        guard let payload else {
            FileLog.shared.info("HUD emit SKIPPED: \(skipReason ?? "unknown") [trigger=\(trigger) combo=\(combo)]")
            return
        }
        let hasHandler = (onShow != nil)
        FileLog.shared.info("HUD emit → dispatch to main (onShow set=\(hasHandler)) trigger=\(trigger) combo=\(combo) caption=\(caption) dur=\(payload.duration)")
        DispatchQueue.main.async { [weak self] in
            self?.onShow?(payload)
        }
    }

    /// Hide a currently-showing `.untilDismissed` HUD. The controller no-ops this
    /// for a timed HUD, so a normal timed HUD on screen lives out its timer
    /// untouched. (The caller decides when to dismiss; the HUD doesn't know why.)
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            self?.onDismiss?()
        }
    }
}
