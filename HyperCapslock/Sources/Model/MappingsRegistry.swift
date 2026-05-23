import Foundation

/// Thread-safe holder of the live action mappings. The event-tap callback reads
/// from here on its own thread; the UI writes through `ConfigStore`, which keeps
/// this registry in sync. Mirrors the Rust `Mutex<Option<Vec<ActionMappingEntry>>>`.
final class MappingsRegistry {
    static let shared = MappingsRegistry()

    private let lock = NSLock()
    private var mappings: [ActionMappingEntry] = []

    func set(_ newMappings: [ActionMappingEntry]) {
        lock.lock(); defer { lock.unlock() }
        mappings = newMappings
    }

    func snapshot() -> [ActionMappingEntry] {
        lock.lock(); defer { lock.unlock() }
        return mappings
    }

    /// Run `body` against the live mappings under the lock and return its result.
    /// Keeps the read in the hot path allocation-free (no array copy).
    func withMappings<T>(_ body: ([ActionMappingEntry]) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(mappings)
    }
}
