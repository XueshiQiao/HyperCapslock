# Testing HyperCapslock on a headless Mac (read before you trust a repro)

**You cannot validly test HyperCapslock's CapsLock hyper-key on a headless Mac
that you drive over Screen Sharing.** It will look completely broken — no
chords, no `Caps(F18)`, CapsLock seemingly dead — on a machine that is in fact
perfectly healthy. This is a property of the *test environment*, not a bug in
the app. We burned a long debugging session on this; this note exists so the
next person (or agent) doesn't.

## Two independent reasons it can't work over Screen Sharing

1. **Screen-shared keystrokes are synthetic → they bypass `hidutil`.**
   HyperCapslock turns CapsLock into a hyper key by remapping CapsLock → F18 at
   the HID layer via `hidutil` (see `HidUtil.swift`). That remap only applies to
   **physical** HID input. Keystrokes injected by `screensharingd` are synthetic
   `CGEvent`s that never traverse the HID remap, so on the target machine
   CapsLock stays CapsLock and **never becomes F18** — the engine's entire
   F18-based path (chords, hold, single-tap) is dead by construction.

2. **The controller eats CapsLock before it's ever sent.**
   If the *controlling* Mac is also running HyperCapslock, its global
   `.cghidEventTap` (head-insert) sees CapsLock **before** Screen Sharing.app
   does, remaps it to F18, runs its own hyper logic, and swallows it. Screen
   Sharing never receives the key, so nothing is forwarded to the target. Only
   the plain letters you type get forwarded — carrying the *controller's* caps
   state, which is why you may see weird mixed-case like `aBC` (that's the
   controller's app, including its known caps-toggle race — not the target).

## Plugging in a physical keyboard isn't enough either (if headless)

A **headless** Mac (no display attached) whose only display is a *Screen Sharing
Virtual Display* will **recognize** a connected Bluetooth/USB keyboard at the HID
layer (it enumerates fine), but **its keypresses do not reach the screen-shared
virtual session** — they appear to do nothing. This is a well-documented
headless + Screen Sharing input-routing quirk, not a recognition failure, and
not Slow/Mouse/Sticky Keys.

## How to actually test (confirmed 2026-06-30)

Give the target Mac a **real console session**, then use a **physical keyboard on
it**:

- Attach a **real display**, or an **HDMI dummy-plug / display emulator**, to the
  target Mac. (Confirmed: connecting a real monitor to the Mac mini made the
  physical keyboard work immediately.)
- Press CapsLock on a keyboard **physically attached to the target** (not through
  the Screen Sharing window).
- Watch the target's log at `/tmp/hypercapslock-macos.log`:
  - `Caps(F18) down` → remap effective + tap healthy (working).
  - raw CapsLock seen / nothing → remap not effective or tap not receiving.

## Telltale signature of the artifact

On the remote (target) machine: `/tmp/hypercapslock-macos.log` shows the tap
`INSTALLED` and the `hidutil` remap applied, yet **zero `Caps(F18)`** events ever
— while the *controller's* log shows the full `Caps(F18) down` / `toggling
CapsLock` / `Caps+J -> directional down` sequence at the exact same time. That
means your keypresses were handled on the controller and never reached the
target. Stop; you're testing the wrong machine.
