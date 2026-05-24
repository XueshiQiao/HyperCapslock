import Foundation
import Carbon

/// macOS input-source (keyboard layout / IME) control via Carbon TIS.
///
/// TIS APIs assert main-queue affinity, so every call that touches them runs on
/// the main queue. Two dispatch shapes, exactly as in the Rust original:
///   • `queueSwitch(toID:)` — async to main (fire-and-forget mapping switch).
///   • `smartToggle()` — **sync** to main from the event-tap thread, so the
///     user's in-flight key is held at the tap until the source has switched
///     (no "first letter in the old IME" bug). No analog of the AlphaShift patch
///     exists for IME state, hence the synchronous hold.
enum InputSourceController {
    /// Latin layouts live under `com.apple.keylayout.*`; everything else
    /// (Pinyin, WeChat, Kotoeri, …) is treated as non-Latin.
    static func isLatin(_ id: String) -> Bool {
        id.hasPrefix("com.apple.keylayout.")
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
        FileLog.shared.info("Queueing input source mapping switch: source_id=\(id)")
        DispatchQueue.main.async {
            if let e = select(byID: id) {
                FileLog.shared.warn("Input source mapping failed on main queue: source_id=\(id) error=\(e)")
            } else {
                FileLog.shared.info("Input source mapping switched on main queue: source_id=\(id)")
            }
        }
    }

    // MARK: - Reads (main-queue only)

    private static func currentSourceIDOnMain() -> String? {
        guard let srcUM = TISCopyCurrentKeyboardInputSource() else { return nil }
        let src = srcUM.takeRetainedValue()
        return propertyString(src, kTISPropertyInputSourceID)
    }

    /// Enabled, selectable keyboard input sources (filters out IME bundle
    /// parents whose only role is to namespace their input modes).
    private static func enabledKeyboardSourcesOnMain() -> [String] {
        guard let listUM = TISCreateInputSourceList(nil, false) else { return [] }
        let list = listUM.takeRetainedValue()
        let count = CFArrayGetCount(list)
        var result: [String] = []
        for i in 0..<count {
            let raw = CFArrayGetValueAtIndex(list, i)
            let src = unsafeBitCast(raw, to: TISInputSource.self)

            guard let category = propertyCFType(src, kTISPropertyInputSourceCategory),
                  CFEqual(category, kTISCategoryKeyboardInputSource) else { continue }

            guard let selectablePtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let selectable = Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue()
            guard CFBooleanGetValue(selectable) else { continue }

            if let id = propertyString(src, kTISPropertyInputSourceID) {
                result.append(id)
            }
        }
        return result
    }

    private static func propertyString(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func propertyCFType(_ src: TISInputSource, _ key: CFString) -> CFTypeRef? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(ptr).takeUnretainedValue()
    }

    // MARK: - Smart 中/英 toggle (sync to main)

    private static func pickSmartToggleTargetOnMain() -> String? {
        guard let current = currentSourceIDOnMain() else { return nil }
        let currentIsLatin = isLatin(current)
        FileLog.shared.info("Smart toggle: current input source = \(current) (\(currentIsLatin ? "Latin" : "non-Latin"))")

        let sources = enabledKeyboardSourcesOnMain()
        if sources.isEmpty {
            FileLog.shared.warn("Smart toggle: TIS returned an empty enabled-keyboard-source list.")
            return nil
        }
        let dump = sources.map { id -> String in
            let tag = isLatin(id) ? "Latin" : "non-Latin"
            let marker = id == current ? " <- current" : ""
            return "    [\(tag)] \(id)\(marker)"
        }.joined(separator: "\n")
        FileLog.shared.info("Smart toggle: enabled keyboard sources (\(sources.count) total):\n\(dump)")

        if let opposite = sources.first(where: { $0 != current && isLatin($0) != currentIsLatin }) {
            FileLog.shared.info("Smart toggle: picked opposite-category target = \(opposite)")
            return opposite
        }
        if let fallback = sources.first(where: { $0 != current }) {
            FileLog.shared.info("Smart toggle: no opposite-category source — picked cycle fallback target = \(fallback)")
            return fallback
        }
        FileLog.shared.warn("Smart toggle: only one enabled source — no toggle target available.")
        return nil
    }

    /// Synchronously dispatch to the main queue and TIS-select the toggle target.
    /// Called from the event-tap thread; blocks it until the switch completes.
    static func smartToggle() {
        if EngineState.shared.isPaused { return }
        DispatchQueue.main.sync {
            guard let target = pickSmartToggleTargetOnMain() else {
                FileLog.shared.info("Smart toggle: no candidate target available.")
                return
            }
            FileLog.shared.info("Smart toggle target: \(target)")
            if let e = select(byID: target) {
                FileLog.shared.warn("Smart toggle TIS failed: \(e)")
            }
        }
    }
}
