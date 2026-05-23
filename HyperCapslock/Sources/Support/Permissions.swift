import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

/// Accessibility + Input Monitoring TCC checks and System Settings deep links.
enum Permissions {
    enum Status: String { case granted, notGranted = "not_granted" }

    static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var isInputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    enum Pane { case accessibility, inputMonitoring }

    static func openPrivacyPane(_ pane: Pane) {
        let urlString: String
        switch pane {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
