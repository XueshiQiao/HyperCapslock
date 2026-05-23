import Foundation
import os

/// Lock-free-ish runtime state shared between the CGEventTap callback (runs on
/// its own CFRunLoop thread), the deferred-toggle timer threads, and the UI.
/// Mirrors the `AtomicBool`/`AtomicU64` globals in the Rust original.
/// `OSAllocatedUnfairLock` (macOS 13+) gives cheap, correct mutual exclusion in
/// the hot keypress path.
final class EngineState {
    static let shared = EngineState()

    private let _isPaused = OSAllocatedUnfairLock(initialState: false)
    private let _capsDown = OSAllocatedUnfairLock(initialState: false)
    private let _capsPressedAtMs = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private let _didRemap = OSAllocatedUnfairLock(initialState: false)
    /// Timestamp of the last short tap pending a possible 2nd tap (cancellation
    /// token for the deferred CapsLock toggle). 0 = none pending.
    private let _lastTapAtMs = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    var isPaused: Bool {
        get { _isPaused.withLock { $0 } }
        set { _isPaused.withLock { $0 = newValue } }
    }

    var capsDown: Bool {
        get { _capsDown.withLock { $0 } }
        set { _capsDown.withLock { $0 = newValue } }
    }

    /// Set capsDown and return the previous value (atomic swap).
    func swapCapsDown(_ newValue: Bool) -> Bool {
        _capsDown.withLock { old in let prev = old; old = newValue; return prev }
    }

    var capsPressedAtMs: UInt64 {
        get { _capsPressedAtMs.withLock { $0 } }
        set { _capsPressedAtMs.withLock { $0 = newValue } }
    }

    func swapCapsPressedAtMs(_ newValue: UInt64) -> UInt64 {
        _capsPressedAtMs.withLock { old in let prev = old; old = newValue; return prev }
    }

    var didRemap: Bool {
        get { _didRemap.withLock { $0 } }
        set { _didRemap.withLock { $0 = newValue } }
    }

    /// Atomic swap of the pending-tap token. Returns the previous value.
    func swapLastTapAtMs(_ newValue: UInt64) -> UInt64 {
        _lastTapAtMs.withLock { old in let prev = old; old = newValue; return prev }
    }

    func storeLastTapAtMs(_ value: UInt64) {
        _lastTapAtMs.withLock { $0 = value }
    }

    /// Compare-and-clear: if the token still equals `expected`, set it to 0 and
    /// return true; otherwise leave it and return false. Used by the deferred
    /// timer to avoid firing a toggle that a 2nd tap (or a pre-empting keypress)
    /// already consumed.
    func compareExchangeLastTapAtMs(expected: UInt64, new: UInt64) -> Bool {
        _lastTapAtMs.withLock { cur in
            if cur == expected { cur = new; return true }
            return false
        }
    }
}

@inline(__always)
func nowMillis() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000.0)
}
