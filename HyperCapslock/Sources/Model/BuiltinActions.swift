import Foundation

/// The code-defined built-in action catalog.
///
/// ⚠️ PERMANENT CONTRACT — the `builtin.*` IDs below are referenced by users'
/// saved mappings (`action_id`). Once shipped, an ID must NEVER be renamed or
/// removed: doing so orphans every mapping that references it. You may add new
/// built-ins; you may not change or delete existing IDs. (See AGENTS.md.)
///
/// Built-ins are never persisted — they exist only here and are merged with the
/// user's custom actions at runtime by `ActionsRegistry`.
enum BuiltinActions {
    static let all: [Action] = [
        a("builtin.move_left",        "action.left",          .directional(.left)),
        a("builtin.move_right",       "action.right",         .directional(.right)),
        a("builtin.move_up",          "action.up",            .directional(.up)),
        a("builtin.move_down",        "action.down",          .directional(.down)),
        a("builtin.word_forward",     "action.word_forward",  .directional(.wordForward)),
        a("builtin.word_back",        "action.word_back",     .directional(.wordBack)),
        a("builtin.line_start",       "action.home",          .directional(.home)),
        a("builtin.line_end",         "action.end",           .directional(.end)),
        a("builtin.jump_up_10",       "action.up",            .jump(direction: .up, count: 10)),
        a("builtin.jump_down_10",     "action.down",          .jump(direction: .down, count: 10)),
        a("builtin.backspace",        "action.backspace",     .independent(.backspace)),
        a("builtin.new_line",         "action.next_line",     .independent(.nextLine)),
        a("builtin.insert_quotes",    "action.insert_quotes", .independent(.insertQuotes)),
        a("builtin.toggle_caps_lock", "action.toggle_caps_lock", .independent(.toggleCapsLock)),
        a("builtin.switch_input_source", "action.switch_input_source", .independent(.switchInputSource)),
    ]

    private static let ids: Set<String> = Set(all.map(\.id))

    static func isBuiltinID(_ id: String) -> Bool { id.hasPrefix("builtin.") }

    static func byID(_ id: String) -> Action? { all.first { $0.id == id } }

    /// Find the built-in whose config exactly matches `config` (used to migrate a
    /// legacy inline action to a built-in id where possible).
    static func matching(_ config: ActionConfig) -> Action? {
        all.first { $0.config == config }
    }

    private static func a(_ id: String, _ nameKey: String, _ config: ActionConfig) -> Action {
        Action(id: id, name: nameKey, nameKey: nameKey, config: config, isBuiltin: true)
    }
}
