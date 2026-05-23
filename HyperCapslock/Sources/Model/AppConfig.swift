import Foundation

/// Appearance preference: explicit light/dark, or follow the system.
enum ThemeMode: String, Codable, CaseIterable {
    case light, dark, system
}

/// App-level preferences, persisted as `app_config.yml`. Unknown keys are
/// ignored on decode (tolerant); known keys round-trip.
struct AppConfig: Codable, Equatable {
    var hideDockIcon: Bool = false
    var showHud: Bool = false
    var hudDurationMs: Int = 1350
    var themeMode: ThemeMode = .system

    enum CodingKeys: String, CodingKey {
        case hideDockIcon = "hide_dock_icon"
        case showHud = "show_hud"
        case hudDurationMs = "hud_duration_ms"
        case themeMode = "theme_mode"
    }

    init(hideDockIcon: Bool = false, showHud: Bool = false, hudDurationMs: Int = 1350, themeMode: ThemeMode = .system) {
        self.hideDockIcon = hideDockIcon
        self.showHud = showHud
        self.hudDurationMs = hudDurationMs
        self.themeMode = themeMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hideDockIcon = try c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
        self.showHud = try c.decodeIfPresent(Bool.self, forKey: .showHud) ?? false
        self.hudDurationMs = try c.decodeIfPresent(Int.self, forKey: .hudDurationMs) ?? 1350
        self.themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .system
    }
}
