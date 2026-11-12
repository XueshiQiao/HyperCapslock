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

    // MARK: - Headless discovery (CLI & ConfigValidator — zero AppKit/NSImage)

    struct SourceDescriptor: Codable, Equatable {
        let id: String
        let name: String
        let languages: [String]
        let isCJKV: Bool
        let isCurrent: Bool
    }

    private static let cjkvExactLanguages: Set<String> = ["ru", "ko", "ja", "vi"]

    /// Lists all installed, enabled, select-capable keyboard input sources via Carbon TIS
    /// without touching `NSApplication` or `NSImage`. Must be called on the main thread.
    static func listSelectableKeyboardSources() -> [SourceDescriptor] {
        let currentID: String? = {
            guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let ptr = TISGetInputSourceProperty(cur, kTISPropertyInputSourceID) else {
                return nil
            }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }()

        guard let cf = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        let sources = (cf as NSArray) as? [TISInputSource] ?? []
        return sources.compactMap { src in
            guard let catPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceCategory),
                  (Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String) == (kTISCategoryKeyboardInputSource as String),
                  let selPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue()),
                  let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else {
                return nil
            }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let name: String = {
                guard let p = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) else { return id }
                return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            }()
            let langs: [String] = {
                guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return [] }
                return (Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as NSArray) as? [String] ?? []
            }()
            let cjkv = langs.first.map { cjkvExactLanguages.contains($0) || $0.hasPrefix("zh") } ?? false
            return SourceDescriptor(id: id, name: name, languages: langs, isCJKV: cjkv, isCurrent: id == currentID)
        }
    }

    /// True if `id` is currently installed, enabled, and select-capable in Carbon TIS.
    static func isSelectableSourceInstalled(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let cf = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return false }
        let list = (cf as NSArray) as? [TISInputSource] ?? []
        return list.contains { src in
            guard let selPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue())
        }
    }
}
