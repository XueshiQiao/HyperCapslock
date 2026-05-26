import Foundation
import Carbon

/// macOS input-source (keyboard layout / IME) control via Carbon TIS.
///
/// TIS APIs assert main-queue affinity, so the switch runs on the main queue:
///   • `queueSwitch(toID:)` — async to main (fire-and-forget mapping switch).
///
/// When the configured `CJKVFixStrategy` is non-`.none` and the target is a CJKV
/// IME, the switch is handled by `InputSourceFix` instead of a plain select.
///
/// The old `smartToggle()` (auto 中/英 flip) was removed — see `IndependentActionKind`
/// in ActionModel.swift for why its built-in action is gone.
enum InputSourceController {
    // MARK: - CJKV fix strategy (set from the UI, read on the switch path)

    /// Lock-guarded so the UI-thread setter and the switch read don't race.
    /// Mirrors the `HudCenter` thread-safe-config pattern.
    private static let _fixStrategy = NSLock()
    private static var _fixStrategyValue: CJKVFixStrategy = .none

    static func setFixStrategy(_ strategy: CJKVFixStrategy) {
        _fixStrategy.lock(); defer { _fixStrategy.unlock() }
        _fixStrategyValue = strategy
    }

    static func currentFixStrategy() -> CJKVFixStrategy {
        _fixStrategy.lock(); defer { _fixStrategy.unlock() }
        return _fixStrategyValue
    }

    // MARK: - Switch to a specific source by ID

    /// Select the input source with the given ID. Returns `nil` on success or an
    /// error message string.
    @discardableResult
    static func select(byID id: String) -> String? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let listUM = TISCreateInputSourceList(filter, false) else {
            return "TISCreateInputSourceList returned null"
        }
        let list = listUM.takeRetainedValue()
        if CFArrayGetCount(list) <= 0 {
            return "Input source not found: \(id)"
        }
        let raw = CFArrayGetValueAtIndex(list, 0)
        let source = unsafeBitCast(raw, to: TISInputSource.self)
        let status = TISSelectInputSource(source)
        if status != noErr {
            return "TISSelectInputSource failed with status \(status)"
        }
        return nil
    }

    // MARK: - Mapping switch (async to main)

    static func queueSwitch(toID id: String) {
        let strategy = currentFixStrategy()
        DispatchQueue.main.async {
            InputSourceFix.switchToSource(id: id, strategy: strategy)
        }
    }
}
