import Foundation

/// A library action: a named, reusable binding target. Either built-in
/// (code-defined, read-only) or custom (user-defined, persisted in the config).
/// Mappings reference an action by `id`; the engine resolves id → `config`.
struct Action: Identifiable, Equatable {
    let id: String
    var name: String           // display name (custom: user-set; built-in: English fallback)
    var nameKey: String?       // L10n key for built-ins (UI prefers this over `name`)
    var config: ActionConfig
    var isBuiltin: Bool

    init(id: String, name: String, nameKey: String? = nil, config: ActionConfig, isBuiltin: Bool) {
        self.id = id
        self.name = name
        self.nameKey = nameKey
        self.config = config
        self.isBuiltin = isBuiltin
    }
}

// Custom actions persist in the config's `actions:` section as { id, name, action }.
// Built-ins are never encoded (they live in code).
extension Action: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, action }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        self.id = id
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        self.nameKey = nil
        self.config = try c.decode(ActionConfig.self, forKey: .action)
        self.isBuiltin = BuiltinActions.isBuiltinID(id)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(config, forKey: .action)
    }
}
