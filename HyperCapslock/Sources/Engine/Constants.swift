import Foundation
import CoreGraphics

enum EngineConstants {
    /// Max hold time for a Caps press to count as a "tap" (vs. a hold-for-chord).
    static let capsTapMaxMs: UInt64 = 200
    /// Window within which a 2nd tap counts as a double-tap.
    static let doubleTapWindowMs: UInt64 = 200
}

/// The subset of `flags` that are real modifier flags (Shift/Ctrl/Alt/Cmd/Fn).
@inline(__always)
func activeModifierFlags(_ flags: CGEventFlags) -> CGEventFlags {
    flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
}
