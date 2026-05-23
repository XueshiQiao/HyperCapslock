import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.t("perm.accessibility"))
                        Text(loc.t("perm.macos_hint")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent(loc.t("perm.refresh_label")) {
                    Button(loc.t("perm.refresh")) {
                        app.refreshPermissions()
                        app.showToast(loc.t("toast.perm_refreshed"))
                    }
                }
            }

            Section(loc.t("settings.label")) {
                Toggle(loc.t("settings.autostart"), isOn: Binding(
                    get: { app.autostart },
                    set: { _ in
                        do {
                            try app.toggleAutostart()
                            app.showToast(app.autostart ? loc.t("toast.autostart_enabled") : loc.t("toast.autostart_disabled"))
                        } catch { app.showToast(loc.t("toast.autostart_failed"), isError: true) }
                    }))
                Toggle(loc.t("settings.hide_dock"), isOn: Binding(
                    get: { config.appConfig.hideDockIcon },
                    set: { v in
                        do { try app.setHideDockIcon(v); app.showToast(v ? loc.t("toast.hide_dock_enabled") : loc.t("toast.hide_dock_disabled")) }
                        catch { app.showToast(loc.t("toast.hide_dock_failed"), isError: true) }
                    }))
                Toggle(loc.t("settings.show_hud"), isOn: Binding(
                    get: { config.appConfig.showHud },
                    set: { v in
                        do { try app.setShowHud(v); app.showToast(v ? loc.t("toast.show_hud_enabled") : loc.t("toast.show_hud_disabled")) }
                        catch { app.showToast(loc.t("toast.show_hud_failed"), isError: true) }
                    }))
                if config.appConfig.showHud {
                    LabeledContent(loc.t("settings.hud_duration")) {
                        HStack(spacing: 10) {
                            Text(String(format: "%.1fs", Double(config.appConfig.hudDurationMs) / 1000.0))
                                .foregroundStyle(.secondary).font(.callout).monospacedDigit()
                            Slider(value: Binding(get: { Double(config.appConfig.hudDurationMs) },
                                                  set: { try? app.setHudDuration(Int($0)) }),
                                   in: 300...6000, step: 100).frame(width: 160)
                        }
                    }
                }
            }

            Section(loc.t("appearance.label")) {
                Picker(loc.t("settings.language"), selection: Binding(get: { loc.locale }, set: { loc.setLocale($0) })) {
                    ForEach(AppLocale.allCases, id: \.self) { l in Text("\(l.flag)  \(l.label)").tag(l) }
                }
                Picker(loc.t("settings.theme"), selection: Binding(get: { app.themeMode }, set: { app.setTheme($0) })) {
                    Text(loc.t("theme.light_opt")).tag(ThemeMode.light)
                    Text(loc.t("theme.dark_opt")).tag(ThemeMode.dark)
                    Text(loc.t("theme.system_opt")).tag(ThemeMode.system)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.settings"))
    }

    private var statusRow: some View {
        HStack(spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("HyperCapslock").font(.headline)
                HStack(spacing: 6) {
                    StatusDot(running: app.isRunning, animate: app.isRunning)
                    Text(loc.t("status.\(app.status.rawValue)")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                let wasRunning = app.isRunning
                app.togglePause()
                app.showToast(wasRunning ? loc.t("toast.service_paused") : loc.t("toast.service_resumed"))
            } label: {
                Text(app.isRunning ? loc.t("status.pause") : loc.t("status.resume")).frame(minWidth: 56)
            }
        }
        .padding(.vertical, 6)
    }
}
