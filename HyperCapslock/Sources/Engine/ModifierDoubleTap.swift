import Foundation
import CoreGraphics

/// Double-tap-modifier detection, independent of the Caps/F18 path.
///
/// One slot per ModifierKey (9). The whole subsystem is gated by
/// `anyConfigured()` — an unconfigured keyboard does zero work. Once active,
/// physical down-state is tracked for ALL nine slots (even unmapped ones): a
/// configured modifier's tap can only be judged "clean" if no *other* modifier
/// is physically held, and the only way to know an unmapped sibling is held is
/// to track it. Tap bookkeeping runs only for configured modifiers.
final class ModifierDoubleTap {
    static let shared = ModifierDoubleTap()

    private struct ModTapState {
        var lastCleanTapMs: UInt64 = 0  // 0 = no pending first tap
        var pressStartMs: UInt64 = 0    // 0 = not currently held
        var armed = false               // candidate tap in progress
        var dirty = false               // disqualified: combined with another key/modifier
        var physDown = false            // physical key-down state (all slots, while active)
    }

    private let lock = NSLock()
    private var table = [ModTapState](repeating: ModTapState(), count: 9)

    // MARK: - Static mapping helpers

    static func modifier(for keycode: UInt16) -> ModifierKey? {
        switch keycode {
        case KeyCodes.lShift: return .leftShift
        case KeyCodes.rShift: return .rightShift
        case KeyCodes.lCtrl: return .leftControl
        case KeyCodes.rCtrl: return .rightControl
        case KeyCodes.lOption: return .leftOption
        case KeyCodes.rOption: return .rightOption
        case KeyCodes.lCommand: return .leftCommand
        case KeyCodes.rCommand: return .rightCommand
        case KeyCodes.fn: return .fn
        default: return nil
        }
    }

    private static func slot(_ m: ModifierKey) -> Int {
        switch m {
        case .leftShift: return 0
        case .rightShift: return 1
        case .leftControl: return 2
        case .rightControl: return 3
        case .leftOption: return 4
        case .rightOption: return 5
        case .leftCommand: return 6
        case .rightCommand: return 7
        case .fn: return 8
        }
    }

    /// Side-agnostic family mask: decides whether a FlagsChanged is a press
    /// (bit set) or release (bit cleared). Side comes from the keycode.
    private static func familyMask(_ m: ModifierKey) -> CGEventFlags {
        switch m {
        case .leftShift, .rightShift: return .maskShift
        case .leftControl, .rightControl: return .maskControl
        case .leftOption, .rightOption: return .maskAlternate
        case .leftCommand, .rightCommand: return .maskCommand
        case .fn: return .maskSecondaryFn
        }
    }

    private static func familySiblingSlots(_ m: ModifierKey) -> [Int] {
        switch m {
        case .leftShift, .rightShift: return [0, 1]
        case .leftControl, .rightControl: return [2, 3]
        case .leftOption, .rightOption: return [4, 5]
        case .leftCommand, .rightCommand: return [6, 7]
        case .fn: return [8]
        }
    }

    // MARK: - Config lookups

    static func anyConfigured() -> Bool {
        MappingsRegistry.shared.withMappings { mappings in
            mappings.contains { if case .doubleTapModifier = $0.trigger { return true }; return false }
        }
    }

    private static func configuredAction(_ m: ModifierKey) -> ActionConfig? {
        MappingsRegistry.shared.withMappings { mappings in
            guard let entry = mappings.first(where: { if case .doubleTapModifier(let cfg) = $0.trigger { return cfg == m }; return false })
            else { return nil }
            return ActionsRegistry.shared.resolve(entry)
        }
    }

    // MARK: - Invalidation (a non-modifier key joined → chord, not a lone tap)

    func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        for i in table.indices {
            if table[i].armed { table[i].dirty = true }
            table[i].lastCleanTapMs = 0
        }
    }

    // MARK: - Core state machine

    /// Handle a FlagsChanged for any modifier keycode. Returns the action to
    /// fire on a clean double-tap, else nil.
    func onModifierFlags(_ modifier: ModifierKey, flags: CGEventFlags) -> ActionConfig? {
        let now = nowMillis()
        let slot = Self.slot(modifier)
        let familyActive = !flags.intersection(Self.familyMask(modifier)).isEmpty
        let configured = Self.configuredAction(modifier)

        lock.lock(); defer { lock.unlock() }

        // This key's transition.
        let isPress: Bool
        if !familyActive {
            // No key of this family is down → hard resync both siblings to up.
            isPress = false
            for i in Self.familySiblingSlots(modifier) {
                table[i].physDown = false
                if i != slot && table[i].armed { table[i].armed = false }
            }
        } else if table[slot].physDown {
            isPress = false
            table[slot].physDown = false
        } else {
            isPress = true
            table[slot].physDown = true
        }

        // Another modifier physically held, or a non-family bit set in the flags.
        let otherPhys = table.indices.contains { $0 != slot && table[$0].physDown }
        let crossFamily = activeModifierFlags(flags).subtracting(Self.familyMask(modifier))
        let otherMod = otherPhys || !crossFamily.isEmpty

        if isPress {
            // A modifier press anywhere invalidates every other in-progress tap.
            for i in table.indices where i != slot && table[i].armed {
                table[i].dirty = true
            }
            if configured != nil {
                table[slot].armed = true
                table[slot].pressStartMs = now
                table[slot].dirty = otherMod
            }
            return nil
        } else {
            // Release.
            guard configured != nil else { return nil }
            let wasArmed = table[slot].armed
            let dirty = table[slot].dirty
            let held = now &- table[slot].pressStartMs
            table[slot].armed = false
            table[slot].pressStartMs = 0
            table[slot].dirty = false

            if !wasArmed || dirty || otherMod || held > EngineConstants.capsTapMaxMs {
                return nil
            }
            if table[slot].lastCleanTapMs != 0
                && now &- table[slot].lastCleanTapMs <= EngineConstants.doubleTapWindowMs {
                table[slot].lastCleanTapMs = 0
                return configured
            }
            table[slot].lastCleanTapMs = now
            return nil
        }
    }
}
