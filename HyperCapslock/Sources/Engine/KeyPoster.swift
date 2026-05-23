import Foundation
import CoreGraphics

/// Synthesizes keyboard events. Every posted event is stamped with
/// `injectedMagic` in `EVENT_SOURCE_USER_DATA` so the tap callback skips it
/// (no feedback loop / re-detection). Mirrors `post_key` / `post_key_tap`.
enum KeyPoster {
    /// Magic value stamped on injected events ("GVLN").
    static let injectedMagic: Int64 = 0x4756_4C4E

    static func post(_ keycode: UInt16, keyDown: Bool, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keycode, keyDown: keyDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: injectedMagic)
        event.post(tap: .cghidEventTap)
    }

    static func postTap(_ keycode: UInt16, flags: CGEventFlags) {
        post(keycode, keyDown: true, flags: flags)
        post(keycode, keyDown: false, flags: flags)
    }

    /// Insert a literal string, bypassing the IME (posted at the annotated
    /// session level) so Chinese input methods don't convert ASCII quotes into
    /// smart quotes. Used by the InsertQuotes action.
    static func insertString(_ string: String) {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
        let utf16 = Array(string.utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        event.setIntegerValueField(.eventSourceUserData, value: injectedMagic)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }
}
