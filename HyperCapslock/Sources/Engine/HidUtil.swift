import Foundation

/// CapsLock → F18 remap via `hidutil`. This gives proper KeyDown/KeyUp events
/// for CapsLock instead of the unreliable FlagsChanged toggle macOS sends
/// natively, which is what makes Caps usable as a hyper modifier.
enum HidUtil {
    // 0x700000039 = CapsLock usage, 0x70000006D = F18 usage. This base remap is
    // always present — it's what makes CapsLock usable as the hyper modifier.
    private static let capsLockUsage: UInt64 = 0x700000039
    private static let f18Usage: UInt64 = 0x70000006D
    private static let clearPayload = #"{"UserKeyMapping":[]}"#

    /// Apply the base CapsLock→F18 remap plus any user-configured remaps, as a
    /// single `--set` (hidutil replaces the whole `UserKeyMapping`, so everything
    /// must go in one call). Idempotent — safe to call again whenever the list
    /// changes.
    @discardableResult
    static func setupRemap(extra: [KeyRemap] = []) -> Bool {
        run(["property", "--set", buildPayload(extra: extra)],
            onSuccess: "hidutil remap applied (CapsLock→F18 + \(extra.count) user remap(s)).",
            onFail: "hidutil remap failed")
    }

    /// Build the `UserKeyMapping` JSON: the base remap first, then the user
    /// remaps (deduped by source, so a hand-edited config can't emit a key twice).
    private static func buildPayload(extra: [KeyRemap]) -> String {
        var pairs: [(src: UInt64, dst: UInt64)] = [(capsLockUsage, f18Usage)]
        var seenSrc: Set<UInt64> = [capsLockUsage]
        for r in extra where seenSrc.insert(r.source.hidUsage).inserted {
            pairs.append((r.source.hidUsage, r.destination.hidUsage))
        }
        func hex(_ v: UInt64) -> String { "0x" + String(v, radix: 16) }
        let entries = pairs.map {
            #"{"HIDKeyboardModifierMappingSrc":\#(hex($0.src)),"HIDKeyboardModifierMappingDst":\#(hex($0.dst))}"#
        }.joined(separator: ",")
        return #"{"UserKeyMapping":[\#(entries)]}"#
    }

    static func cleanupRemap() {
        _ = run(["property", "--set", clearPayload], onSuccess: "hidutil remap removed.",
                onFail: "Failed to remove hidutil remap")
    }

    @discardableResult
    private static func run(_ args: [String], onSuccess: String, onFail: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                FileLog.shared.info(onSuccess)
                return true
            }
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            FileLog.shared.error("\(onFail) (status=\(proc.terminationStatus)): \(err)")
            return false
        } catch {
            FileLog.shared.error("Failed to execute hidutil: \(error.localizedDescription)")
            return false
        }
    }
}
