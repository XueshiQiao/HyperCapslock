import SwiftUI
import AppKit

enum SidebarPage: Hashable, CaseIterable {
    case settings, mappings, actions, inputSource, about

    /// Stable, language-independent id stem for accessibility identifiers:
    /// `nav.<axID>` on the sidebar row, `page.<axID>` on the detail root. These
    /// are the contract the XCUITest suite targets — never key tests off visible
    /// (localized) text. Treat like a public API.
    var axID: String {
        switch self {
        case .mappings: return "mappings"
        case .settings: return "settings"
        case .actions: return "actions"
        case .inputSource: return "input_source"
        case .about: return "about"
        }
    }
}

/// Stable identity for a trigger (ForEach id + edit-sheet identity).
func triggerUniqueID(_ t: Trigger) -> String {
    switch t {
    case .singleTapHyper: return "single_tap_hyper"
    case .doubleTapHyper: return "double_tap_hyper"
    case .doubleTapModifier(let m): return "dtm:\(m.rawValue)"
    case .hyperPlusKey(let key, let withShift): return "hyper:\(key):\(withShift ? "s" : "n")"
    }
}

/// A macOS System-Settings-style sidebar row icon: a white SF Symbol on a
/// colored rounded square.
struct SidebarIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(
                LinearGradient(colors: [color.opacity(0.98), color.opacity(0.68)],
                               startPoint: .top, endPoint: .bottom)))
            // Rasterize so the row-selection vibrancy can't tint/blend the tile —
            // keeps the icon its true color on the selected (blue) row.
            .drawingGroup()
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    // Mappings is the primary screen — it opens first and sits at the top.
    @State private var page: SidebarPage? = .mappings

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                sidebarRow(.mappings, loc.t("nav.mappings"), "keyboard.fill", .blue)
                sidebarRow(.actions, loc.t("nav.actions"), "bolt.fill", .orange)
                sidebarRow(.inputSource, loc.t("nav.input_source"), "globe", .green)
                sidebarRow(.settings, loc.t("nav.settings"), "gearshape.fill", .gray)
                sidebarRow(.about, loc.t("nav.about"), "info.circle.fill", .gray)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 215, ideal: 220, max: 240)
            .safeAreaInset(edge: .top, spacing: 0) { brand }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusFooter }
        } detail: {
            Group {
                switch page ?? .mappings {
                case .settings: SettingsPage().accessibilityIdentifier("page.settings")
                case .mappings: MappingsPage().accessibilityIdentifier("page.mappings")
                case .actions: ActionsPage().accessibilityIdentifier("page.actions")
                case .inputSource: InputSourcePage().accessibilityIdentifier("page.input_source")
                case .about: AboutPage().accessibilityIdentifier("page.about")
                }
            }
            // Match System Settings' taller rows (SwiftUI's grouped-Form default is tighter).
            .environment(\.defaultMinListRowHeight, 34)
            // Liveliness: a soft aurora wash behind the detail; hide the Form's own
            // background so the grouped cards float on it (layout unchanged).
            .scrollContentBackground(.hidden)
            .auroraBackground()
            // A leading sidebar toggle, always present on the detail side so the
            // sidebar can be reopened after it's collapsed (NavigationSplitView
            // doesn't provide one on its own). Merges with each page's own toolbar.
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) { Image(systemName: "sidebar.leading") }
                        .help(loc.t("nav.toggle_sidebar"))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let toast = app.toast { toastView(toast).padding(.bottom, 24) }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
    }

    /// Toggle the NavigationSplitView's sidebar by sending the AppKit
    /// `toggleSidebar:` action up the responder chain (the SwiftUI split view is
    /// backed by an NSSplitViewController that handles it).
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func sidebarRow(_ p: SidebarPage, _ title: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 9) {
            SidebarIcon(symbol: symbol, color: color)
            Text(title)
        }
        .padding(.vertical, 2)
        .tag(p)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nav.\(p.axID)")
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("HyperCapslock").font(.system(size: 14, weight: .bold))
                Text("v\(app.appVersion)").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    private var statusFooter: some View {
        HStack(spacing: 7) {
            StatusDot(running: app.isRunning, animate: app.isRunning)
            Text(app.isRunning ? loc.t("status.running") : loc.t("status.paused"))
                .font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    private func toastView(_ toast: AppState.ToastMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(toast.isError ? .red : .green)
            Text(toast.text).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke((toast.isError ? Color.red : Color.green).opacity(0.5), lineWidth: 1))
        .shadow(radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Status dot: breathes in place when running, solid when paused.
struct StatusDot: View {
    let running: Bool
    var animate: Bool = false
    @State private var breathe = false
    private var color: Color { running ? .green : .orange }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .scaleEffect(animate ? (breathe ? 1.0 : 0.72) : 1.0)
            .opacity(animate ? (breathe ? 1.0 : 0.5) : 1.0)
            .frame(width: 12, height: 12)
            .onAppear {
                guard animate else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
                }
            }
    }
}
