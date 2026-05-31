import Foundation
import os

/// A listener on the CapsLock-hold lifecycle. Implementations are plugins; the
/// engine neither knows nor cares what they do. Methods are called SYNCHRONOUSLY
/// on whatever thread fired the lifecycle event (usually the tap thread).
protocol CapsHoldObserver: AnyObject {
    func capsHoldBegan()
    func capsHoldEnded()
}

/// In-process event hub for the CapsLock-hold lifecycle. Observer membership IS
/// the on/off switch — there is no separate "enabled" flag. Thread-safe:
/// observers (un)register from the main thread; the lifecycle fires from the tap
/// thread. Observers are held WEAKLY, so their owner controls lifetime.
///
/// `isHeld` mirrors the live hold state so that adding an observer mid-hold
/// immediately syncs it with `capsHoldBegan()` (and removing mid-hold fires
/// `capsHoldEnded()`) — no asymmetry if the user flips a plugin on/off while
/// CapsLock is down.
final class CapsHoldCenter {
    static let shared = CapsHoldCenter()

    private struct WeakObserver {
        let id: ObjectIdentifier
        weak var ref: CapsHoldObserver?
    }
    private struct State {
        var observers: [WeakObserver] = []
        var isHeld = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Register a plugin. If a hold is already active, the plugin is immediately
    /// synced with `capsHoldBegan()` so it doesn't miss the in-progress hold.
    func add(_ observer: CapsHoldObserver) {
        let id = ObjectIdentifier(observer)
        let syncBegan: Bool = state.withLock { st in
            st.observers.removeAll { $0.id == id || $0.ref == nil }
            st.observers.append(WeakObserver(id: id, ref: observer))
            return st.isHeld
        }
        if syncBegan { observer.capsHoldBegan() }
    }

    /// Unregister a plugin. If a hold is active, the plugin is sent
    /// `capsHoldEnded()` first so it can unwind cleanly.
    func remove(_ observer: CapsHoldObserver) {
        let id = ObjectIdentifier(observer)
        let syncEnded: Bool = state.withLock { st in
            let present = st.observers.contains { $0.id == id }
            st.observers.removeAll { $0.id == id || $0.ref == nil }
            return present && st.isHeld
        }
        if syncEnded { observer.capsHoldEnded() }
    }

    /// Lifecycle: a hold began. Snapshots live observers under the lock, then
    /// fans out OFF the lock (so an observer adding/removing can't deadlock).
    func notifyBegan() { fanOut(isHeld: true) { $0.capsHoldBegan() } }

    /// Lifecycle: a hold ended.
    func notifyEnded() { fanOut(isHeld: false) { $0.capsHoldEnded() } }

    private func fanOut(isHeld: Bool, _ body: (CapsHoldObserver) -> Void) {
        let live: [CapsHoldObserver] = state.withLock { st in
            st.isHeld = isHeld
            st.observers.removeAll { $0.ref == nil }
            return st.observers.compactMap { $0.ref }
        }
        live.forEach(body)
    }
}

// MARK: - Lifecycle hooks (the engine's only contact with the hub)

/// A CapsLock hold began. Owns the fresh `capsDown` transition + bookkeeping,
/// then fires the lifecycle event. Called only on the F18 key-down edge; the
/// guard makes repeated key-down (auto-repeat) a no-op.
func beginCapsHold() {
    guard !EngineState.shared.swapCapsDown(true) else { return }
    EngineState.shared.capsPressedAtMs = nowMillis()
    EngineState.shared.didRemap = false
    FileLog.shared.info("Caps(F18) down.")
    CapsHoldCenter.shared.notifyBegan()
}

/// A CapsLock hold ended. Owns the `capsDown` → false transition, fires the
/// lifecycle event, and returns whether a hold was actually active (key-up needs
/// it for tap classification). Idempotent: a second call returns false and fires
/// nothing. Called from the normal F18 key-up AND every abnormal exit
/// (pause / terminate / tap-disabled).
@discardableResult
func endCapsHold() -> Bool {
    let wasDown = EngineState.shared.swapCapsDown(false)
    if wasDown { CapsHoldCenter.shared.notifyEnded() }
    return wasDown
}
