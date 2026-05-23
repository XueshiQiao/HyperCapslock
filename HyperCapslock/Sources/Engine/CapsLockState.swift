import Foundation
import IOKit

/// Direct IOKit control of the CapsLock lock state (the AlphaShift bit / keyboard
/// LED), bypassing HIToolbox. Mirrors `read_caps_lock_state` / `set_caps_lock_state`
/// in the Rust original. Used for the default short-tap CapsLock toggle and the
/// `toggleCapsLock` action.
enum CapsLockState {
    private static let kIOHIDParamConnectType: UInt32 = 1
    private static let kIOHIDCapsLockState: Int32 = 1

    /// Read the current CapsLock lock state. `nil` if any IOKit step fails.
    static func read() -> Bool? {
        guard let connect = openHIDSystem() else { return nil }
        defer { IOServiceClose(connect) }
        var state = false
        let kr = IOHIDGetModifierLockState(connect, kIOHIDCapsLockState, &state)
        return kr == KERN_SUCCESS ? state : nil
    }

    /// Force the CapsLock lock state. Returns `true` only when the bit was
    /// actually flipped — the pre-empt path relies on this to decide whether to
    /// XOR the in-flight key's AlphaShift flag.
    @discardableResult
    static func set(_ newState: Bool) -> Bool {
        guard let connect = openHIDSystem() else {
            FileLog.shared.error("set_caps_lock_state: could not open IOHIDSystem.")
            return false
        }
        defer { IOServiceClose(connect) }
        let kr = IOHIDSetModifierLockState(connect, kIOHIDCapsLockState, newState)
        if kr != KERN_SUCCESS {
            FileLog.shared.warn("set_caps_lock_state: IOHIDSetModifierLockState returned \(kr).")
            return false
        }
        return true
    }

    private static func openHIDSystem() -> io_connect_t? {
        let matching = IOServiceMatching("IOHIDSystem")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if service == 0 { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, kIOHIDParamConnectType, &connect)
        return kr == KERN_SUCCESS ? connect : nil
    }
}
