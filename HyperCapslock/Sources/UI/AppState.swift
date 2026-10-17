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
    private var cancellables = Set<AnyCancellable>()

    func showToast(_ text: String, isError: Bool = false) {
        toast = ToastMessage(text: text, isError: isError)
        toastClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    let config = ConfigStore.shared
    let loc = LocalizationManager.shared

    /// The AnyDrag integration plugin. Held while the setting is enabled and
    /// registered with `CapsHoldCenter`; nil otherwise. Its existence == the
    /// setting being on (so the ping responder is active exactly then). This is
    /// the only AppState member that touches the AnyDrag integration.
    private var anyDragBridge: AnyDragCapsHoldBridge?
    let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    var isRunning: Bool { status == .running }
    var isPaused: Bool { status == .paused }

    private init() {}

    // MARK: - Bootstrap

    func bootstrap() {
        config.load()
        // Load before the keyboard hook installs, so the first recorded press
        // accumulates onto the persisted history instead of a blank slate.
        UsageStats.shared.load()
        FileLog.shared.info("bootstrap: \(config.mappings.count) mappings, \(config.customActions.count) custom actions; appConfig=\(config.appConfig)")
        applyHudSettings()
        applyDoubleTapWindow()
        applyInputSourceSettings()
        if !AppEnvironment.isUITest {
            // Lock first: a watchdog of a just-dead instance may be mid-cleanup,
            // and our remap must land after it, not be wiped by it.
            CapsLockWatchdog.holdInstanceLock()
            CapsLockWatchdog.spawn()
        }
        applyKeyRemaps()
        applyActivationPolicy(hide: config.appConfig.hideDockIcon)
        applyAppearance(config.appConfig.themeMode)
        autostart = LaunchAtLogin.isEnabled
        status = .running
        EngineState.shared.isPaused = false
        applyAnyDragIntegration(config.appConfig.broadcastCapsHoldForAnyDrag)
        observeSecureInput()
        observeCapsLockHandBackEvents()
        refreshPermissions()
    }

    private func applyHudSettings() {
        HudCenter.shared.updateSettings(enabled: config.appConfig.showHud,
                                        durationMs: config.appConfig.hudDurationMs)
        FileLog.shared.info("HUD settings applied: enabled=\(config.appConfig.showHud) duration=\(config.appConfig.hudDurationMs)ms")
    }

    /// Push the persisted double-tap window into the engine's live state (the
    /// single source of truth the tap thread reads). Called at launch and after
    /// each slider change so the new value takes effect immediately.
    private func applyDoubleTapWindow() {
        EngineState.shared.doubleTapWindowMs = UInt64(config.appConfig.doubleTapWindowMs)
        FileLog.shared.info("Double-tap window applied: \(config.appConfig.doubleTapWindowMs)ms")
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
        if paused {
            // Paused → the tap returns early, so a chord mid-hold would never see
            // its key-up. Release everything (esp. a held push-to-talk modifier)
            // and drop the stale Caps-held state so resume starts clean. Routed
            // through the tap thread so it can't race a chord key-down in flight.
            KeyboardHook.shared.releaseHeldChordsSerialized()
            // End the Caps hold (clears the held state and fires its end side
            // effect) so pausing mid-hold leaves nothing latched.
            endCapsHold()
        }
        status = paused ? .paused : .running
        FileLog.shared.info("[STATE] Service \(paused ? "paused" : "resumed")")
        // Paused, the tap ignores F18 — give the user their real CapsLock back.
        setCapsLockHandBack(.paused, paused)
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

    var doubleTapWindowMs: Int { config.appConfig.doubleTapWindowMs }

    /// Persist the new double-tap window and push it into the engine immediately
    /// (no relaunch needed).
    func setDoubleTapWindow(_ ms: Int) throws {
        try config.setDoubleTapWindow(ms)
        applyDoubleTapWindow()
    }

    var cjkvFixStrategy: CJKVFixStrategy { config.appConfig.cjkvFixStrategy }

    func setCJKVFixStrategy(_ strategy: CJKVFixStrategy) throws {
        try config.setCJKVFixStrategy(strategy)
        applyInputSourceSettings()
    }

    var broadcastCapsHoldForAnyDrag: Bool { config.appConfig.broadcastCapsHoldForAnyDrag }

    func setBroadcastCapsHoldForAnyDrag(_ on: Bool) throws {
        try config.setBroadcastCapsHoldForAnyDrag(on)
        applyAnyDragIntegration(on)
    }

    /// Install or tear down the AnyDrag integration plugin. Installing it into
    /// `CapsHoldCenter` both starts broadcasting the hold lifecycle and (via the
    /// bridge) answers AnyDrag's liveness pings. The hub reconciles a mid-hold
    /// install/remove on its own (it fires `capsHoldBegan`/`capsHoldEnded` to the
    /// freshly added/removed plugin), so flipping this while CapsLock is held
    /// arms/disarms AnyDrag correctly with no special-casing here.
    private func applyAnyDragIntegration(_ on: Bool) {
        if on {
            guard anyDragBridge == nil else { return }
            let bridge = AnyDragCapsHoldBridge()
            anyDragBridge = bridge
            CapsHoldCenter.shared.add(bridge)
        } else if let bridge = anyDragBridge {
            CapsHoldCenter.shared.remove(bridge)
            anyDragBridge = nil
        }
    }

    var mappingsViewStyle: MappingsViewStyle { config.appConfig.mappingsViewStyle }

    /// Pure presentation toggle — just persist it; the Mappings page re-renders
    /// off the published `appConfig`. No engine/runtime side effects.
    func setMappingsViewStyle(_ style: MappingsViewStyle) throws {
        try config.setMappingsViewStyle(style)
    }

    var statsShowInline: Bool { config.appConfig.statsShowInline }

    /// Pure presentation toggle for the Mappings-page inline press counts.
    func setStatsShowInline(_ on: Bool) throws {
        try config.setStatsShowInline(on)
    }

    var showWindowOnLaunch: Bool { config.appConfig.showWindowOnLaunch }

    /// Whether the main window auto-shows at launch. Just persist it — there's no
    /// runtime side effect; it's read by `AppDelegate` on the next launch.
    func setShowWindowOnLaunch(_ on: Bool) throws {
        try config.setShowWindowOnLaunch(on)
    }

    var analyticsEnabled: Bool { config.appConfig.analyticsEnabled }

    /// Persist the anonymous-analytics opt-out and apply it live: flipping this
    /// off stops all events immediately (and never initialized the SDK if it was
    /// off at launch); flipping it on starts sending from now.
    func setAnalyticsEnabled(_ on: Bool) throws {
        try config.setAnalyticsEnabled(on)
        Analytics.shared.setEnabled(on)
    }

    private func applyInputSourceSettings() {
        InputSourceController.setFixStrategy(config.appConfig.cjkvFixStrategy)
        FileLog.shared.info("Input-source fix strategy applied: \(config.appConfig.cjkvFixStrategy.rawValue)")
    }

    // MARK: - Key remapping (hidutil)

    var keyRemaps: [KeyRemap] { config.appConfig.keyRemaps }

    /// Persist a new remap list and re-apply it to the live `hidutil` mapping.
    /// Errors surface as a toast (and a log line) rather than throwing, to keep
    /// the settings UI simple.
    func setKeyRemaps(_ remaps: [KeyRemap]) {
        let prev = config.appConfig.keyRemaps
        do {
            try config.setKeyRemaps(remaps)
        } catch {
            FileLog.shared.error("Failed to persist key remaps: \(error)")
            showToast(loc.t("toast.remap_failed"), isError: true)
            return
        }
        // If hidutil rejects the new mapping the live keyboard is unchanged (a
        // failed `--set` is atomic), so roll the config back to match reality
        // instead of leaving the UI claiming a remap that never took effect.
        // Carry the current hand-back state through, or editing remaps while a
        // password prompt is open (or while paused) would quietly re-arm CapsLock→F18.
        if !applyKeyRemaps(capsLockRemap: capsLockHandBackReasons.isEmpty) {
            try? config.setKeyRemaps(prev)
            showToast(loc.t("toast.remap_failed"), isError: true)
        }
    }

    /// (Re)apply the base CapsLock→F18 remap plus the user remaps via hidutil.
    /// This is the single owner of the live `UserKeyMapping` (KeyboardHook.start
    /// no longer touches it), so a settings edit and launch never clobber one
    /// another. Skipped under -uitest, which must never touch global hidutil state.
    /// Returns whether the apply succeeded (always true under -uitest).
    @discardableResult
    private func applyKeyRemaps(capsLockRemap: Bool = true) -> Bool {
        guard !AppEnvironment.isUITest else { return true }
        let ok = HidUtil.setupRemap(extra: config.appConfig.keyRemaps, capsLock: capsLockRemap)
        if !ok {
            FileLog.shared.warn("hidutil remap apply failed — CapsLock / key remaps may be unreliable.")
        }
        return ok
    }

    // MARK: - Handing CapsLock back to macOS

    /// Why the physical CapsLock must currently behave natively. Whenever this is
    /// non-empty the CapsLock→F18 hidutil remap is removed (user remaps stay).
    ///
    /// The remap lives in the HID layer, below every app, so whenever the tap
    /// can't turn F18 back into a CapsLock toggle the physical key becomes
    /// unable to change the CapsLock state *at all*. Land on a password prompt
    /// with capitals already on and there is no way out but holding Shift for
    /// every character — and on the lock screen after waking from sleep you are
    /// stuck there. Each reason below is such a window. The hyper key is dead
    /// (or unwanted) for its duration anyway, so nothing is lost.
    enum CapsLockHandBackReason: String {
        case secureInput = "secure_input"     // tap is deaf to key events
        case paused                           // tap ignores F18 on purpose
        case screenLocked = "screen_locked"   // lock screen / login prompt
        case screenSaver = "screen_saver"     // may end in a password prompt
        case asleep                           // remove BEFORE sleep: wake lands on the lock screen
        case sessionInactive = "session_inactive" // fast user switching away
    }
    private(set) var capsLockHandBackReasons: Set<CapsLockHandBackReason> = []
    private var handBackObservers: [(NotificationCenter, NSObjectProtocol)] = []

    private func setCapsLockHandBack(_ reason: CapsLockHandBackReason, _ on: Bool) {
        let before = capsLockHandBackReasons.isEmpty
        if on { capsLockHandBackReasons.insert(reason) } else { capsLockHandBackReasons.remove(reason) }
        FileLog.shared.info("CapsLock hand-back \(reason.rawValue)=\(on) → reasons=\(capsLockHandBackReasons.map(\.rawValue).sorted())")
        guard capsLockHandBackReasons.isEmpty != before else { return }
        reconcileCapsLockRemap()
    }

    /// Install or remove CapsLock→F18 to match `capsLockHandBackReasons`.
    private func reconcileCapsLockRemap() {
        let want = capsLockHandBackReasons.isEmpty
        if !want {
            // The tap may not see the key-up of a hold or chord in progress
            // (same reasoning as the tap-disabled path). Let go of everything
            // before the remap changes underneath it.
            endCapsHold()
            KeyboardHook.shared.releaseHeldChordsSerialized()
        }
        let ok = applyKeyRemaps(capsLockRemap: want)
        // Only on success: a failed --set leaves the live mapping untouched, and
        // the tap's swallow rule has to track what the keyboard actually does,
        // not what we asked for.
        if ok { EngineState.shared.capsLockRemapActive = want }
        FileLog.shared.info("CapsLock→F18 remap \(want ? "restored" : "REMOVED so the physical key toggles CapsLock natively") (hidutil ok=\(ok)).")
    }

    private func observeSecureInput() {
        SecureInputMonitor.shared.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main) // main queue drains in every run-loop mode
            .sink { [weak self] active in self?.setCapsLockHandBack(.secureInput, active) }
            .store(in: &cancellables)
    }

    /// Lock screen, screen saver, sleep and fast-user-switching. These don't
    /// depend on Secure Input being detected in time: right after wake our
    /// polling timer may not have run yet, while the lock screen already has.
    private func observeCapsLockHandBackEvents() {
        guard !AppEnvironment.isUITest else { return }
        let dnc = DistributedNotificationCenter.default()
        let ws = NSWorkspace.shared.notificationCenter
        func on(_ center: NotificationCenter, _ name: Notification.Name,
                _ reason: CapsLockHandBackReason, _ value: Bool) {
            let o = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppState.shared.setCapsLockHandBack(reason, value) }
            }
            handBackObservers.append((center, o))
        }
        on(dnc, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true)
        on(dnc, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false)
        on(dnc, Notification.Name("com.apple.screensaver.didstart"), .screenSaver, true)
        on(dnc, Notification.Name("com.apple.screensaver.didstop"), .screenSaver, false)
        on(ws, NSWorkspace.willSleepNotification, .asleep, true)
        on(ws, NSWorkspace.didWakeNotification, .asleep, false)
        on(ws, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true)
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false)
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

    /// `isNew` distinguishes a genuine add (from the "add mapping" flow) from an
    /// edit, so analytics counts adoption, not re-saves. Fired only after the
    /// upsert succeeds. See `Analytics.mappingProps` for the PII-safe payload.
    func upsertMapping(trigger: Trigger, actionId: String?, inlineAction: ActionConfig? = nil, bindings: [MappingBinding] = [], isNew: Bool = false) throws {
        try config.upsert(trigger: trigger, actionId: actionId, inlineAction: inlineAction, bindings: bindings)
        if isNew {
            Analytics.shared.track("mapping_added", Analytics.mappingProps(actionId: actionId, inlineAction: inlineAction))
        }
    }

    func removeMapping(_ trigger: Trigger) {
        // Resolve the action type BEFORE removing so the "retire" signal knows
        // which feature was dropped.
        let entry = config.mappings.first { $0.trigger == trigger }
        config.remove(trigger: trigger)
        if let entry {
            Analytics.shared.track("mapping_removed", Analytics.mappingProps(actionId: entry.actionId, inlineAction: entry.inlineAction))
        }
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
