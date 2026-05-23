import SwiftUI
import AppKit

enum SidebarPage: Hashable, CaseIterable {
    case settings, mappings, actions, about
}

/// Stable identity for a trigger (used as ForEach id and edit-sheet identity).
func triggerUniqueID(_ t: Trigger) -> String {
    switch t {
    case .singleTapHyper: return "single_tap_hyper"
    case .doubleTapHyper: return "double_tap_hyper"
    case .doubleTapModifier(let m): return "dtm:\(m.rawValue)"
    case .hyperPlusKey(let key, let withShift): return "hyper:\(key):\(withShift ? "s" : "n")"
    }
}

/// App brand gradient (Design B).
let brandGradient = LinearGradient(colors: [Color(red: 0.23, green: 0.51, blue: 0.96),
                                            Color(red: 0.55, green: 0.36, blue: 0.96)],
                                   startPoint: .leading, endPoint: .trailing)

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    @State private var page: SidebarPage = .settings

    var body: some View {
        NavigationSplitView {
            SidebarView(page: $page)
                .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 240)
        } detail: {
            ZStack {
                switch page {
                case .settings: SettingsPage()
                case .mappings: MappingsPage()
                case .actions: ActionsPage()
                case .about: AboutPage()
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 720, minHeight: 560)
        // Appearance is driven entirely by NSApp.appearance (set in AppState.setTheme):
        // light/dark force it, system clears it to follow the OS. We deliberately do
        // NOT use .preferredColorScheme — combining the two left "system" in a broken
        // half-state.
        .overlay(alignment: .bottom) {
            if let toast = app.toast { toastView(toast).padding(.bottom, 24) }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
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

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @Binding var page: SidebarPage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            brand
            Divider().padding(.vertical, 6)
            navItem(.settings, loc.t("nav.settings"), "gearshape.fill")
            navItem(.mappings, loc.t("nav.mappings"), "keyboard.fill")
            navItem(.actions, loc.t("nav.actions"), "bolt.fill")
            navItem(.about, loc.t("nav.about"), "info.circle.fill")
            Spacer()
            statusFooter
        }
        .padding(10)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 0) {
                Text("HyperCapslock").font(.system(size: 13, weight: .bold))
                Text("v\(app.appVersion)").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6).padding(.top, 4)
    }

    private func navItem(_ p: SidebarPage, _ title: String, _ icon: String) -> some View {
        let selected = page == p
        return Button { page = p } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13))
                    .foregroundColor(selected ? .white : .secondary)
                    .frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                    .foregroundColor(selected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background {
                if selected { RoundedRectangle(cornerRadius: 7).fill(brandGradient) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusFooter: some View {
        HStack(spacing: 7) {
            StatusDot(running: app.isRunning, animate: app.isRunning)
            Text(app.isRunning ? loc.t("status.running") : loc.t("status.paused"))
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.1)))
    }
}

/// Status indicator. When `animate` is true it breathes (scales up/down in
/// place); otherwise it's a solid dot. Centered scale + a fixed layout box keep
/// it pulsing in place (no sliding).
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
            .frame(width: 12, height: 12)   // fixed box so scaling never shifts neighbors
            .onAppear {
                guard animate else { return }
                // Defer one runloop so the entrance layout has settled, then
                // start ONLY the breathe animation (not the view's geometry).
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        breathe = true
                    }
                }
            }
    }
}

/// Shared page scaffold: gradient title + scrollable content column.
struct PageScaffold<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(title).font(.system(size: 22, weight: .bold))
                        .foregroundStyle(brandGradient)
                    Spacer()
                    if let trailing { trailing }
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
