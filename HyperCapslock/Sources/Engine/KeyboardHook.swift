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
        // A chord (esp. a held push-to-talk modifier) may have been mid-hold when
        // the tap went deaf; we'll miss its key-up, so release everything now.
        ActionExecutor.releaseAllInFlightChords()
        // The F18 key-up may likewise be missed — end the hold now.
        endCapsHold()
        if KeyboardHook.shared.reenable() {
            FileLog.shared.warn("Event tap disabled by system (type=\(type.rawValue)); requested re-enable.")
        } else {
            FileLog.shared.error("Event tap disabled by system (type=\(type.rawValue)); could not re-enable (tap port unknown).")
        }
        return pass
    }

    // Skip our own injected events (no feedback loop / re-detection).
    let injectedUserData = event.getIntegerValueField(.eventSourceUserData)
    if injectedUserData == KeyPoster.injectedMagic {
        return pass
    }
    // Same idea for the input-source-fix synthetic events (⌃Space / ⌘ reset),
    // but with a distinct tag we log explicitly — positive proof the tap saw them
    // as ours and did NOT re-enter the F18/chord/modifier-double-tap logic.
    if injectedUserData == InputSourceFix.syntheticEventUserData {
        FileLog.shared.info("Tap: passing through input-source-fix synthetic event (keycode=\(UInt16(event.getIntegerValueField(.keyboardEventKeycode))) type=\(type.rawValue)) — not re-processed.")
        return pass
    }

    // If paused, pass everything through.
    if state.isPaused { return pass }

    let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    // F18 = physical CapsLock (remapped via hidutil) → proper KeyDown/KeyUp.
    if keycode == KeyCodes.f18 {
        if type == .keyDown {
            beginCapsHold()
        } else if type == .keyUp {
            let wasDown = endCapsHold()
            // Caps released → release any in-flight chord now. If the chord key is
            // still physically held, its later key-up won't be seen (capsDown is
            // false), so without this a held modifier / key stays stuck down.
            ActionExecutor.releaseAllInFlightChords()
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
                UsageStats.shared.record(triggerUniqueID(.doubleTapModifier(modifier)))
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
    /// The tap thread's run loop, captured once the loop is up. Set on the tap
    /// thread before `CFRunLoopRun`, read from other threads (same plain-var
    /// cross-thread style as `eventTap`). Used to run chord-release on the tap
    /// thread so it serializes with chord handling.
    private var tapRunLoop: CFRunLoop?

    /// Release every in-flight chord, but **on the tap thread's run loop** so it
    /// can't race a fresh chord key-down being processed there (which would post
    /// a synthesized modifier down *after* the release cleared its latch, leaving
    /// it stuck). Routed for the off-tap-thread callers (pause, terminate); the
    /// tap-thread callers (Caps-up, tap-disabled, loop teardown) already run
    /// releaseAllInFlightChords directly.
    ///
    /// `wait: true` blocks (briefly) until the tap thread has drained the release.
    /// Used at termination, where an async hop might not run before the process
    /// exits — without it, a held push-to-talk modifier could stay stuck.
    func releaseHeldChordsSerialized(wait: Bool = false) {
        guard let rl = tapRunLoop, CFRunLoopGetCurrent() !== rl else {
            ActionExecutor.releaseAllInFlightChords()   // already on the tap thread (or no loop yet)
            return
        }
        if wait {
            let sem = DispatchSemaphore(value: 0)
            CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) {
                ActionExecutor.releaseAllInFlightChords()
                sem.signal()
            }
            CFRunLoopWakeUp(rl)
            _ = sem.wait(timeout: .now() + 0.2)   // bounded: never hang quit if the tap thread is wedged
        } else {
            CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) {
                ActionExecutor.releaseAllInFlightChords()
            }
            CFRunLoopWakeUp(rl)
        }
    }

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
            tapRunLoop = CFRunLoopGetCurrent()
            CGEvent.tapEnable(tap: tap, enable: true)
            FileLog.shared.info("✅ macOS keyboard event tap INSTALLED and enabled (attempt \(attempt)). mappings=\(MappingsRegistry.shared.snapshot().count) isPaused=\(EngineState.shared.isPaused)")
            // Recover from a prior crash/kill that left a hold-modifier stuck down.
            ActionExecutor.normalizeSyntheticModifiersAtStartup()
            CFRunLoopRun()   // blocks while the tap is alive
            FileLog.shared.warn("CFRunLoopRun returned; tap loop will rebuild the tap.")
            // The tap died for some reason other than the handled tap-disabled
            // callback; we'll miss any pending key-up, so force-release now (on
            // the tap thread, tap already dead → no concurrent callback to race).
            ActionExecutor.releaseAllInFlightChords()
            // Same reasoning for a CapsLock hold — end it so a missed F18 key-up
            // can't leave a hold latched (mirrors the tap-disabled branch).
            endCapsHold()
            eventTap = nil
        }
    }
}
