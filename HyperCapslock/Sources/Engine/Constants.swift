import Foundation
import CoreGraphics

enum EngineConstants {
    /// Max hold time for a Caps press to count as a "tap" (vs. a hold-for-chord).
    static let capsTapMaxMs: UInt64 = 200
    /// Default double-tap window (ms). The live value is user-configurable and
    /// held in `EngineState.doubleTapWindowMs`; this is the fallback/default and
    /// the seed for a config with no `double_tap_window_ms` key.
    static let doubleTapWindowDefaultMs: UInt64 = 200
    /// User-adjustable bounds for the double-tap window (ms) — the slider range
    /// and the clamp applied on load / on set.
    static let doubleTapWindowMinMs: UInt64 = 100
    static let doubleTapWindowMaxMs: UInt64 = 500

    /// Clamp a millisecond value into the allowed double-tap window range.
    static func clampDoubleTapWindow(_ ms: Int) -> Int {
        min(max(ms, Int(doubleTapWindowMinMs)), Int(doubleTapWindowMaxMs))
    }
}

/// The subset of `flags` that are real modifier flags (Shift/Ctrl/Alt/Cmd/Fn).
@inline(__always)
func activeModifierFlags(_ flags: CGEventFlags) -> CGEventFlags {
    flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
}
