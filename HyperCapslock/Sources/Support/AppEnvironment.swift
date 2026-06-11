import Foundation

/// Process-wide environment flags derived from launch arguments / env vars.
enum AppEnvironment {
    /// True when the app is launched by the XCUITest suite (`-uitest`, or the
    /// `HC_UITEST=1` environment variable). In this mode the app MUST NOT install
    /// the global keyboard hook / `hidutil` CapsLock→F18 remap (tests must never
    /// grab the host keyboard) and MUST use an isolated temp config dir (see
    /// `ConfigStore.appDataDir`) so it never touches the user's real config.
    static let isUITest: Bool =
        CommandLine.arguments.contains("-uitest")
        || ProcessInfo.processInfo.environment["HC_UITEST"] == "1"

    /// The app's per-process Application Support directory: an isolated temp dir
    /// under `-uitest` (so tests never touch the user's data), else
    /// `…/Application Support/<bundle id>`. Single source of truth for the data
    /// directory — both `ConfigStore` and `UsageStats` resolve their files from
    /// here so the path (and the uitest isolation) can never drift between them.
    static var appSupportDirectory: URL {
        if isUITest {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("hypercapslock-uitest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let bundleID = Bundle.main.bundleIdentifier ?? "me.xueshi.hypercapslock"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }
}
