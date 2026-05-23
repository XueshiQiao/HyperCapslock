import Foundation

/// App-level preferences, persisted as `app_config.yml`. Field names match the
/// original serde struct so the existing file round-trips unchanged.
struct AppConfig: Codable, Equatable {
    var hideDockIcon: Bool = false
    var showHud: Bool = false
    var hudDurationMs: Int = 1350

    enum CodingKeys: String, CodingKey {
        case hideDockIcon = "hide_dock_icon"
        case showHud = "show_hud"
        case hudDurationMs = "hud_duration_ms"
    }

    init(hideDockIcon: Bool = false, showHud: Bool = false, hudDurationMs: Int = 1350) {
        self.hideDockIcon = hideDockIcon
        self.showHud = showHud
        self.hudDurationMs = hudDurationMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hideDockIcon = try c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
        self.showHud = try c.decodeIfPresent(Bool.self, forKey: .showHud) ?? false
        self.hudDurationMs = try c.decodeIfPresent(Int.self, forKey: .hudDurationMs) ?? 1350
    }
}
