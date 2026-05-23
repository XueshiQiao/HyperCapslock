import AppKit
import UniformTypeIdentifiers

/// A picked application: stable bundle id (used for matching) + display name.
struct AppRef: Identifiable, Equatable {
  var bundleID: String
  var name: String
  var id: String { bundleID }
}

/// Shared `.app` picker, mirroring the `open_app` action's flow.
enum AppChooser {
  @MainActor static func choose() -> AppRef? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK, let url = panel.url,
          let bid = Bundle(url: url)?.bundleIdentifier, !bid.isEmpty else { return nil }
    let display = FileManager.default.displayName(atPath: url.path)
    let name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    return AppRef(bundleID: bid, name: name)
  }

  @MainActor static func icon(_ bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }
}
