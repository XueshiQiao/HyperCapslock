import Foundation

/// CapsLock → F18 remap via `hidutil`. This gives proper KeyDown/KeyUp events
/// for CapsLock instead of the unreliable FlagsChanged toggle macOS sends
/// natively, which is what makes Caps usable as a hyper modifier.
enum HidUtil {
    // 0x700000039 = CapsLock usage, 0x70000006D = F18 usage.
    private static let remapPayload =
        #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#
    private static let clearPayload = #"{"UserKeyMapping":[]}"#

    @discardableResult
    static func setupRemap() -> Bool {
        run(["property", "--set", remapPayload], onSuccess: "hidutil remapped CapsLock to F18 successfully.",
            onFail: "hidutil remap failed")
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
