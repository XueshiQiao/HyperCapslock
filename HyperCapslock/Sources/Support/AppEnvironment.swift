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
}
