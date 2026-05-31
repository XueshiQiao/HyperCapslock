import Foundation

/// The ONLY file in HyperCapslock aware that AnyDrag exists. A `CapsHoldCenter`
/// plugin that bridges the in-process CapsLock-hold lifecycle to AnyDrag:
///
///   • broadcasts `capsHoldBegan` / `capsHoldEnded` outward, and
///   • answers AnyDrag's liveness pings with a pong, so AnyDrag can disarm if we
///     are killed mid-hold.
///
/// Purely reactive on the ping channel — it NEVER initiates a ping. Its lifetime
/// equals the user's AnyDrag setting: created + added to the hub when enabled,
/// removed + released when disabled, which also tears down the ping responder.
///
/// The four wire names below are a permanent cross-app contract; AnyDrag matches
/// them byte-for-byte. They live here and nowhere else — the engine and the hub
/// stay completely AnyDrag-agnostic.
final class AnyDragCapsHoldBridge: CapsHoldObserver {
    private enum Wire {
        static let began = Notification.Name("me.xueshi.hypercapslock.capsHoldBegan")
        static let ended = Notification.Name("me.xueshi.hypercapslock.capsHoldEnded")
        static let ping  = Notification.Name("me.xueshi.hypercapslock.capsHoldPing")
        static let pong  = Notification.Name("me.xueshi.hypercapslock.capsHoldPong")
    }

    private var pingObserver: NSObjectProtocol?

    init() {
        pingObserver = DistributedNotificationCenter.default().addObserver(
            forName: Wire.ping, object: nil, queue: .main
        ) { [weak self] _ in self?.post(Wire.pong) }
        FileLog.shared.info("AnyDrag bridge installed (broadcasting CapsLock hold; answering pings).")
    }

    deinit {
        if let o = pingObserver { DistributedNotificationCenter.default().removeObserver(o) }
        FileLog.shared.info("AnyDrag bridge uninstalled.")
    }

    // MARK: CapsHoldObserver (fired synchronously on the lifecycle's thread)

    func capsHoldBegan() { post(Wire.began) }
    func capsHoldEnded() { post(Wire.ended) }

    private func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
