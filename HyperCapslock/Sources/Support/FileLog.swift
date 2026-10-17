import Foundation
import os

/// Append-only file logger: `hypercapslock.log` in the app's data dir
/// (`AppEnvironment.appSupportDirectory`, so Dev and Release log separately),
/// `[HYPERCAPS][macOS][ts][LEVEL] msg` lines. Unlike the old `/tmp` path it
/// survives reboots, so it is capped: past `maxBytes` at launch, the file is
/// moved to `hypercapslock.old.log` (replacing the previous one).
final class FileLog: @unchecked Sendable {
    static let shared = FileLog()

    private static let maxBytes: UInt64 = 5 * 1024 * 1024
    let path: String
    private let lock = NSLock()
    private let osLog = Logger(subsystem: "me.xueshi.hypercapslock", category: "engine")

    private init() {
        let dir = AppEnvironment.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("hypercapslock.log")
        path = url.path
        if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64,
           size > Self.maxBytes {
            let old = dir.appendingPathComponent("hypercapslock.old.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
    }

    func info(_ message: String) { log("INFO", message) }
    func warn(_ message: String) { log("WARN", message) }
    func error(_ message: String) { log("ERROR", message) }

    /// Diagnostic detail that fires on ordinary user activity and would
    /// otherwise bury the interesting lines.
    ///
    /// The file is append-only and only trimmed at launch once it passes
    /// `maxBytes`, so anything that ticks along with normal use has to stay
    /// out of it.
    ///
    /// It is still handed to the unified log, but at `debug` level, which macOS
    /// keeps in memory and only captures once debug logging has been switched on
    /// for the subsystem **beforehand**:
    ///
    ///     log stream --predicate 'subsystem == "me.xueshi.hypercapslock"' --level debug
    ///
    /// So treat this as effectively **lost on Release**: starting that stream
    /// after something went wrong will not bring back what already happened. Only
    /// route a line here once the context it carried also appears on a line that
    /// stays in the file (see the `frontmost=` field on the Caps-remap lines).
    func debug(_ message: String) {
        #if DEBUG
        log("DEBUG", message)
        #else
        osLog.debug("\(message, privacy: .public)")
        #endif
    }

    func log(_ level: String, _ message: String) {
        let ts = UInt64(Date().timeIntervalSince1970)
        let line = "[HYPERCAPS][macOS][\(ts)][\(level)] \(message)"
        switch level {
        case "ERROR": osLog.error("\(message, privacy: .public)")
        case "WARN": osLog.warning("\(message, privacy: .public)")
        case "DEBUG": osLog.debug("\(message, privacy: .public)")
        default: osLog.info("\(message, privacy: .public)")
        }

        lock.lock(); defer { lock.unlock() }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
