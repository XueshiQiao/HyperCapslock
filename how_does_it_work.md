# How HyperCapslock Works

This document explains the technical implementation of the key-remapping logic
in the native macOS app (SwiftUI + AppKit).

## Architecture Overview

The app is a single native process with two layers:
1. **UI Layer (SwiftUI + AppKit):** the settings window, the menu-bar status
   item, and a transparent on-screen HUD.
2. **Engine Layer (`HyperCapslock/Sources/Engine/`):** a low-level keyboard
   engine built on a `CGEventTap`, which intercepts and modifies keyboard input
   system-wide before any application sees it.

## The Core: hidutil remap + CGEventTap

### 1. CapsLock → F18 (`HidUtil`)
macOS sends CapsLock as an unreliable `FlagsChanged` toggle, not clean
KeyDown/KeyUp. So at launch we run `hidutil` to remap the physical CapsLock to
**F18** (a key no keyboard physically has). Now CapsLock generates proper
KeyDown/KeyUp events we can treat as a modifier. The remap is removed on quit.

Because F18 is not a real modifier (not ⌘/⌃/⌥/⇧), it **stacks with all of them
for free** — `Caps+Shift+H` arrives as F18-held + Shift + H, so "select left"
works with no extra configuration.

### 2. The Event Tap (`KeyboardHook`)
We install a `CGEventTap` at the HID level (`.cghidEventTap`,
`.headInsertEventTap`) with `.defaultTap` (active — it can modify/drop events,
which is why the app needs **Accessibility** permission, not Input Monitoring).
The tap runs on its own `CFRunLoop` thread. If creation fails because
Accessibility isn't granted yet, it retries every second, so the tap
auto-installs the moment the user grants permission — no relaunch.

### 3. Interception Logic (the tap callback)

- **Feedback-loop prevention:** every event we synthesize is stamped with a
  magic value in `EVENT_SOURCE_USER_DATA`; the callback skips any event carrying
  it, so our injected arrow keys don't re-trigger the tap.
- **F18 as modifier:** on F18 KeyDown we set `CAPS_DOWN` and swallow it; on KeyUp
  we decide between a *chord*, a *short tap*, or a *double tap*.
- **Chord (`Caps+key`):** while `CAPS_DOWN`, a mapped key is swallowed and the
  configured action is injected (e.g. H → Left Arrow), preserving any held real
  modifiers.
- **Short tap:** tapping Caps alone toggles the system CapsLock lock state via
  IOKit (`IOHIDSetModifierLockState`) — unless a single-tap mapping is set.
- **Double tap & double-tap-modifier:** a second tap within the window fires a
  configured action instead. A subtle detail: when a double-tap mapping exists,
  the lock toggle is deferred; if the user types during that window, we pre-empt
  the toggle on that keypress and XOR-patch the in-flight event's `AlphaShift`
  flag so the typed character's case resolves correctly.

### 4. Actions (`ActionExecutor`)
Mappings resolve to: directional moves, multi-line jumps, independent edits
(backspace, new line, insert quotes), input-source switching (Carbon TIS,
including the smart 中/英 toggle and the CJKV kana commit workaround), arbitrary
key combos, and shell commands (spawned off the tap thread).

## Safety and Performance
- **Thread-safe state:** runtime flags live behind `OSAllocatedUnfairLock`
  (`EngineState`) and the mappings behind an `NSLock` (`MappingsRegistry`),
  shared between the tap thread, timer threads, and the UI.
- **Minimal overhead:** the callback does integer comparisons and early returns
  to avoid system-wide input lag.
- **Logging:** the engine writes a detailed trace to
  `/tmp/hypercapslock-macos.log` for troubleshooting.
