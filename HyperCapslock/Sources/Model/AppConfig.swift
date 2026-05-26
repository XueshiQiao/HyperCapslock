import Foundation

/// Appearance preference: explicit light/dark, or follow the system.
enum ThemeMode: String, Codable, CaseIterable {
    case light, dark, system
}

/// Reliability workaround applied when a `Caps+key → input source` mapping
/// targets a CJKV IME (Chinese / Japanese / Korean / Vietnamese), where a plain
/// `TISSelectInputSource` often changes the menu-bar icon but leaves typing in
/// the previous source. The two non-`none` strategies are ported from
/// Input Source Pro (GPLv3); `switchingFocus` is itself adapted from macism (MIT).
/// `.none` (default) = no workaround, plain select.
enum CJKVFixStrategy: String, Codable, CaseIterable, Equatable {
    case none
    case shortcutSimulation = "shortcut_simulation"
    case switchingFocus = "switching_focus"
}

/// App-level preferences, persisted as `app_config.yml`. Unknown keys are
/// ignored on decode (tolerant); known keys round-trip.
struct AppConfig: Codable, Equatable {
    var hideDockIcon: Bool = false
    var showHud: Bool = false
    var hudDurationMs: Int = 1350
    var themeMode: ThemeMode = .system
    var cjkvFixStrategy: CJKVFixStrategy = .none

    enum CodingKeys: String, CodingKey {
        case hideDockIcon = "hide_dock_icon"
        case showHud = "show_hud"
        case hudDurationMs = "hud_duration_ms"
        case themeMode = "theme_mode"
        case cjkvFixStrategy = "cjkv_fix_strategy"
    }

    init(hideDockIcon: Bool = false, showHud: Bool = false, hudDurationMs: Int = 1350,
         themeMode: ThemeMode = .system, cjkvFixStrategy: CJKVFixStrategy = .none) {
        self.hideDockIcon = hideDockIcon
        self.showHud = showHud
        self.hudDurationMs = hudDurationMs
        self.themeMode = themeMode
        self.cjkvFixStrategy = cjkvFixStrategy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hideDockIcon = try c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
        self.showHud = try c.decodeIfPresent(Bool.self, forKey: .showHud) ?? false
        self.hudDurationMs = try c.decodeIfPresent(Int.self, forKey: .hudDurationMs) ?? 1350
        self.themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .system
        // Tolerant: an unknown future strategy value decodes back to `.none`.
        self.cjkvFixStrategy = (try? c.decodeIfPresent(CJKVFixStrategy.self, forKey: .cjkvFixStrategy)) ?? .none
    }
}
