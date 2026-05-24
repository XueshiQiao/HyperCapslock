import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

/// Accessibility TCC check and System Settings deep link.
///
/// The app's CGEventTap is an active `.defaultTap`, which macOS gates on
/// Accessibility only — Input Monitoring is for `.listenOnly` taps, which we
/// don't use, so it is intentionally not requested or checked.
enum Permissions {
    enum Status: String { case granted, notGranted = "not_granted" }

    static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    enum Pane { case accessibility }

    static func openPrivacyPane(_ pane: Pane) {
        let urlString: String
        switch pane {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
