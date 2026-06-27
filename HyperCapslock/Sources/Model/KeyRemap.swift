import Foundation

/// A spare *right-side* modifier the user may repurpose, via `hidutil`, into a
/// free function key. Only the right-hand modifiers are offered: their left-hand
/// twins keep doing their normal job, so the user never loses a modifier outright
/// — they just sacrifice the seldom-used right one. The raw value is the stable
/// YAML token persisted in `app_config.yml`.
enum KeyRemapSource: String, Codable, CaseIterable, Equatable, Identifiable {
  case rightCommand = "right_command"
  case rightOption = "right_option"
  case rightControl = "right_control"
  case rightShift = "right_shift"

  var id: String { rawValue }

  /// HID usage (usage page 0x07) for `hidutil`'s `UserKeyMapping`. This is a
  /// *third* numbering, distinct from both the JS keyCodes and the macOS virtual
  /// keycodes the rest of the app uses.
  var hidUsage: UInt64 {
    switch self {
    case .rightCommand: return 0x7000000E7
    case .rightOption: return 0x7000000E6
    case .rightControl: return 0x7000000E4
    case .rightShift: return 0x7000000E5
    }
  }
}

/// A free function key (F13–F19) that macOS assigns no default action to, so it's
/// safe to repurpose as a global hotkey in other apps. **F18 is deliberately
/// absent** — it's the app's own CapsLock remap target and is reserved.
enum KeyRemapTarget: String, Codable, CaseIterable, Equatable, Identifiable {
  case f13, f14, f15, f16, f17, f19

  var id: String { rawValue }

  /// "f17" → "F17". No localization needed — function-key names are universal.
  var displayName: String { rawValue.uppercased() }

  var hidUsage: UInt64 {
    switch self {
    case .f13: return 0x700000068
    case .f14: return 0x700000069
    case .f15: return 0x70000006A
    case .f16: return 0x70000006B
    case .f17: return 0x70000006C
    case .f19: return 0x70000006E
    }
  }
}

/// One user-configured low-level remap: a spare right modifier → a free function
/// key. Applied via `hidutil` on top of the built-in CapsLock→F18 remap, so the
/// repurposed key can be bound as a global hotkey in any app (and used inside
/// HyperCapslock too, once the recorder accepts F13–F19).
struct KeyRemap: Codable, Equatable, Identifiable {
  var source: KeyRemapSource
  var destination: KeyRemapTarget

  /// `source` is unique across the list (the editor enforces it), so it doubles
  /// as a stable identity.
  var id: String { source.rawValue }

  enum CodingKeys: String, CodingKey {
    case source
    case destination
  }
}
