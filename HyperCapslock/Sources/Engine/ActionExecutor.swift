import Foundation
import CoreGraphics
import AppKit
import os

// MARK: - Human-readable descriptions (logs + HUD)

/// "Cmd+Shift+V"-style string for a KeyCombo.
func keyComboString(_ targetKey: UInt16, _ ctrl: Bool, _ alt: Bool, _ cmd: Bool, _ shift: Bool) -> String {
    var s = ""
    if cmd { s += "Cmd+" }
    if ctrl { s += "Ctrl+" }
    if alt { s += "Alt+" }
    if shift { s += "Shift+" }
    s += KeyCodes.name(targetKey)
    return s
}

func describeAction(_ action: ActionConfig) -> String {
    switch action {
    case .keyCombo(let k, let ctrl, let alt, let cmd, let shift):
        return keyComboString(k, ctrl, alt, cmd, shift)
    case .directional(let a): return "directional \(a.rawValue)"
    case .jump(let dir, let count): return "jump \(dir.rawValue) x\(count)"
    case .independent(let a): return "independent \(a.rawValue)"
    case .inputSource(let id): return "input source \(id)"
    case .command(let cmd): return "command: \(cmd)"
    case .openApp(let bid, let name): return "open app \(name) (\(bid))"
    }
}

/// (keycap-combo string, human caption) for the HUD. KeyCombo is keys-only;
/// everything else gets a glyph + caption. Captions kept in English to match the
/// original HUD payloads.
func hudParts(_ action: ActionConfig) -> (String, String) {
    switch action {
    case .keyCombo(let k, let ctrl, let alt, let cmd, let shift):
        return (keyComboString(k, ctrl, alt, cmd, shift), "")
    case .directional(let a):
        let map: [DirectionalActionKind: (String, String)] = [
            .left: ("←", "Move Left"), .right: ("→", "Move Right"),
            .up: ("↑", "Move Up"), .down: ("↓", "Move Down"),
            .wordForward: ("⌥→", "Word Forward"), .wordBack: ("⌥←", "Word Back"),
            .home: ("↖", "Line Start"), .end: ("↘", "Line End"),
        ]
        let (sym, name) = map[a]!
        return (sym, name)
    case .jump(let dir, let count):
        let sym = dir == .up ? "↑" : "↓"
        return ("\(sym)×\(count)", "Jump \(dir.rawValue)")
    case .independent(let a):
        let map: [IndependentActionKind: (String, String)] = [
            .backspace: ("⌫", "Backspace"), .nextLine: ("↵", "New Line"),
            .insertQuotes: ("\u{201C}\u{201D}", "Insert Quotes"),
            .toggleCapsLock: ("\u{21EA}", "Toggle Caps Lock"),
            .switchInputSource: ("\u{2328}", "Switch Input Source"),
            .noop: ("\u{2298}", "Do Nothing"),
        ]
        let (sym, name) = map[a]!
        return (sym, name)
    case .inputSource(let id):
        return ("\u{2328}", id)
    case .command(let cmd):
        return ("Shell", cmd)
    case .openApp(_, let name):
        return ("App", name)
    }
}

func modifierHudLabel(_ m: ModifierKey) -> String {
    switch m {
    case .leftShift: return "\u{21E7}L"
    case .rightShift: return "\u{21E7}R"
    case .leftControl: return "\u{2303}L"
    case .rightControl: return "\u{2303}R"
    case .leftOption: return "\u{2325}L"
    case .rightOption: return "\u{2325}R"
    case .leftCommand: return "\u{2318}L"
    case .rightCommand: return "\u{2318}R"
    case .fn: return "fn"
    }
}

// MARK: - Action executor

enum ActionExecutor {
    /// True for actions whose Caps+key binding should also fire when Shift is
    /// held (so Caps+Shift+H still moves left). Excludes actions where Shift
    /// would change meaning (input source / command / key combo carry their own
    /// modifier intent).
    static func allowShiftFallback(_ action: ActionConfig) -> Bool {
        switch action {
        case .inputSource, .command, .keyCombo, .openApp: return false
        case .independent(.noop): return false  // a disabled key shouldn't disable its shifted variant too
        default: return true
        }
    }

    /// Snapshot of the runtime environment for binding evaluation. Reads only
    /// the cached frontmost bundle id (a lock read) — safe on the tap thread.
    static func currentContext() -> RuntimeContext {
        RuntimeContext(frontmostBundleID: FrontmostAppTracker.shared.currentBundleID())
    }

    /// Effective action for a mapping under `ctx`: the first per-app binding
    /// whose conditions all hold and that resolves to an action wins; otherwise
    /// the default `actionId`/inline; otherwise nil (caller decides
    /// swallow-vs-passthrough). An orphaned matching binding is skipped.
    static func effectiveAction(_ entry: ActionMappingEntry, _ ctx: RuntimeContext) -> ActionConfig? {
        for binding in entry.bindings where binding.matches(ctx) {
            if let cfg = ActionsRegistry.shared.resolve(binding) { return cfg }
        }
        return ActionsRegistry.shared.resolve(entry)
    }

    /// Stage 1: find the trigger group for a Caps+key chord, applying the
    /// shift-fallback — Caps+Shift+K with no exact group falls back to the
    /// Caps+K group when *its effective action under `ctx`* allows it.
    static func resolveEntry(jsKeycode: UInt16, shiftHeld: Bool, ctx: RuntimeContext) -> ActionMappingEntry? {
        MappingsRegistry.shared.withMappings { mappings in
            if let exact = mappings.first(where: {
                if case .hyperPlusKey(let key, let withShift) = $0.trigger {
                    return key == jsKeycode && withShift == shiftHeld
                }
                return false
            }) { return exact }

            if shiftHeld {
                if let fallback = mappings.first(where: { entry in
                    guard case .hyperPlusKey(let key, let withShift) = entry.trigger,
                          key == jsKeycode, withShift == false,
                          let cfg = effectiveAction(entry, ctx) else { return false }
                    return allowShiftFallback(cfg)
                }) { return fallback }
            }
            return nil
        }
    }

    static func findSingleTapAction(_ ctx: RuntimeContext) -> ActionConfig? {
        MappingsRegistry.shared.withMappings { m in
            guard let entry = m.first(where: { if case .singleTapHyper = $0.trigger { return true }; return false })
            else { return nil }
            return effectiveAction(entry, ctx)
        }
    }

    static func findDoubleTapAction(_ ctx: RuntimeContext) -> ActionConfig? {
        MappingsRegistry.shared.withMappings { m in
            guard let entry = m.first(where: { if case .doubleTapHyper = $0.trigger { return true }; return false })
            else { return nil }
            return effectiveAction(entry, ctx)
        }
    }

    static func execute(_ action: ActionConfig, keyDown: Bool, activeModifiers: CGEventFlags) {
        switch action {
        case .directional(let a):
            switch a {
            case .left: KeyPoster.post(KeyCodes.left, keyDown: keyDown, flags: activeModifiers)
            case .right: KeyPoster.post(KeyCodes.right, keyDown: keyDown, flags: activeModifiers)
            case .up: KeyPoster.post(KeyCodes.up, keyDown: keyDown, flags: activeModifiers)
            case .down: KeyPoster.post(KeyCodes.down, keyDown: keyDown, flags: activeModifiers)
            case .wordForward:
                KeyPoster.post(KeyCodes.right, keyDown: keyDown, flags: activeModifiers.union(.maskAlternate))
            case .wordBack:
                KeyPoster.post(KeyCodes.left, keyDown: keyDown, flags: activeModifiers.union(.maskAlternate))
            case .home:
                KeyPoster.post(KeyCodes.left, keyDown: keyDown, flags: activeModifiers.union(.maskCommand))
            case .end:
                KeyPoster.post(KeyCodes.right, keyDown: keyDown, flags: activeModifiers.union(.maskCommand))
            }
        case .jump(let direction, let count):
            if keyDown && count > 0 {
                let kc = direction == .up ? KeyCodes.up : KeyCodes.down
                for _ in 0..<count { KeyPoster.postTap(kc, flags: activeModifiers) }
            }
        case .independent(let a):
            switch a {
            case .backspace:
                KeyPoster.post(KeyCodes.delete, keyDown: keyDown, flags: activeModifiers)
            case .nextLine:
                if keyDown {
                    KeyPoster.postTap(KeyCodes.right, flags: .maskCommand)
                    KeyPoster.postTap(KeyCodes.return, flags: [])
                }
            case .insertQuotes:
                if keyDown {
                    for _ in 0..<6 { KeyPoster.insertString("\"") }
                    for _ in 0..<3 { KeyPoster.postTap(KeyCodes.left, flags: []) }
                }
            case .toggleCapsLock:
                if keyDown { _ = toggleCapsLock() }
            case .switchInputSource, .noop:
                break   // intentionally does nothing (the chord is still swallowed).
                        // `.switchInputSource` is a retired tombstone — see ActionModel.swift.
            }
        case .inputSource(let id):
            if keyDown { InputSourceController.queueSwitch(toID: id) }
        case .command(let cmd):
            if keyDown {
                FileLog.shared.info("Shell mapping triggered: command=\(cmd)")
                DispatchQueue.global().async {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/bin/sh")
                    proc.arguments = ["-c", cmd]
                    do { try proc.run() }
                    catch { FileLog.shared.error("Failed to spawn shell mapping: \(error.localizedDescription)") }
                }
            }
        case .keyCombo(let targetKey, let ctrl, let alt, let cmd, let shift):
            guard let mac = KeyCodes.jsToMac(targetKey) else {
                FileLog.shared.warn("KeyCombo: unknown JS keycode \(targetKey), cannot map to macOS")
                return
            }
            var flags: CGEventFlags = []
            if ctrl { flags.insert(.maskControl) }
            if alt { flags.insert(.maskAlternate) }
            if cmd { flags.insert(.maskCommand) }
            if shift { flags.insert(.maskShift) }
            KeyPoster.post(mac, keyDown: keyDown, flags: flags)
        case .openApp(let bundleID, _):
            if keyDown {
                FileLog.shared.info("Open-app mapping triggered: bundleID=\(bundleID)")
                // Launch Services lookup + launch off the CGEventTap callback thread
                // (same reason `.command` dispatches): don't block the hot path.
                DispatchQueue.global().async {
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                        FileLog.shared.error("Open-app: no application found for bundle id \(bundleID)")
                        return
                    }
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
                        if let error { FileLog.shared.error("Open-app failed for \(bundleID): \(error.localizedDescription)") }
                    }
                }
            }
        }
    }

    // MARK: - Caps short-tap behavior

    /// Direct IOKit CapsLock toggle. Returns true only when the AlphaShift bit
    /// actually flipped (the pre-empt path depends on this).
    @discardableResult
    static func toggleCapsLock() -> Bool {
        guard let current = CapsLockState.read() else {
            FileLog.shared.error("toggle_caps_lock: could not read current CapsLock state; aborting toggle.")
            return false
        }
        let newState = !current
        if CapsLockState.set(newState) {
            FileLog.shared.info("CapsLock toggled via IOKit: previous_state=\(current) new_state=\(newState)")
            return true
        }
        FileLog.shared.error("CapsLock toggle failed at IOKit set step (previous_state=\(current)).")
        return false
    }

    /// Dispatcher for a confirmed short Caps tap. Returns true only when the
    /// kernel CapsLock state was flipped (so the in-flight AlphaShift patch is safe).
    @discardableResult
    static func fireCapsShortTap() -> Bool {
        if let action = findSingleTapAction(currentContext()) {
            FileLog.shared.info("Caps single-tap action: \(describeAction(action))")
            let (combo, caption) = hudParts(action)
            HudCenter.shared.emit(trigger: "Caps", combo: combo, caption: caption)
            if case .independent(.toggleCapsLock) = action {
                return toggleCapsLock()
            }
            execute(action, keyDown: true, activeModifiers: [])
            execute(action, keyDown: false, activeModifiers: [])
            return false
        } else {
            return toggleCapsLock()
        }
    }

    /// State machine for a confirmed short Caps tap (held ≤ capsTapMax, no remap).
    /// Defers the CapsLock toggle by `doubleTapWindow` when a DoubleTapHyper
    /// mapping exists, so a 2nd tap can convert it into the configured action.
    static func handleShortTap() {
        let now = nowMillis()
        let prevTap = EngineState.shared.swapLastTapAtMs(0)
        let dtAction = findDoubleTapAction(currentContext())

        // 2nd tap within the double-tap window?
        if prevTap > 0, now &- prevTap <= EngineConstants.doubleTapWindowMs, let action = dtAction {
            FileLog.shared.info("Caps(F18) DOUBLE-TAP detected (\(now &- prevTap)ms gap). Firing action.")
            let (combo, caption) = hudParts(action)
            HudCenter.shared.emit(trigger: "Caps ×2", combo: combo, caption: caption)
            execute(action, keyDown: true, activeModifiers: [])
            execute(action, keyDown: false, activeModifiers: [])
            return
        }

        // Fresh single tap. Fire an orphaned previous tap's toggle synchronously.
        if prevTap > 0 {
            FileLog.shared.info("Caps(F18) prior pending tap expired without 2nd tap; firing CapsLock toggle synchronously.")
            _ = fireCapsShortTap()
        }

        if dtAction != nil {
            FileLog.shared.info("Caps(F18) short tap; deferring CapsLock toggle by \(EngineConstants.doubleTapWindowMs)ms (double-tap mapping configured).")
            EngineState.shared.storeLastTapAtMs(now)
            let scheduledFor = now
            let delay = Double(EngineConstants.doubleTapWindowMs + 10) / 1000.0
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                if EngineState.shared.compareExchangeLastTapAtMs(expected: scheduledFor, new: 0) {
                    if EngineState.shared.isPaused {
                        FileLog.shared.info("Caps(F18) double-tap window elapsed but service paused; skipping CapsLock toggle.")
                        return
                    }
                    FileLog.shared.info("Caps(F18) double-tap window elapsed; toggling CapsLock.")
                    _ = fireCapsShortTap()
                }
            }
        } else {
            FileLog.shared.info("Caps(F18) short tap; toggling CapsLock immediately.")
            _ = fireCapsShortTap()
        }
    }

    // MARK: - Caps + key chord

    /// Action latched at key-DOWN so key-UP releases the SAME synthesized key
    /// even if the frontmost app changes mid-chord. With per-app bindings the
    /// resolved action is context-dependent, so re-resolving on key-up could
    /// post the up of a *different* key (or none) and strand the down. The
    /// stored value is `ActionConfig?`: a present entry means "we handled the
    /// down" (nil inner = swallowed, no action posted); absent means we didn't.
    private static let inFlightChord = OSAllocatedUnfairLock<[UInt16: ActionConfig?]>(initialState: [:])

    /// Returns true if the chord was handled (and the original key should be
    /// swallowed). Logs a readable "Caps remap: <trigger> -> <action>" on keyDown.
    static func handleCapsRemap(keycode: UInt16, keyDown: Bool, activeModifiers: CGEventFlags) -> Bool {
        let shiftHeld = activeModifiers.contains(.maskShift)
        guard let jsKeycode = KeyCodes.macToJs(keycode) else { return false }

        // Key-UP: mirror the key-down decision via the latch so down/up always
        // pair up, regardless of any app switch in between.
        if !keyDown {
            if let latched = inFlightChord.withLock({ $0.removeValue(forKey: jsKeycode) }) {
                if let action = latched { execute(action, keyDown: false, activeModifiers: activeModifiers) }
                return true   // handled the down (executed or swallowed) → swallow the up too
            }
            return false       // we passed the down through → pass the up through
        }

        // Key-DOWN. Autorepeat: a held chord re-fires key-down. Reuse the action
        // latched at the FIRST down so the whole hold stays consistent and the
        // eventual up pairs up — even if the app/shift/config changed mid-hold.
        if let cached = inFlightChord.withLock({ $0[jsKeycode] }) {
            if let action = cached { execute(action, keyDown: true, activeModifiers: activeModifiers) }
            return true   // already our chord (autorepeat) → swallow
        }

        // Fresh press. Stage 1: trigger group. No group → not ours; pass through.
        let ctx = currentContext()
        guard let mapping = resolveEntry(jsKeycode: jsKeycode, shiftHeld: shiftHeld, ctx: ctx) else { return false }
        // Stage 2: effective action under the frontmost app. Latch it. Use
        // updateValue, not subscript-assign: for a `[Key: Optional]` dictionary,
        // `dict[key] = nil` REMOVES the entry, but we need to store an explicit
        // nil meaning "we handled the down by swallowing".
        let action = effectiveAction(mapping, ctx)
        inFlightChord.withLock { _ = $0.updateValue(action, forKey: jsKeycode) }

        let trigger = shiftHeld ? "Caps+Shift+\(KeyCodes.name(jsKeycode))" : "Caps+\(KeyCodes.name(jsKeycode))"
        guard let action else {
            // Group matched but no applicable binding and no resolvable default.
            // The user claimed this chord → swallow it (no-op), do NOT pass the
            // raw key through. (Divergence from the pre-bindings behavior.)
            let base = "Caps remap: \(trigger) matched but no applicable action (frontmost=\(ctx.frontmostBundleID ?? "nil")) — swallowing."
            if mapping.actionId != nil || mapping.inlineAction != nil {
                FileLog.shared.warn(base + " (default action unresolved/orphaned)")
            } else {
                FileLog.shared.info(base)
            }
            return true
        }
        FileLog.shared.info("Caps remap: \(trigger) -> \(describeAction(action))")
        let (combo, caption) = hudParts(action)
        HudCenter.shared.emit(trigger: trigger, combo: combo, caption: caption)
        execute(action, keyDown: true, activeModifiers: activeModifiers)
        return true
    }

    // MARK: - Double-tap-modifier firing

    /// Fire the action bound to a double-tapped modifier. KeyCombo needs special
    /// handling: detection fires at modifier-release, which races the real
    /// release for Carbon/global-hotkey matching, so we defer ~50ms then
    /// synthesize an explicit modifier-down → target → modifier-up sequence with
    /// cumulative flags. Other actions keep the plain down+up behavior.
    static func fireDoubleTapModifierAction(_ action: ActionConfig) {
        if case .keyCombo(let targetKey, let ctrl, let alt, let cmd, let shift) = action {
            guard let mac = KeyCodes.jsToMac(targetKey) else {
                FileLog.shared.warn("double-tap KeyCombo: unknown JS keycode \(targetKey), cannot map to macOS")
                return
            }
            FileLog.shared.info("double-tap KeyCombo synthesizing: \(keyComboString(targetKey, ctrl, alt, cmd, shift))")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                if EngineState.shared.isPaused { return }
                var mods: [(UInt16, CGEventFlags)] = []
                if cmd { mods.append((KeyCodes.lCommand, .maskCommand)) }
                if ctrl { mods.append((KeyCodes.lCtrl, .maskControl)) }
                if alt { mods.append((KeyCodes.lOption, .maskAlternate)) }
                if shift { mods.append((KeyCodes.lShift, .maskShift)) }

                var acc: CGEventFlags = []
                for (kc, fl) in mods {
                    acc.formUnion(fl)
                    KeyPoster.post(kc, keyDown: true, flags: acc)
                }
                KeyPoster.post(mac, keyDown: true, flags: acc)
                KeyPoster.post(mac, keyDown: false, flags: acc)
                for (kc, fl) in mods.reversed() {
                    acc.subtract(fl)
                    KeyPoster.post(kc, keyDown: false, flags: acc)
                }
            }
            return
        }
        execute(action, keyDown: true, activeModifiers: [])
        execute(action, keyDown: false, activeModifiers: [])
    }
}
