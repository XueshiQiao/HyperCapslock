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

    /// Effective action config for a mapping: a resolvable `actionId` wins;
    /// otherwise the inline action; otherwise nil (an invalid/orphaned mapping —
    /// the caller logs it and shows ⚠️, never silently drops it).
    func resolve(_ entry: ActionMappingEntry) -> ActionConfig? {
        if let id = entry.actionId, let a = action(byID: id) { return a.config }
        return entry.inlineAction
    }
}
