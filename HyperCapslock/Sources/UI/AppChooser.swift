import AppKit
import SwiftUI
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

// MARK: - App picker popover (running apps, Finder fallback)

/// A button that opens the app picker popover: the running (Dock) apps, plus a
/// "Choose from Finder…" fallback. `browse` is that fallback (defaults to the
/// plain `.app` open panel, which starts in /Applications).
struct AppPickerButton<Label: View>: View {
  var browse: @MainActor () -> AppRef? = { AppChooser.choose() }
  let onPick: (AppRef) -> Void
  @ViewBuilder let label: () -> Label
  @State private var showing = false

  var body: some View {
    Button { showing = true } label: { label() }
      .popover(isPresented: $showing, arrowEdge: .bottom) {
        AppPickerPopover(browse: browse) { ref in
          showing = false
          onPick(ref)
        }
      }
  }
}

struct AppPickerPopover: View {
  @EnvironmentObject var loc: LocalizationManager
  let browse: @MainActor () -> AppRef?
  let onPick: (AppRef) -> Void

  @State private var running: [AppRef] = []

  var body: some View {
    VStack(spacing: 0) {
      List {
        Section(loc.t("apppicker.running")) {
          ForEach(running) { row($0) }
        }
      }
      .listStyle(.inset)
      .accessibilityIdentifier("app_picker.list")
      Divider()
      HStack {
        Button {
          if let picked = browse() { onPick(picked) }
        } label: { Label(loc.t("apppicker.browse"), systemImage: "folder") }
          .accessibilityIdentifier("app_picker.browse")
        Spacer()
      }
      .padding(10)
    }
    .frame(width: 300, height: 400)
    .onAppear { running = Self.runningApps() }
  }

  /// Regular (Dock) apps, de-duplicated by bundle id, sorted by name.
  private static func runningApps() -> [AppRef] {
    var seen = Set<String>()
    return NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { app -> AppRef? in
        guard let bid = app.bundleIdentifier, !bid.isEmpty, seen.insert(bid.lowercased()).inserted else { return nil }
        return AppRef(bundleID: bid, name: app.localizedName ?? bid)
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private func row(_ a: AppRef) -> some View {
    Button { onPick(a) } label: {
      HStack(spacing: 8) {
        if let icon = AppChooser.icon(a.bundleID) {
          Image(nsImage: icon).resizable().frame(width: 18, height: 18)
        }
        Text(a.name)
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("app_picker.row.\(a.bundleID.lowercased())")
  }
}
