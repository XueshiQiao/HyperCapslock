import Foundation

struct HudPayload: Equatable {
    var trigger: String
    var combo: String
    var caption: String
    var duration: Int
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

    func updateSettings(enabled: Bool, durationMs: Int) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        self.durationMs = durationMs
    }

    func emit(trigger: String, combo: String, caption: String) {
        let payload: HudPayload? = {
            lock.lock(); defer { lock.unlock() }
            guard enabled else { return nil }
            let key = "\(trigger)\u{1}\(combo)\u{1}\(caption)"
            let now = nowMillis()
            if key == lastKey && now &- lastEmitMs < Self.throttleMs { return nil }
            lastKey = key
            lastEmitMs = now
            return HudPayload(trigger: trigger, combo: combo, caption: caption, duration: durationMs)
        }()
        guard let payload else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onShow?(payload)
        }
    }
}
