import Foundation
import os

/// Append-only file logger. Keeps the original engine log path
/// (`/tmp/hypercapslock-macos.log`) and `[HYPERCAPS][macOS][ts][LEVEL] msg`
/// line format so existing troubleshooting docs and `tail -f` habits still work.
final class FileLog: @unchecked Sendable {
    static let shared = FileLog()

    private let path = "/tmp/hypercapslock-macos.log"
    private let lock = NSLock()
    private let osLog = Logger(subsystem: "me.xueshi.hypercapslock", category: "engine")

    func info(_ message: String) { log("INFO", message) }
    func warn(_ message: String) { log("WARN", message) }
    func error(_ message: String) { log("ERROR", message) }

    func log(_ level: String, _ message: String) {
        let ts = UInt64(Date().timeIntervalSince1970)
        let line = "[HYPERCAPS][macOS][\(ts)][\(level)] \(message)"
        switch level {
        case "ERROR": osLog.error("\(message, privacy: .public)")
        case "WARN": osLog.warning("\(message, privacy: .public)")
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
