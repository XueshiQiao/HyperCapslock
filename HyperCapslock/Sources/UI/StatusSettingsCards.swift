import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        PageScaffold(title: loc.t("nav.settings")) {
            statusCard
            PermissionsSection()
            generalSection
            appearanceSection
        }
    }

    private var statusCard: some View {
        Card {
            HStack(spacing: 13) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("HyperCapslock").font(.system(size: 15, weight: .bold))
                    HStack(spacing: 6) {
                        StatusDot(running: app.isRunning, animate: app.isRunning)
                        Text(loc.t("status.\(app.status.rawValue)"))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    let wasRunning = app.isRunning
                    app.togglePause()
                    app.showToast(wasRunning ? loc.t("toast.service_paused") : loc.t("toast.service_resumed"))
                } label: {
                    Text(app.isRunning ? loc.t("status.pause") : loc.t("status.resume"))
                        .frame(minWidth: 60)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            .padding(14)
        }
    }

    private var generalSection: some View {
        SettingsSection(title: loc.t("settings.label")) {
            SettingsRow(label: loc.t("settings.autostart"), isFirst: true) {
                Toggle("", isOn: Binding(get: { app.autostart }, set: { _ in
                    do {
                        try app.toggleAutostart()
                        app.showToast(app.autostart ? loc.t("toast.autostart_enabled") : loc.t("toast.autostart_disabled"))
                    } catch { app.showToast(loc.t("toast.autostart_failed"), isError: true) }
                })).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(label: loc.t("settings.hide_dock")) {
                Toggle("", isOn: Binding(get: { config.appConfig.hideDockIcon }, set: { v in
                    do {
                        try app.setHideDockIcon(v)
                        app.showToast(v ? loc.t("toast.hide_dock_enabled") : loc.t("toast.hide_dock_disabled"))
                    } catch { app.showToast(loc.t("toast.hide_dock_failed"), isError: true) }
                })).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(label: loc.t("settings.show_hud")) {
                Toggle("", isOn: Binding(get: { config.appConfig.showHud }, set: { v in
                    do {
                        try app.setShowHud(v)
                        app.showToast(v ? loc.t("toast.show_hud_enabled") : loc.t("toast.show_hud_disabled"))
                    } catch { app.showToast(loc.t("toast.show_hud_failed"), isError: true) }
                })).labelsHidden().toggleStyle(.switch)
            }
            if config.appConfig.showHud {
                SettingsRow(label: loc.t("settings.hud_duration"),
                            sublabel: String(format: "%.1fs", Double(config.appConfig.hudDurationMs) / 1000.0)) {
                    Slider(value: Binding(get: { Double(config.appConfig.hudDurationMs) },
                                          set: { try? app.setHudDuration(Int($0)) }),
                           in: 300...6000, step: 100).frame(width: 130)
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: loc.t("appearance.label")) {
            SettingsRow(label: loc.t("settings.language"), isFirst: true) {
                Picker("", selection: Binding(get: { loc.locale }, set: { loc.setLocale($0) })) {
                    ForEach(AppLocale.allCases, id: \.self) { l in
                        Text("\(l.flag)  \(l.label)").tag(l)
                    }
                }.labelsHidden().frame(width: 150)
            }
            SettingsRow(label: loc.t("settings.theme")) {
                Picker("", selection: Binding(get: { app.themeMode }, set: { app.setTheme($0) })) {
                    Text(loc.t("theme.light_opt")).tag(ThemeMode.light)
                    Text(loc.t("theme.dark_opt")).tag(ThemeMode.dark)
                    Text(loc.t("theme.system_opt")).tag(ThemeMode.system)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
            }
        }
    }
}
