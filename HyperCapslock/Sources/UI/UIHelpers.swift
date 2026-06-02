import SwiftUI

/// Display string for a JS keyCode in the UI (mirrors `keyCodeToDisplay` in
/// App.tsx — arrows/symbols get glyphs, letters/digits show as-is).
func keyCodeDisplay(_ keyCode: UInt16) -> String {
    let special: [UInt16: String] = [
        8: "Backspace", 9: "Tab", 13: "Enter", 27: "Esc", 32: "Space", 46: "⌦",
        33: "PgUp", 34: "PgDn", 35: "End", 36: "Home", 37: "←", 38: "↑", 39: "→", 40: "↓",
        112: "F1", 113: "F2", 114: "F3", 115: "F4", 116: "F5", 117: "F6",
        118: "F7", 119: "F8", 120: "F9", 121: "F10", 122: "F11", 123: "F12",
        186: ";", 187: "=", 188: ",", 189: "-", 190: ".", 191: "/",
        219: "[", 220: "\\", 221: "]", 222: "'", 192: "`",
    ]
    if let s = special[keyCode] { return s }
    if (keyCode >= 65 && keyCode <= 90) || (keyCode >= 48 && keyCode <= 57) {
        return String(UnicodeScalar(UInt8(keyCode)))
    }
    return "Key \(keyCode)"
}

/// Glyph for a modifier key in trigger chips, e.g. "⌘L".
func modifierGlyph(_ m: ModifierKey) -> String {
    switch m {
    case .leftCommand: return "⌘L"
    case .rightCommand: return "⌘R"
    case .leftControl: return "⌃L"
    case .rightControl: return "⌃R"
    case .leftOption: return "⌥L"
    case .rightOption: return "⌥R"
    case .leftShift: return "⇧L"
    case .rightShift: return "⇧R"
    case .fn: return "fn"
    }
}

/// Unambiguous modifier label spelling out side + name + glyph (e.g. "Right Cmd
/// ⌘") so it can't be misread as a "⌘+R" combo. Used by the double-tap-modifier
/// trigger picker and the Hold Modifier action picker so both read identically.
/// `.fn` has no side and is flagged experimental.
@MainActor
func modifierFullLabel(_ m: ModifierKey, _ loc: LocalizationManager) -> String {
    let left = loc.t("side.left"), right = loc.t("side.right")
    switch m {
    case .leftCommand:  return "\(left) Cmd ⌘"
    case .rightCommand: return "\(right) Cmd ⌘"
    case .leftControl:  return "\(left) Ctrl ⌃"
    case .rightControl: return "\(right) Ctrl ⌃"
    case .leftOption:   return "\(left) Opt ⌥"
    case .rightOption:  return "\(right) Opt ⌥"
    case .leftShift:    return "\(left) Shift ⇧"
    case .rightShift:   return "\(right) Shift ⇧"
    case .fn:           return "fn (\(loc.t("trigger.experimental")))"
    }
}

/// A rounded "card" container matching the original panel look.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}
