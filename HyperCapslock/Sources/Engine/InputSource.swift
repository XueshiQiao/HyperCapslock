import Foundation
import Carbon

/// macOS input-source (keyboard layout / IME) control via Carbon TIS.
///
/// TIS APIs assert main-queue affinity, so the switch runs on the main queue:
///   • `queueSwitch(toID:)` — async to main (fire-and-forget mapping switch).
///
/// The old `smartToggle()` (auto 中/英 flip) was removed — see `IndependentActionKind`
/// in ActionModel.swift for why its built-in action is gone.
enum InputSourceController {
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
}
