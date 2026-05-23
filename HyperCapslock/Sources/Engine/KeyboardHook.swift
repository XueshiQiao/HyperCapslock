import Foundation
import CoreGraphics

/// The CGEventTap callback. Must be a bare C function (captures nothing); all
/// state lives in singletons, exactly like the Rust globals.
///
/// Return convention (raw CGEventTap C API): return the event to pass it
/// through, `nil` to drop (swallow) it.
private func hcTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let state = EngineState.shared
    let pass = Unmanaged.passUnretained(event)

    // Re-enable the tap if the system disabled it (timeout / heavy input).
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if KeyboardHook.shared.reenable() {
            FileLog.shared.warn("Event tap disabled by system (type=\(type.rawValue)); requested re-enable.")
        } else {
            FileLog.shared.error("Event tap disabled by system (type=\(type.rawValue)); could not re-enable (tap port unknown).")
        }
        return pass
    }

    // Skip our own injected events (no feedback loop / re-detection).
    if event.getIntegerValueField(.eventSourceUserData) == KeyPoster.injectedMagic {
        return pass
    }

    // If paused, pass everything through.
    if state.isPaused { return pass }

    let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    // F18 = physical CapsLock (remapped via hidutil) → proper KeyDown/KeyUp.
    if keycode == KeyCodes.f18 {
        if type == .keyDown {
            let wasDown = state.swapCapsDown(true)
            if !wasDown {
                state.capsPressedAtMs = nowMillis()
                state.didRemap = false
                FileLog.shared.info("Caps(F18) down.")
            }
        } else if type == .keyUp {
            let wasDown = state.swapCapsDown(false)
            let pressedAt = state.swapCapsPressedAtMs(0)
            let held = nowMillis() &- pressedAt
            if wasDown && !state.didRemap {
                if held <= EngineConstants.capsTapMaxMs {
                    ActionExecutor.handleShortTap()
                } else {
                    FileLog.shared.info("Caps(F18) held \(held)ms (> \(EngineConstants.capsTapMaxMs)ms). Suppressing native CapsLock toggle.")
                }
            } else if wasDown {
                FileLog.shared.info("Caps(F18) up after remap sequence.")
            }
        }
        return nil  // swallow F18
    }

    // Raw CapsLock FlagsChanged (in case hidutil isn't active) → swallow.
    if type == .flagsChanged && keycode == KeyCodes.capsLock {
        return nil
    }

    // ─── Modifier double-tap detection (independent of the Caps/F18 path) ───
    // Never swallows/mutates modifier events; just additionally fires the mapped
    // action on a clean 2nd tap. Gated so unconfigured keyboards pay nothing.
    if ModifierDoubleTap.anyConfigured() {
        if type == .flagsChanged {
            if let modifier = ModifierDoubleTap.modifier(for: keycode),
               let action = ModifierDoubleTap.shared.onModifierFlags(modifier, flags: flags) {
                FileLog.shared.info("Modifier DOUBLE-TAP detected (keycode=\(keycode)). Firing action.")
                let (combo, caption) = hudParts(action)
                HudCenter.shared.emit(trigger: "\(modifierHudLabel(modifier)) ×2", combo: combo, caption: caption)
                ActionExecutor.fireDoubleTapModifierAction(action)
            }
        } else if type == .keyDown {
            // A regular key press means any in-progress modifier tap is a chord.
            ModifierDoubleTap.shared.invalidateAll()
        }
    }

    // ─── Pre-empt the deferred CapsLock toggle on the next keypress ───
    // If a key is typed during the deferred window, the pending tap was a single
    // tap. Fire the toggle synchronously now, before the typed key propagates,
    // and XOR-patch this in-flight event's AlphaShift flag so its character case
    // re-resolves correctly. Skip while Caps is held (a chord is in progress).
    if type == .keyDown && !state.capsDown {
        let pending = state.swapLastTapAtMs(0)
        if pending > 0 && !state.isPaused {
            let age = nowMillis() &- pending
            let kernelFlipped = ActionExecutor.fireCapsShortTap()
            if kernelFlipped {
                let old = event.flags
                let patched = old.symmetricDifference(.maskAlphaShift)
                FileLog.shared.info("Caps(F18) pending toggle pre-empted by next keypress: keycode=\(keycode) age=\(age)ms; toggled CapsLock and flipped in-flight AlphaShift flag (0x\(String(old.rawValue, radix: 16)) -> 0x\(String(patched.rawValue, radix: 16))).")
                event.flags = patched
            } else {
                FileLog.shared.warn("Caps(F18) pending toggle pre-empted by next keypress: keycode=\(keycode) age=\(age)ms; kernel state flip failed — skipping in-flight AlphaShift patch.")
            }
        }
    }

    // ─── Caps + key chord ───
    if state.capsDown {
        let keyDown = (type == .keyDown)
        let activeMods = activeModifierFlags(flags)
        let js = KeyCodes.macToJs(keycode)
        FileLog.shared.info("Caps HELD + key: \(keyDown ? "DOWN" : "UP") mac=\(keycode) js=\(js.map(String.init) ?? "nil") name=\(js.map(KeyCodes.name) ?? "?") mods=0x\(String(activeMods.rawValue, radix: 16))")
        if ActionExecutor.handleCapsRemap(keycode: keycode, keyDown: keyDown, activeModifiers: activeMods) {
            state.didRemap = true
            FileLog.shared.info("Caps chord HANDLED (mac=\(keycode)) — swallowing original event.")
            return nil  // swallow the chord key
        } else if keyDown {
            FileLog.shared.info("Caps chord had NO mapping (mac=\(keycode) js=\(js.map(String.init) ?? "nil")) — passing through.")
        }
    }

    return pass
}

/// Installs and owns the CGEventTap on a dedicated CFRunLoop thread.
final class KeyboardHook {
    static let shared = KeyboardHook()

    private var eventTap: CFMachPort?

    /// Install hidutil remap + the event tap. Call once at launch.
    func start() {
        FileLog.shared.info("Starting macOS keyboard hook.")

        // The event tap is an ACTIVE (.defaultTap) tap, which macOS gates on
        // Accessibility — NOT Input Monitoring (that's for .listenOnly taps).
        // Granting Accessibility implicitly covers the keyboard tap.
        if !Permissions.isAccessibilityGranted {
            FileLog.shared.warn("Accessibility permission not granted. Prompting system dialog.")
            Permissions.promptAccessibility()
        } else {
            FileLog.shared.info("Accessibility permission already granted.")
        }

        if !HidUtil.setupRemap() {
            FileLog.shared.warn("Could not remap CapsLock via hidutil. Caps modifier may be unreliable.")
        }

        let thread = Thread { [weak self] in self?.runTapLoop() }
        thread.name = "me.xueshi.hypercapslock.eventtap"
        thread.start()
    }

    @discardableResult
    func reenable() -> Bool {
        guard let tap = eventTap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Restore the original CapsLock mapping. Call on quit.
    func cleanup() {
        HidUtil.cleanupRemap()
    }

    private func runTapLoop() {
        FileLog.shared.info("macOS hook thread spawned. AXIsProcessTrusted=\(Permissions.isAccessibilityGranted)")
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // Retry tapCreate until it succeeds. An active tap requires Accessibility;
        // creation fails (returns nil) until it's granted. Retrying tapCreate
        // itself — rather than polling AXIsProcessTrusted(), which can return a
        // stale cached value within a process — lets the tap auto-install the
        // moment the user grants Accessibility, with no relaunch.
        var attempt = 0
        while true {
            attempt += 1
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hcTapCallback,
                userInfo: nil
            ) else {
                if attempt == 1 || attempt % 5 == 0 {
                    FileLog.shared.warn("⏳ CGEventTap creation FAILED (attempt \(attempt)). Accessibility likely not granted yet (AXIsProcessTrusted=\(Permissions.isAccessibilityGranted)). Retrying every 1s — grant Accessibility and the tap will auto-install with NO relaunch.")
                }
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }

            eventTap = tap
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                FileLog.shared.error("CFMachPortCreateRunLoopSource returned nil; retrying in 1s.")
                eventTap = nil
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            FileLog.shared.info("✅ macOS keyboard event tap INSTALLED and enabled (attempt \(attempt)). mappings=\(MappingsRegistry.shared.snapshot().count) isPaused=\(EngineState.shared.isPaused)")
            CFRunLoopRun()   // blocks while the tap is alive
            FileLog.shared.warn("CFRunLoopRun returned; tap loop will rebuild the tap.")
            eventTap = nil
        }
    }
}
