import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    #if DEBUG
    @AppStorage(FrontmostAppHud.defaultsKey) private var debugFrontmostHud = false
    #endif

    var body: some View {
        Form {
            Section { statusRow }

            Section(loc.t("perm.label")) {
                LabeledContent {
                    if app.accessibilityGranted {
                        Text(loc.t("perm.granted")).modifier(BadgeStyle(color: .green))
                    } else {
                        Button {
                            Permissions.promptAccessibility()
                            Permissions.openPrivacyPane(.accessibility)
                        } label: {
                            HStack(spacing: 4) { Text(loc.t("perm.not_granted")); Image(systemName: "arrow.right") }
                        }
                        .modifier(BadgeStyle(color: .red))
                    }
                } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: "accessibility", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t("perm.accessibility"))
                            Text(loc.t("perm.macos_hint")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent {
                    Button(loc.t("perm.refresh")) {
                        app.refreshPermissions()
                        app.showToast(loc.t("toast.perm_refreshed"))
                    }
                } label: {
                    iconLabel("arrow.clockwise", .gray, loc.t("perm.refresh_label"))
                }
            }

            Section(loc.t("settings.label")) {
                Toggle(isOn: Binding(
                    get: { app.autostart },
                    set: { _ in
                        do {
                            try app.toggleAutostart()
                            app.showToast(app.autostart ? loc.t("toast.autostart_enabled") : loc.t("toast.autostart_disabled"))
                        } catch { app.showToast(loc.t("toast.autostart_failed"), isError: true) }
                    })) { iconLabel("power", .green, loc.t("settings.autostart")) }
                Toggle(isOn: Binding(
                    get: { config.appConfig.hideDockIcon },
                    set: { v in
                        do { try app.setHideDockIcon(v); app.showToast(v ? loc.t("toast.hide_dock_enabled") : loc.t("toast.hide_dock_disabled")) }
                        catch { app.showToast(loc.t("toast.hide_dock_failed"), isError: true) }
                    })) { iconLabel("dock.rectangle", .indigo, loc.t("settings.hide_dock")) }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(
                        get: { config.appConfig.showWindowOnLaunch },
                        set: { v in
                            do { try app.setShowWindowOnLaunch(v); app.showToast(v ? loc.t("toast.show_window_on_launch_enabled") : loc.t("toast.show_window_on_launch_disabled")) }
                            catch { app.showToast(loc.t("toast.show_window_on_launch_failed"), isError: true) }
                        })) { iconLabel("macwindow", .cyan, loc.t("settings.show_window_on_launch")) }
                        .accessibilityIdentifier("settings.show_window_on_launch")
                    Text(loc.t("settings.show_window_on_launch_hint")).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: Binding(
                    get: { config.appConfig.showHud },
                    set: { v in
                        do { try app.setShowHud(v); app.showToast(v ? loc.t("toast.show_hud_enabled") : loc.t("toast.show_hud_disabled")) }
                        catch { app.showToast(loc.t("toast.show_hud_failed"), isError: true) }
                    })) { iconLabel("bubble.left.fill", .teal, loc.t("settings.show_hud")) }
                if config.appConfig.showHud {
                    LabeledContent {
                        HStack(spacing: 10) {
                            Text(String(format: "%.1fs", Double(config.appConfig.hudDurationMs) / 1000.0))
                                .foregroundStyle(.secondary).font(.callout).monospacedDigit()
                            Slider(value: Binding(get: { Double(config.appConfig.hudDurationMs) },
                                                  set: { try? app.setHudDuration(Int($0)) }),
                                   in: 300...6000, step: 100).frame(width: 160)
                        }
                    } label: {
                        iconLabel("timer", .orange, loc.t("settings.hud_duration"))
                    }
                }
                Toggle(isOn: Binding(
                    get: { config.appConfig.statsShowInline },
                    set: { v in try? app.setStatsShowInline(v) })) {
                    iconLabel("chart.bar.fill", .purple, loc.t("settings.stats_inline"))
                }
                .accessibilityIdentifier("settings.stats_inline")
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(
                        get: { config.appConfig.broadcastCapsHoldForAnyDrag },
                        set: { v in
                            do { try app.setBroadcastCapsHoldForAnyDrag(v); app.showToast(v ? loc.t("toast.anydrag_caps_hold_enabled") : loc.t("toast.anydrag_caps_hold_disabled")) }
                            catch { app.showToast(loc.t("toast.anydrag_caps_hold_failed"), isError: true) }
                        })) {
                        HStack(spacing: 10) {
                            ArtTile(image: Image("AnyDragIcon"))
                            Text(loc.t("settings.anydrag_caps_hold"))
                        }
                    }
                    Text(loc.t("settings.anydrag_caps_hold_hint")).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(config.appConfig.keyRemaps.indices, id: \.self) { i in
                    keyRemapRow(i)
                }
                Button { addKeyRemap() } label: {
                    iconLabel("plus.circle.fill", .pink, loc.t("remap.add"))
                }
                .buttonStyle(.borderless)
                .disabled(config.appConfig.keyRemaps.count >= KeyRemapSource.allCases.count)
                .accessibilityIdentifier("settings.key_remap.add")
            } header: {
                Text(loc.t("remap.label"))
            } footer: {
                Text(loc.t("remap.hint")).font(.caption).foregroundStyle(.secondary)
            }

            Section(loc.t("appearance.label")) {
                Picker(selection: Binding(
                    get: { loc.followsSystem ? LanguageChoice.system : LanguageChoice.fixed(loc.locale) },
                    set: { choice in
                        switch choice {
                        case .system: loc.useSystemLocale()
                        case .fixed(let l): loc.setLocale(l)
                        }
                    })) {
                    Text(loc.t("settings.language_system")).tag(LanguageChoice.system)
                    ForEach(AppLocale.allCases, id: \.self) { l in
                        Text("\(l.flag)  \(l.label)").tag(LanguageChoice.fixed(l))
                    }
                } label: {
                    iconLabel("globe", .blue, loc.t("settings.language"))
                }
                .accessibilityIdentifier("settings.language")
                Picker(selection: Binding(get: { app.themeMode }, set: { app.setTheme($0) })) {
                    Text(loc.t("theme.light_opt")).tag(ThemeMode.light)
                    Text(loc.t("theme.dark_opt")).tag(ThemeMode.dark)
                    Text(loc.t("theme.system_opt")).tag(ThemeMode.system)
                } label: {
                    iconLabel("circle.lefthalf.filled", .purple, loc.t("settings.theme"))
                }
                .pickerStyle(.segmented)
            }

            #if DEBUG
            // Debug-only diagnostics. Compiled out of release builds entirely.
            Section("Debug") {
                Toggle("Show frontmost-app overlay", isOn: $debugFrontmostHud)
                Text("Shows the active app's name + bundle id, bottom-right, for 3s on each switch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: debugFrontmostHud) { _, on in
                if !on { FrontmostAppHud.shared.hideNow() }
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.settings"))
        .toolbar {
            ToolbarItem {
                Button {
                    let wasRunning = app.isRunning
                    withAnimation { app.togglePause() }
                    app.showToast(wasRunning ? loc.t("toast.service_paused") : loc.t("toast.service_resumed"))
                } label: {
                    Label(app.isRunning ? loc.t("status.pause") : loc.t("status.resume"),
                          systemImage: app.isRunning ? "pause.fill" : "play.fill")
                        // Animate the pause.fill ↔ play.fill swap.
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
    }

    /// A settings-row label: a category-colored icon tile + the text.
    private func iconLabel(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) { IconTile(symbol: symbol, color: color); Text(text) }
    }

    // MARK: - Key remapping rows

    /// One editable remap row: source modifier → target function key + remove.
    private func keyRemapRow(_ i: Int) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(
                get: { config.appConfig.keyRemaps[i].source },
                set: { newValue in
                    var copy = config.appConfig.keyRemaps
                    guard copy.indices.contains(i) else { return }
                    copy[i].source = newValue
                    app.setKeyRemaps(copy)
                })) {
                ForEach(availableSources(forRow: i)) { s in
                    Text(loc.t("remap.src.\(s.rawValue)")).tag(s)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("settings.key_remap.row.\(i).source")

            Image(systemName: "arrow.right").foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { config.appConfig.keyRemaps[i].destination },
                set: { newValue in
                    var copy = config.appConfig.keyRemaps
                    guard copy.indices.contains(i) else { return }
                    copy[i].destination = newValue
                    app.setKeyRemaps(copy)
                })) {
                ForEach(availableTargets(forRow: i)) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("settings.key_remap.row.\(i).target")

            Spacer()

            Button {
                var copy = config.appConfig.keyRemaps
                guard copy.indices.contains(i) else { return }
                copy.remove(at: i)
                app.setKeyRemaps(copy)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .accessibilityIdentifier("settings.key_remap.row.\(i).remove")
        }
    }

    /// Source keys still available to row `i` (its own current source, plus any
    /// not used by another row) — so each modifier can be remapped at most once.
    private func availableSources(forRow i: Int) -> [KeyRemapSource] {
        let usedByOthers = Set(config.appConfig.keyRemaps.enumerated()
            .filter { $0.offset != i }.map { $0.element.source })
        return KeyRemapSource.allCases.filter { !usedByOthers.contains($0) }
    }

    /// Target keys still available to row `i` — each function key targeted once.
    private func availableTargets(forRow i: Int) -> [KeyRemapTarget] {
        let usedByOthers = Set(config.appConfig.keyRemaps.enumerated()
            .filter { $0.offset != i }.map { $0.element.destination })
        return KeyRemapTarget.allCases.filter { !usedByOthers.contains($0) }
    }

    /// Append a new remap with the first unused source + target.
    private func addKeyRemap() {
        let remaps = config.appConfig.keyRemaps
        let usedSrc = Set(remaps.map { $0.source })
        let usedDst = Set(remaps.map { $0.destination })
        guard let src = KeyRemapSource.allCases.first(where: { !usedSrc.contains($0) }),
              let dst = KeyRemapTarget.allCases.first(where: { !usedDst.contains($0) }) else { return }
        app.setKeyRemaps(remaps + [KeyRemap(source: src, destination: dst)])
    }

    private var statusRow: some View {
        HStack(spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("HyperCapslock").font(.headline)
                HStack(spacing: 6) {
                    StatusDot(running: app.isRunning)
                    Text(loc.t("status.\(app.status.rawValue)")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
