import AppKit
import Carbon
import CoreGraphics

/// CJKV input-source-switch reliability workarounds, ported from Input Source Pro
/// (GPLv3, https://github.com/runjuu/InputSourcePro). The `.switchingFocus`
/// (temporary input window) technique is itself adapted from macism
/// (MIT, (c) 2023 https://github.com/laishulu).
///
/// Applied only when a `Caps+key → input source` switch targets a CJKV IME
/// (Chinese / Japanese / Korean / Vietnamese / Russian) AND the user picked a
/// non-`.none` strategy. Everything else is a plain `TISSelectInputSource`.
///
/// Everything here runs on the MAIN queue (TIS main-queue affinity + AppKit
/// window). Synthetic keyboard events are stamped with `syntheticEventUserData`
/// so our own CGEventTap recognizes, logs, and passes them through untouched
/// (see `hcTapCallback` in KeyboardHook.swift) on their way to the system
/// input-source switcher.
///
/// Development note: this path is intentionally chatty in the log so any
/// switching glitch can be diagnosed purely from `FileLog`.
enum InputSourceFix {
    /// Stamped on our synthetic shortcut/⌘ events. Deliberately DISTINCT from
    /// `KeyPoster.injectedMagic` (which tags the high-frequency nav/edit
    /// injections): a separate value lets the tap *positively* log that it
    /// recognized and passed through THESE events, without flooding the log on
    /// every Caps+key navigation. Value spells "ISFX".
    static let syntheticEventUserData: Int64 = 0x4953_4658

    // MARK: - Tunables (mirror ISP timings)

    /// How long the invisible focus-grab window stays key.
    private static let focusWindowDuration: TimeInterval = 0.08
    /// Languages whose IMEs need the activation fix.
    private static let cjkvExactLanguages: Set<String> = ["ru", "ko", "ja", "vi"]

    // Main-queue-only mutable state (no locking needed — never touched off-main).
    private static var pendingWorkItems: [DispatchWorkItem] = []
    private static var focusWindow: NSWindow?
    private static var focusWindowPreviousApp: NSRunningApplication?
    /// While `systemUptime` is below this, FrontmostAppTracker ignores our own
    /// activation (the Switching-Focus round-trip briefly makes us frontmost).
    private static var selfActivationSuppressedUntil: TimeInterval = 0

    /// Read by FrontmostAppTracker (main thread) to skip our transient activation.
    static var isSuppressingSelfActivation: Bool {
        ProcessInfo.processInfo.systemUptime < selfActivationSuppressedUntil
    }

    // MARK: - Entry point (called on the main queue from InputSourceController)

    static func switchToSource(id: String, strategy: CJKVFixStrategy) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelPendingWorkItems()

        guard let target = source(forID: id) else {
            FileLog.shared.warn("InputSourceFix: no selectable input source for id=\(id) — switch aborted.")
            // A just-cancelled Switching-Focus grab must still hand focus back.
            restoreFocusIfNeeded()
            return
        }
        let cjkv = isCJKV(target)
        let willGrabFocus = (strategy == .switchingFocus && cjkv)
        // If a just-cancelled Switching-Focus round-trip left us frontmost and the
        // new switch won't re-grab focus, hand focus back before proceeding.
        if !willGrabFocus { restoreFocusIfNeeded() }

        FileLog.shared.info("InputSourceFix: switch id=\(id) strategy=\(strategy.rawValue) targetIsCJKV=\(cjkv) willGrabFocus=\(willGrabFocus) current=\(currentSourceID() ?? "nil")")

        // No fix when the user opted out, or the target isn't a CJKV IME (the
        // activation bug only affects CJKV targets — a layout switch is reliable).
        guard strategy != .none, cjkv else {
            let status = tisSelect(target, reason: cjkv ? "plain (strategy=none)" : "plain (non-CJKV target)")
            FileLog.shared.info("InputSourceFix: plain select id=\(id) status=\(status) now=\(currentSourceID() ?? "nil")")
            return
        }

        switch strategy {
        case .none:
            break // unreachable (guarded above)
        case .switchingFocus:
            applySwitchingFocus(target: target, id: id)
        case .shortcutSimulation:
            applyShortcutSimulation(target: target, id: id)
        }
    }

    // MARK: - Strategy: Switching Focus (temporary input window, from macism)

    private static func applySwitchingFocus(target: TISInputSource, id: String) {
        _ = tisSelect(target, reason: "switchingFocus target")
        showFocusWindow()

        scheduleWorkItem(after: focusWindowDuration + 0.05) {
            let now = currentSourceID()
            if now != id {
                FileLog.shared.warn("InputSourceFix[switchingFocus]: target not current after focus window (now=\(now ?? "nil")) — re-selecting id=\(id)")
                _ = tisSelect(target, reason: "switchingFocus mismatch fallback")
            } else {
                FileLog.shared.info("InputSourceFix[switchingFocus]: confirmed current=\(id)")
            }
        }
    }

    /// Opens a 3×3px, ~invisible, top-level window and activates our app for a
    /// brief moment. The focus round-trip forces macOS to settle the selected
    /// input source in-context, then we restore the previous frontmost app.
    private static func showFocusWindow() {
        closeFocusWindow(restorePreviousApp: false)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            FileLog.shared.warn("InputSourceFix[switchingFocus]: no screen available — skipping focus window.")
            return
        }

        // Never record ourselves as the app to restore: a rapid re-entry can fire
        // while a prior round-trip's async restore hasn't landed and we're still
        // frontmost — keep the real previous app already captured in that case.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            focusWindowPreviousApp = front
        }
        FileLog.shared.info("InputSourceFix[switchingFocus]: showing focus window; previousApp=\(focusWindowPreviousApp?.bundleIdentifier ?? "nil") front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")

        let size = NSSize(width: 3, height: 3)
        let visible = screen.visibleFrame
        let rect = NSRect(x: visible.maxX - size.width - 8, y: visible.minY + 8, width: size.width, height: size.height)

        let window = FocusGrabWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        window.contentView = textView
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        focusWindow = window
        // Suppress FrontmostAppTracker from latching onto our own activation during
        // the round-trip, so per-app mappings keep resolving to the user's app.
        selfActivationSuppressedUntil = ProcessInfo.processInfo.systemUptime + 0.5
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)

        scheduleWorkItem(after: focusWindowDuration) {
            closeFocusWindow(restorePreviousApp: true)
        }
    }

    private static func closeFocusWindow(restorePreviousApp: Bool) {
        if let window = focusWindow {
            focusWindow = nil
            window.orderOut(nil)
            window.close()
        }
        // When not restoring, the saved previous app is intentionally preserved
        // for the next switch (re-grab or explicit restore).
        if restorePreviousApp { restoreFocusIfNeeded() }
    }

    /// If we still hold focus from a Switching-Focus grab, hand it back to the
    /// app we took it from, then clear the saved reference. No-op otherwise.
    private static func restoreFocusIfNeeded() {
        guard let previousApp = focusWindowPreviousApp,
              previousApp.bundleIdentifier != Bundle.main.bundleIdentifier,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        else { return }
        FileLog.shared.info("InputSourceFix[switchingFocus]: restoring focus to previousApp=\(previousApp.bundleIdentifier ?? "nil")")
        previousApp.activate(options: [])
        focusWindowPreviousApp = nil
    }

    // MARK: - Strategy: Shortcut Simulation (synthesize "select previous source")

    private static func applyShortcutSimulation(target: TISInputSource, id: String) {
        guard let shortcut = previousInputSourceShortcut() else {
            FileLog.shared.warn("InputSourceFix[shortcutSimulation]: system 'Select previous input source' shortcut unavailable — falling back to plain select for id=\(id)")
            _ = tisSelect(target, reason: "shortcutSimulation fallback (no system shortcut)")
            return
        }
        guard let (bounceID, bounceSrc) = firstNonCJKVSource(), bounceID != id else {
            FileLog.shared.warn("InputSourceFix[shortcutSimulation]: no non-CJKV bounce source — falling back to plain select for id=\(id)")
            _ = tisSelect(target, reason: "shortcutSimulation fallback (no bounce source)")
            return
        }

        FileLog.shared.info("InputSourceFix[shortcutSimulation]: applying for id=\(id) bounce=\(bounceID) shortcut=keycode \(shortcut.keyCode) flags=0x\(String(shortcut.flags.rawValue, radix: 16))")
        _ = tisSelect(target, reason: "shortcutSimulation target")
        _ = tisSelect(bounceSrc, reason: "shortcutSimulation bounce")

        scheduleWorkItem(after: 0.1) {
            postKeyShortcut(shortcut)

            scheduleWorkItem(after: 0.1) {
                postCommandReset()

                scheduleWorkItem(after: 0.1) {
                    let now = currentSourceID()
                    if now != id {
                        FileLog.shared.warn("InputSourceFix[shortcutSimulation]: target not current after shortcut (now=\(now ?? "nil")) — re-selecting id=\(id)")
                        _ = tisSelect(target, reason: "shortcutSimulation mismatch fallback")
                    } else {
                        FileLog.shared.info("InputSourceFix[shortcutSimulation]: confirmed current=\(id)")
                    }
                }
            }
        }
    }

    struct ShortcutInfo {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    /// Reads the system "Select the previous input source" shortcut
    /// (symbolic-hotkey id 60). Returns nil if missing or disabled in Settings.
    /// Logs at the switch path (`log: true`); the UI availability check is quiet.
    static func previousInputSourceShortcut(log: Bool = true) -> ShortcutInfo? {
        guard let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotKeys = dict["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = hotKeys["60"] as? [String: Any] else {
            if log { FileLog.shared.info("InputSourceFix: 'Select previous input source' shortcut not found in symbolichotkeys.") }
            return nil
        }
        if let enabled = entry["enabled"] as? Bool, !enabled {
            if log { FileLog.shared.info("InputSourceFix: 'Select previous input source' shortcut is disabled in System Settings.") }
            return nil
        }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count >= 3 else {
            if log { FileLog.shared.info("InputSourceFix: 'Select previous input source' shortcut has an unexpected parameter format.") }
            return nil
        }
        return ShortcutInfo(keyCode: CGKeyCode(parameters[1]),
                            flags: carbonModifiersToCGFlags(parameters[2]))
    }

    /// For the UI: whether Shortcut Simulation can actually run right now (quiet).
    static var isPreviousInputSourceShortcutAvailable: Bool {
        previousInputSourceShortcut(log: false) != nil
    }

    private static func carbonModifiersToCGFlags(_ carbon: Int) -> CGEventFlags {
        var flags = CGEventFlags()
        if carbon & 131072 != 0 { flags.insert(.maskShift) }
        if carbon & 262144 != 0 { flags.insert(.maskControl) }
        if carbon & 524288 != 0 { flags.insert(.maskAlternate) }  // Option
        if carbon & 1048576 != 0 { flags.insert(.maskCommand) }
        return flags
    }

    private static func postKeyShortcut(_ shortcut: ShortcutInfo) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            FileLog.shared.warn("InputSourceFix[shortcutSimulation]: failed to create shortcut key events.")
            return
        }
        stampSynthetic(down)
        stampSynthetic(up)
        down.flags = shortcut.flags
        up.flags = shortcut.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postCommandReset() {
        let source = CGEventSource(stateID: .hidSystemState)
        let commandKey: CGKeyCode = 55  // kVK_Command
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false) else {
            FileLog.shared.warn("InputSourceFix[shortcutSimulation]: failed to create command-reset events.")
            return
        }
        stampSynthetic(down)
        stampSynthetic(up)
        down.flags = .maskCommand
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Stamp with our dedicated magic so the tap recognizes (and logs) it as
    /// ours and passes it through instead of re-processing it.
    private static func stampSynthetic(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
    }

    // MARK: - TIS helpers

    @discardableResult
    private static func tisSelect(_ src: TISInputSource, reason: String) -> OSStatus {
        let status = TISSelectInputSource(src)
        if status != noErr {
            FileLog.shared.warn("InputSourceFix: TISSelectInputSource failed (\(reason)) status=\(status)")
        }
        return status
    }

    private static func allSources() -> [TISInputSource] {
        guard let cf = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        return (cf as NSArray) as? [TISInputSource] ?? []
    }

    /// Return a *selectable* source matching `id`. Never a non-selectable one —
    /// `TISSelectInputSource` fails on those, and the caller treats `nil` as
    /// "abort the switch". (A given source ID generally has a single match.)
    private static func source(forID id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let cf = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return nil }
        let list = (cf as NSArray) as? [TISInputSource] ?? []
        return list.first(where: { isSelectable($0) })
    }

    private static func firstNonCJKVSource() -> (String, TISInputSource)? {
        for src in allSources() where isSelectable(src) && !isCJKV(src) {
            if let id = propertyString(src, kTISPropertyInputSourceID) { return (id, src) }
        }
        return nil
    }

    private static func currentSourceID() -> String? {
        guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return propertyString(cur, kTISPropertyInputSourceID)
    }

    private static func isCJKV(_ src: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return false }
        let langs = (Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as NSArray) as? [String] ?? []
        guard let lang = langs.first else { return false }
        return cjkvExactLanguages.contains(lang) || lang.hasPrefix("zh")
    }

    private static func isSelectable(_ src: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    private static func propertyString(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    // MARK: - Work-item scheduling (main-queue serial; cancellable on re-entry)

    private static func scheduleWorkItem(after delay: TimeInterval, _ work: @escaping () -> Void) {
        var item: DispatchWorkItem?
        item = DispatchWorkItem {
            guard let i = item else { return }
            defer { pendingWorkItems.removeAll { $0 === i } }
            guard !i.isCancelled else { return }
            work()
        }
        guard let i = item else { return }
        pendingWorkItems.append(i)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: i)
    }

    /// A new switch supersedes any in-flight one: cancel pending steps and tear
    /// down a lingering focus window (restoring the previous app).
    private static func cancelPendingWorkItems() {
        // Tear down a lingering focus window WITHOUT restoring (and preserving the
        // saved previous app): the new switch either re-grabs focus (Switching
        // Focus) or restores it explicitly via `restoreFocusIfNeeded()`.
        closeFocusWindow(restorePreviousApp: false)
        guard !pendingWorkItems.isEmpty else { return }
        pendingWorkItems.forEach { $0.cancel() }
        pendingWorkItems.removeAll()
    }
}

/// Borderless window that can still become key/main, so activating it lands
/// keyboard focus on us for the brief Switching-Focus round-trip.
private final class FocusGrabWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
