import Foundation

/// Keycode translation tables and display names.
///
/// The app's config stores keys as **JavaScript `KeyboardEvent.keyCode`** values
/// (a historical artifact of the original web-based UI). The macOS event tap
/// works in **Apple virtual keycodes** (`kVK_*`). These tables convert between
/// the two and must stay exact inverses of each other — a forward entry with no
/// matching reverse entry means a binding saves but silently never fires.
enum KeyCodes {
    // macOS virtual keycodes used directly by the engine.
    static let capsLock: UInt16 = 0x39
    static let f18: UInt16 = 0x4F      // CapsLock is remapped to F18 via hidutil
    static let `return`: UInt16 = 0x24
    static let delete: UInt16 = 0x33   // Backspace on macOS
    static let left: UInt16 = 0x7B
    static let right: UInt16 = 0x7C
    static let down: UInt16 = 0x7D
    static let up: UInt16 = 0x7E

    // Side-specific modifier keycodes for double-tap-modifier triggers.
    static let lShift: UInt16 = 56
    static let rShift: UInt16 = 60
    static let lCtrl: UInt16 = 59
    static let rCtrl: UInt16 = 62
    static let lOption: UInt16 = 58
    static let rOption: UInt16 = 61
    static let lCommand: UInt16 = 55
    static let rCommand: UInt16 = 54
    static let fn: UInt16 = 63

    /// JavaScript keyCode → macOS virtual keycode. Verified against the macOS
    /// SDK `Events.h` (`kVK_*`). The reverse table is kept an exact inverse.
    static func jsToMac(_ js: UInt16) -> UInt16? {
        switch js {
        // Letters A–Z
        case 65: return 0x00; case 66: return 0x0B; case 67: return 0x08
        case 68: return 0x02; case 69: return 0x0E; case 70: return 0x03
        case 71: return 0x05; case 72: return 0x04; case 73: return 0x22
        case 74: return 0x26; case 75: return 0x28; case 76: return 0x25
        case 77: return 0x2E; case 78: return 0x2D; case 79: return 0x1F
        case 80: return 0x23; case 81: return 0x0C; case 82: return 0x0F
        case 83: return 0x01; case 84: return 0x11; case 85: return 0x20
        case 86: return 0x09; case 87: return 0x0D; case 88: return 0x07
        case 89: return 0x10; case 90: return 0x06
        // Digits 0–9 (top row)
        case 48: return 0x1D; case 49: return 0x12; case 50: return 0x13
        case 51: return 0x14; case 52: return 0x15; case 53: return 0x17
        case 54: return 0x16; case 55: return 0x1A; case 56: return 0x1C
        case 57: return 0x19
        // Punctuation / symbols (ANSI/US physical layout)
        case 186: return 0x29; case 187: return 0x18; case 189: return 0x1B
        case 188: return 0x2B; case 190: return 0x2F; case 191: return 0x2C
        case 220: return 0x2A; case 222: return 0x27; case 219: return 0x21
        case 221: return 0x1E; case 192: return 0x32
        // Whitespace / control
        case 8: return 0x33; case 9: return 0x30; case 13: return 0x24
        case 27: return 0x35; case 32: return 0x31; case 46: return 0x75
        // Navigation cluster
        case 37: return 0x7B; case 38: return 0x7E; case 39: return 0x7C
        case 40: return 0x7D; case 36: return 0x73; case 35: return 0x77
        case 33: return 0x74; case 34: return 0x79
        // Function keys F1–F12
        case 112: return 0x7A; case 113: return 0x78; case 114: return 0x63
        case 115: return 0x76; case 116: return 0x60; case 117: return 0x61
        case 118: return 0x62; case 119: return 0x64; case 120: return 0x65
        case 121: return 0x6D; case 122: return 0x67; case 123: return 0x6F
        default: return nil
        }
    }

    /// macOS virtual keycode → JavaScript keyCode. Exact inverse of `jsToMac`.
    static func macToJs(_ mac: UInt16) -> UInt16? {
        switch mac {
        case 0x00: return 65; case 0x0B: return 66; case 0x08: return 67
        case 0x02: return 68; case 0x0E: return 69; case 0x03: return 70
        case 0x05: return 71; case 0x04: return 72; case 0x22: return 73
        case 0x26: return 74; case 0x28: return 75; case 0x25: return 76
        case 0x2E: return 77; case 0x2D: return 78; case 0x1F: return 79
        case 0x23: return 80; case 0x0C: return 81; case 0x0F: return 82
        case 0x01: return 83; case 0x11: return 84; case 0x20: return 85
        case 0x09: return 86; case 0x0D: return 87; case 0x07: return 88
        case 0x10: return 89; case 0x06: return 90
        case 0x1D: return 48; case 0x12: return 49; case 0x13: return 50
        case 0x14: return 51; case 0x15: return 52; case 0x17: return 53
        case 0x16: return 54; case 0x1A: return 55; case 0x1C: return 56
        case 0x19: return 57
        case 0x29: return 186; case 0x18: return 187; case 0x1B: return 189
        case 0x2B: return 188; case 0x2F: return 190; case 0x2C: return 191
        case 0x2A: return 220; case 0x27: return 222; case 0x21: return 219
        case 0x1E: return 221; case 0x32: return 192
        case 0x33: return 8; case 0x30: return 9; case 0x24: return 13
        case 0x35: return 27; case 0x31: return 32; case 0x75: return 46
        case 0x7B: return 37; case 0x7E: return 38; case 0x7C: return 39
        case 0x7D: return 40; case 0x73: return 36; case 0x77: return 35
        case 0x74: return 33; case 0x79: return 34
        case 0x7A: return 112; case 0x78: return 113; case 0x63: return 114
        case 0x76: return 115; case 0x60: return 116; case 0x61: return 117
        case 0x62: return 118; case 0x64: return 119; case 0x65: return 120
        case 0x6D: return 121; case 0x67: return 122; case 0x6F: return 123
        default: return nil
        }
    }

    /// Human-readable name for a JS keyCode (used in logs and the YAML
    /// `# comment`). Mirrors `js_keycode_name` in the Rust original.
    static func name(_ key: UInt16) -> String {
        switch key {
        case 48...57: return String(UnicodeScalar(UInt8(48 + (key - 48) + 0)))  // 0-9 → '0'..'9'
        case 65...90: return String(UnicodeScalar(UInt8(65 + (key - 65))))      // A-Z
        case 112...123: return "F\(key - 111)"
        case 8: return "Backspace"
        case 9: return "Tab"
        case 13: return "Enter"
        case 27: return "Esc"
        case 32: return "Space"
        case 46: return "Fwd Del"
        case 33: return "PgUp"
        case 34: return "PgDn"
        case 35: return "End"
        case 36: return "Home"
        case 37: return "Left"
        case 38: return "Up"
        case 39: return "Right"
        case 40: return "Down"
        case 186: return ";"
        case 187: return "="
        case 188: return ","
        case 189: return "-"
        case 190: return "."
        case 191: return "/"
        case 192: return "`"
        case 219: return "["
        case 220: return "\\"
        case 221: return "]"
        case 222: return "'"
        default: return "Key\(key)"
        }
    }
}
