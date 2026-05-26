import SwiftUI

/// "Input Source" page: pick a reliability workaround for switching to a CJKV
/// IME via a `Caps+key → input source` mapping. Mirrors Input Source Pro's
/// troubleshooting UI (a radio group of methods); default is "Do Nothing".
struct InputSourcePage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    /// Whether the system "Select previous input source" shortcut is available
    /// (gates the Shortcut-Simulation warning). Held in state so the toolbar
    /// Refresh button can re-check it without a relaunch.
    @State private var shortcutAvailable = InputSourceFix.isPreviousInputSourceShortcutAvailable

    private var strategyBinding: Binding<CJKVFixStrategy> {
        Binding(
            get: { config.appConfig.cjkvFixStrategy },
            set: { newValue in
                do { try app.setCJKVFixStrategy(newValue) }
                catch { app.showToast(loc.t("toast.is_strategy_failed"), isError: true) }
            })
    }

    var body: some View {
        Form {
            Section {
                Text(loc.t("is.fix_desc"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("", selection: strategyBinding) {
                    ForEach(CJKVFixStrategy.allCases, id: \.self) { strategy in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc.t(nameKey(strategy)))
                            Text(loc.t(descKey(strategy)))
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                        .tag(strategy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                if config.appConfig.cjkvFixStrategy == .shortcutSimulation && !shortcutAvailable {
                    Label(loc.t("is.shortcut_unavailable"), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(loc.t("is.fix_title"))
            } footer: {
                Text(loc.t("is.attribution")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.input_source"))
        // A toolbar item keeps this page's title bar height consistent with the
        // others (no layout jump when navigating in), and re-checks system state.
        .toolbar {
            ToolbarItem {
                Button { shortcutAvailable = InputSourceFix.isPreviousInputSourceShortcutAvailable } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(loc.t("is.refresh"))
            }
        }
        .onAppear { shortcutAvailable = InputSourceFix.isPreviousInputSourceShortcutAvailable }
    }

    private func nameKey(_ s: CJKVFixStrategy) -> String {
        switch s {
        case .none: return "is.method_none"
        case .shortcutSimulation: return "is.method_shortcut"
        case .switchingFocus: return "is.method_focus"
        }
    }

    private func descKey(_ s: CJKVFixStrategy) -> String {
        switch s {
        case .none: return "is.method_none_desc"
        case .shortcutSimulation: return "is.method_shortcut_desc"
        case .switchingFocus: return "is.method_focus_desc"
        }
    }
}
