import Foundation

/// Thread-safe registry of all actions: code-defined built-ins (immutable) plus
/// the user's custom actions. The event-tap thread resolves a mapping → action
/// config through here; the UI writes custom actions via `ConfigStore`.
final class ActionsRegistry {
    static let shared = ActionsRegistry()

    private let lock = NSLock()
    private var custom: [Action] = []

    func setCustom(_ actions: [Action]) {
        lock.lock(); defer { lock.unlock() }
        custom = actions
    }

    func customActions() -> [Action] {
        lock.lock(); defer { lock.unlock() }
        return custom
    }

    /// Built-ins + custom, aggregated for the Actions page.
    func allActions() -> [Action] {
        lock.lock(); defer { lock.unlock() }
        return BuiltinActions.all + custom
    }

    func action(byID id: String) -> Action? {
        if let b = BuiltinActions.byID(id) { return b }
        lock.lock(); defer { lock.unlock() }
        return custom.first { $0.id == id }
    }

    /// Effective action config for an `(actionId, inline)` reference — the shared
    /// precedence used by both mappings and per-app bindings: a resolvable
    /// `actionId` wins, else the inline action, else nil.
    func resolve(actionId: String?, inline: ActionConfig?) -> ActionConfig? {
        if let id = actionId, let a = action(byID: id) { return a.config }
        return inline
    }

    /// Effective action config for a mapping: a resolvable `actionId` wins;
    /// otherwise the inline action; otherwise nil (an invalid/orphaned mapping —
    /// the caller logs it and shows ⚠️, never silently drops it).
    func resolve(_ entry: ActionMappingEntry) -> ActionConfig? {
        resolve(actionId: entry.actionId, inline: entry.inlineAction)
    }

    /// Effective action config for a per-app binding — same precedence as a
    /// mapping: resolvable `actionId` wins, else inline, else nil.
    func resolve(_ binding: MappingBinding) -> ActionConfig? {
        resolve(actionId: binding.actionId, inline: binding.inlineAction)
    }
}
