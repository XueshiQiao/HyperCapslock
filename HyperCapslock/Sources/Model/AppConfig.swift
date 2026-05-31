import Foundation

/// Appearance preference: explicit light/dark, or follow the system.
enum ThemeMode: String, Codable, CaseIterable {
    case light, dark, system
}

/// How the Mappings page renders its content. Pure presentation — the mappings
/// themselves are identical across styles. Persisted in `app_config.yml` so the
/// chosen style survives relaunch.
enum MappingsViewStyle: String, Codable, CaseIterable, Equatable {
    case grouped   // sectioned by trigger category (default)
    case keyboard  // a visual keyboard map
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
    /// Broadcast CapsLock-hold over `DistributedNotificationCenter` so AnyDrag
    /// can arm its "hold CapsLock and drag a window" gesture. Off by default —
    /// users who don't run AnyDrag emit zero cross-app chatter.
    var broadcastCapsHoldForAnyDrag: Bool = false
    var mappingsViewStyle: MappingsViewStyle = .grouped

    enum CodingKeys: String, CodingKey {
        case hideDockIcon = "hide_dock_icon"
        case showHud = "show_hud"
        case hudDurationMs = "hud_duration_ms"
        case themeMode = "theme_mode"
        case cjkvFixStrategy = "cjkv_fix_strategy"
        case broadcastCapsHoldForAnyDrag = "broadcast_caps_hold_for_anydrag"
        case mappingsViewStyle = "mappings_view_style"
    }

    init(hideDockIcon: Bool = false, showHud: Bool = false, hudDurationMs: Int = 1350,
         themeMode: ThemeMode = .system, cjkvFixStrategy: CJKVFixStrategy = .none,
         broadcastCapsHoldForAnyDrag: Bool = false,
         mappingsViewStyle: MappingsViewStyle = .grouped) {
        self.hideDockIcon = hideDockIcon
        self.showHud = showHud
        self.hudDurationMs = hudDurationMs
        self.themeMode = themeMode
        self.cjkvFixStrategy = cjkvFixStrategy
        self.broadcastCapsHoldForAnyDrag = broadcastCapsHoldForAnyDrag
        self.mappingsViewStyle = mappingsViewStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hideDockIcon = try c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
        self.showHud = try c.decodeIfPresent(Bool.self, forKey: .showHud) ?? false
        self.hudDurationMs = try c.decodeIfPresent(Int.self, forKey: .hudDurationMs) ?? 1350
        self.themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .system
        // Tolerant: an unknown future strategy value decodes back to `.none`.
        self.cjkvFixStrategy = (try? c.decodeIfPresent(CJKVFixStrategy.self, forKey: .cjkvFixStrategy)) ?? .none
        self.broadcastCapsHoldForAnyDrag = try c.decodeIfPresent(Bool.self, forKey: .broadcastCapsHoldForAnyDrag) ?? false
        // Tolerant: a missing value, or the now-removed legacy "list" value,
        // decodes back to `.grouped`.
        self.mappingsViewStyle = (try? c.decodeIfPresent(MappingsViewStyle.self, forKey: .mappingsViewStyle)) ?? .grouped
    }
}
