import SwiftUI
import AppKit

enum SidebarPage: Hashable, CaseIterable {
    case settings, mappings, actions, about
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    @State private var page: SidebarPage? = .settings

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label { Text(loc.t("nav.settings")) } icon: { SidebarIcon(symbol: "gearshape.fill", color: .gray) }
                    .tag(SidebarPage.settings)
                Label { Text(loc.t("nav.mappings")) } icon: { SidebarIcon(symbol: "keyboard.fill", color: .blue) }
                    .tag(SidebarPage.mappings)
                Label { Text(loc.t("nav.actions")) } icon: { SidebarIcon(symbol: "bolt.fill", color: .orange) }
                    .tag(SidebarPage.actions)
                Label { Text(loc.t("nav.about")) } icon: { SidebarIcon(symbol: "info.circle.fill", color: .gray) }
                    .tag(SidebarPage.about)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 215, ideal: 220, max: 240)
            .safeAreaInset(edge: .top, spacing: 0) { brand }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusFooter }
        } detail: {
            switch page ?? .settings {
            case .settings: SettingsPage()
            case .mappings: MappingsPage()
            case .actions: ActionsPage()
            case .about: AboutPage()
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let toast = app.toast { toastView(toast).padding(.bottom, 24) }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 0) {
                Text("HyperCapslock").font(.system(size: 13, weight: .bold))
                Text("v\(app.appVersion)").font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
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
