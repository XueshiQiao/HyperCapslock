import SwiftUI

struct StatusCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager

    private var dotColor: Color {
        switch app.status {
        case .running: return .green
        case .paused: return .orange
        default: return .red
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle().fill(dotColor).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.t("status.label").uppercased())
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                        Text(loc.t("status.\(app.status.rawValue)"))
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(dotColor)
                    }
                    Spacer()
                }
                Button {
                    let wasRunning = app.isRunning
                    app.togglePause()
                    app.showToast(wasRunning ? loc.t("toast.service_paused") : loc.t("toast.service_resumed"))
                } label: {
                    HStack {
                        Image(systemName: app.isRunning ? "pause.circle" : "play.circle")
                        Text(app.isRunning ? loc.t("status.pause") : loc.t("status.resume"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(app.isRunning ? .secondary : .blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc.t("settings.label").uppercased())
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)

                toggleRow(loc.t("settings.autostart"), isOn: app.autostart) {
                    do {
                        try app.toggleAutostart()
                        app.showToast(app.autostart ? loc.t("toast.autostart_enabled") : loc.t("toast.autostart_disabled"))
                    } catch {
                        app.showToast(loc.t("toast.autostart_failed"), isError: true)
                    }
                }
                toggleRow(loc.t("settings.hide_dock"), isOn: config.appConfig.hideDockIcon) {
                    let next = !config.appConfig.hideDockIcon
                    do {
                        try app.setHideDockIcon(next)
                        app.showToast(next ? loc.t("toast.hide_dock_enabled") : loc.t("toast.hide_dock_disabled"))
                    } catch {
                        app.showToast(loc.t("toast.hide_dock_failed"), isError: true)
                    }
                }
                toggleRow(loc.t("settings.show_hud"), isOn: config.appConfig.showHud) {
                    let next = !config.appConfig.showHud
                    do {
                        try app.setShowHud(next)
                        app.showToast(next ? loc.t("toast.show_hud_enabled") : loc.t("toast.show_hud_disabled"))
                    } catch {
                        app.showToast(loc.t("toast.show_hud_failed"), isError: true)
                    }
                }
                if config.appConfig.showHud {
                    hudDurationRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleRow(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var hudDurationRow: some View {
        HStack(spacing: 10) {
            Text("\(loc.t("settings.hud_duration"))  (\(String(format: "%.1f", Double(config.appConfig.hudDurationMs) / 1000.0))s)")
                .font(.system(size: 13, weight: .medium)).fixedSize()
            Slider(
                value: Binding(
                    get: { Double(config.appConfig.hudDurationMs) },
                    set: { try? app.setHudDuration(Int($0)) }
                ),
                in: 300...6000, step: 100
            )
            .frame(width: 120)
        }
    }
}
