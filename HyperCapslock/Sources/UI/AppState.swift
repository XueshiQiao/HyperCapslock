import Foundation
import AppKit
import SwiftUI
import Combine

/// Central UI state, bridging SwiftUI to the engine, config store, permissions,
/// autostart, and activation policy. Mirrors the state the React `App.tsx` held.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum ServiceStatus: String { case initializing, running, paused, error }

    @Published var status: ServiceStatus = .initializing
    @Published var accessibilityGranted = false
    @Published var permissionsResolved = false   // false until first refresh completes
    @Published var autostart = false
    @Published var permissionsExpandedManually: Bool? = nil
    @Published var toast: ToastMessage?

    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private var toastClearWork: DispatchWorkItem?

    func showToast(_ text: String, isError: Bool = false) {
        toast = ToastMessage(text: text, isError: isError)
        toastClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    let config = ConfigStore.shared
    let loc = LocalizationManager.shared
    let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    var isRunning: Bool { status == .running }
    var isPaused: Bool { status == .paused }

    private init() {}

    // MARK: - Bootstrap

    func bootstrap() {
        config.load()
        FileLog.shared.info("bootstrap: \(config.mappings.count) mappings, \(config.customActions.count) custom actions; appConfig=\(config.appConfig)")
        applyHudSettings()
        applyActivationPolicy(hide: config.appConfig.hideDockIcon)
        applyAppearance(config.appConfig.themeMode)
        autostart = LaunchAtLogin.isEnabled
        status = .running
        EngineState.shared.isPaused = false
        refreshPermissions()
    }

    private func applyHudSettings() {
        HudCenter.shared.updateSettings(enabled: config.appConfig.showHud,
                                        durationMs: config.appConfig.hudDurationMs)
        FileLog.shared.info("HUD settings applied: enabled=\(config.appConfig.showHud) duration=\(config.appConfig.hudDurationMs)ms")
    }

    // MARK: - Theme (light / dark / system)

    var themeMode: ThemeMode { config.appConfig.themeMode }

    /// For SwiftUI `.preferredColorScheme` — nil means follow the system.
    var colorScheme: ColorScheme? {
        switch config.appConfig.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    func setTheme(_ mode: ThemeMode) {
        do {
            try config.setThemeMode(mode)
            applyAppearance(mode)   // only apply the appearance we actually persisted
            objectWillChange.send()
        } catch {
            FileLog.shared.error("Failed to persist theme: \(error) — keeping previous appearance.")
        }
    }

    private func applyAppearance(_ mode: ThemeMode) {
        switch mode {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    // MARK: - Service pause/resume

    func setPaused(_ paused: Bool) {
        EngineState.shared.isPaused = paused
        status = paused ? .paused : .running
        FileLog.shared.info("[STATE] Service \(paused ? "paused" : "resumed")")
    }

    func togglePause() { setPaused(!isPaused) }

    // MARK: - Settings toggles

    func setHideDockIcon(_ hide: Bool) throws {
        try config.setHideDockIcon(hide)
        applyActivationPolicy(hide: hide)
        // Switching policy can drop focus; reassert the window.
        MainWindowController.shared?.show()
    }

    func setShowHud(_ show: Bool) throws {
        try config.setShowHud(show)
        applyHudSettings()
    }

    func setHudDuration(_ ms: Int) throws {
        try config.setHudDuration(ms)
        applyHudSettings()
    }

    func toggleAutostart() throws {
        let next = !autostart
        try LaunchAtLogin.setEnabled(next)
        autostart = next
    }

    private func applyActivationPolicy(hide: Bool) {
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }

    // MARK: - Permissions

    func refreshPermissions() {
        accessibilityGranted = Permissions.isAccessibilityGranted
        permissionsResolved = true
    }

    // MARK: - Mapping operations (wrap ConfigStore, surface errors as messages)

    func upsertMapping(trigger: Trigger, actionId: String?, inlineAction: ActionConfig? = nil, bindings: [MappingBinding] = []) throws {
        try config.upsert(trigger: trigger, actionId: actionId, inlineAction: inlineAction, bindings: bindings)
    }

    func removeMapping(_ trigger: Trigger) {
        config.remove(trigger: trigger)
    }

    // MARK: - Custom action operations

    @discardableResult
    func addCustomAction(name: String, config cfg: ActionConfig) throws -> Action {
        try config.addCustomAction(name: name, config: cfg)
    }

    func updateCustomAction(_ action: Action) throws {
        try config.updateCustomAction(action)
    }

    func removeCustomAction(id: String) throws {
        try config.removeCustomAction(id: id)
    }
}
