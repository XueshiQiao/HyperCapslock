import Foundation
import Sparkle

/// Sparkle auto-update wrapper. Reads `SUFeedURL` (the appcast published as a
/// GitHub Release asset) and `SUPublicEDKey` from Info.plist. Replaces the
/// Tauri updater. Starts the background update checker at launch.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    /// User-initiated check (shows Sparkle's standard UI for available/no-update/error).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
