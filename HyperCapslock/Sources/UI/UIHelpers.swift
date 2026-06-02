import SwiftUI
import AppKit

extension View {
    /// The app's signature soft aurora wash, composited over an OPAQUE base.
    ///
    /// Opaque matters for performance: when the foreground (a grouped Form) hides
    /// its own background via `.scrollContentBackground(.hidden)`, a translucent
    /// wash would let the window's vibrancy sample the desktop and re-blur on every
    /// drag frame (a visible stutter). The opaque window-color base avoids that.
    /// Pair this with `.scrollContentBackground(.hidden)` on the Form so the grouped
    /// cards float over the wash.
    func auroraBackground() -> some View {
        background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(
                    LinearGradient(colors: [Color(.sRGB, red: 0.40, green: 0.55, blue: 1.00, opacity: 0.10),
                                            Color(.sRGB, red: 1.00, green: 0.55, blue: 0.85, opacity: 0.07),
                                            Color(.sRGB, red: 0.35, green: 0.85, blue: 0.70, opacity: 0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .ignoresSafeArea()
        )
    }
}

// MARK: - Colored icon tiles
//
// The shared leading-icon visual used across the app (Actions rows, Settings rows,
// Input Source methods, About links): a white glyph on a category/accent-colored
// gradient tile, matching the sidebar icons. `ArtTile` is the exception for
// self-contained artwork (an app icon) that shouldn't be tinted.

/// 26pt rounded gradient tile background in `color`, with a hairline white edge.
private struct ColorTile: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(
                LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.18)))
    }
}
extension View { func colorTile(_ color: Color) -> some View { modifier(ColorTile(color: color)) } }

/// White SF Symbol on a colored tile.
struct IconTile: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).colorTile(color)
    }
}

/// A white template-rendered asset (e.g. a brand logo) on a colored tile.
struct AssetIconTile: View {
    let asset: String
    let color: Color
    var glyph: CGFloat = 15
    var body: some View {
        Image(asset).renderingMode(.template).resizable().scaledToFit()
            .frame(width: glyph, height: glyph).foregroundStyle(.white).colorTile(color)
    }
}

/// Self-contained artwork (an app icon) at the tile footprint — shown as-is on a
/// rounded clip, NOT tinted, since the artwork carries its own colors.
struct ArtTile: View {
    let image: Image
    var body: some View {
        image.resizable().interpolation(.high)
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.black.opacity(0.08)))
    }
}

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
