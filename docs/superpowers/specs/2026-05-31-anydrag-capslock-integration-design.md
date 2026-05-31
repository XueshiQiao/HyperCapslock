# HyperCapslock ↔ AnyDrag — CapsLock-Hold Window Drag Integration — Design

Date: 2026-05-31 · Spans two repos: **HyperCapslock** (publisher) and **AnyDrag** (subscriber)

> Updated to reflect the shipped design: a generic in-process observer hub +
> plugin on the HyperCapslock side, a virtual "Hyper" modifier + liveness
> watchdog on the AnyDrag side. (The original draft used a single hard-wired
> broadcast; that was refactored before merge.)

## Goal

Let the user **hold CapsLock and drag any window** by reusing AnyDrag's
window-server title-bar drag — instead of holding one of AnyDrag's modifier
keys. Holding CapsLock arms AnyDrag's **full gesture set** (move-drag,
double-click-maximize, right-click-tiling), exactly as a real modifier would.
Plain CapsLock vim-chords stay 100% free (they're keyboard-only; dragging is
mouse-only, so they never collide).

## Why a cross-app signal is required

- AnyDrag arms only off modifier `CGEventFlags` on the mouse-down event
  (`DragEngine.matchesConfiguredModifier`). CapsLock is **not** a modifier flag.
- HyperCapslock remaps CapsLock→F18 at the HID level and its tap **swallows F18**
  (`KeyboardHook.swift` `return nil`), so AnyDrag can't see a flag or an F18
  keypress. (We keep swallowing F18 — leaking it would fire F18 elsewhere.)
- So the apps cooperate via an explicit one-way signal over
  `DistributedNotificationCenter`. Built-in, no entitlement (neither app is
  sandboxed), and human reaction-time between pressing CapsLock and clicking
  makes its latency irrelevant.

## Wire contract (4 names, owned by the plugins only)

| Name | Direction | Meaning |
|------|-----------|---------|
| `me.xueshi.hypercapslock.capsHoldBegan` | HC → AD | a hold started |
| `me.xueshi.hypercapslock.capsHoldEnded` | HC → AD | a hold ended |
| `me.xueshi.hypercapslock.capsHoldPing`  | AD → HC | "are you alive?" (10 Hz while held) |
| `me.xueshi.hypercapslock.capsHoldPong`  | HC → AD | "alive" |

No `userInfo` payload — state is encoded by *which* name fires. These strings
live **only** in `AnyDragCapsHoldBridge` (HC) and `HyperCapslockCapsHoldSource`
(AD); every other file is integration-agnostic. They are a permanent contract.

## HyperCapslock side — generic hub + one plugin

The engine never mentions AnyDrag. A generic observer hub sits between the
CapsLock lifecycle and any consumer:

- **`CapsHoldObserver`** — protocol with `capsHoldBegan()` / `capsHoldEnded()`.
- **`CapsHoldCenter`** — singleton weak-observer registry behind
  `OSAllocatedUnfairLock`. Observer **membership is the on/off switch** (no
  separate flag). Tracks `isHeld`, so `add`/`remove` reconcile a mid-hold plugin
  (add → `capsHoldBegan` if held; remove → `capsHoldEnded` if held).
  `notifyBegan/notifyEnded` snapshot under the lock, then fan out **off** the
  lock (no re-entrancy/deadlock).
- **Lifecycle hooks** — `beginCapsHold()` (fresh `capsDown` transition +
  bookkeeping + `notifyBegan`) and `endCapsHold() -> Bool` (`capsDown`→false +
  `notifyEnded`, idempotent). `KeyboardHook` calls these on F18 down/up; the
  hold-end hook is also called from **every abnormal exit** — pause, terminate,
  tap-disabled recovery, tap-loop teardown — so a hold can't stay latched.
- **`AnyDragCapsHoldBridge`** — the only file aware AnyDrag exists. A
  `CapsHoldObserver` plugin that broadcasts `capsHoldBegan/Ended` and answers
  pings with a pong (purely reactive). Its lifetime equals the user's setting:
  `AppState` creates + `add`s it when enabled, `remove`s + releases it when
  disabled (which also tears down the ping responder).
- **Setting** `broadcast_caps_hold_for_anydrag` (`AppConfig`, default **off**) +
  a Settings toggle, localized en/zh/ja/de.

Observer methods fire **synchronously on the firing thread** (the tap thread for
key down/up). Chosen over async-to-main so `began`/`ended` can never reorder and
so terminate flushes before exit; the cost is one distributed post per caps
down/up (not per keystroke), which is negligible.

## AnyDrag side — a virtual modifier + watchdog

- **`ModifierCombination.hyper`** (bit `1<<5`, **no** `CGEventFlag`) — a virtual
  modifier meaning "CapsLock held". Shown as a 6th chip (glyph **⇪**, the macOS
  CapsLock symbol) in the modifier row, with a hint that it needs HyperCapslock.
  Persists inside the existing `modifierFlags` bitmask (no new key).
- **`HyperCapslockCapsHoldSource`** — the only AnyDrag file aware of the wire
  protocol. Owns the cross-process listeners (began/ended/pong on main) and a
  `isHeld` flag (behind a lock; read on the tap thread). `DragEngine.modifiers`'
  `didSet` drives `setEnabled(contains(.hyper))`; `matchesConfiguredModifier`
  early-returns armed when `modifiers.contains(.hyper) && source.isHeld`.
- **Liveness watchdog** — while held and enabled, pings every **100 ms**; if no
  pong arrives within **1 s** it treats HyperCapslock as gone and ends the hold
  (so a `kill -9` disarms AnyDrag within ~1 s — equivalent to releasing the
  modifier; an in-flight window-server drag finishes at mouse-up). Graceful exits
  (pause/quit/disable) still fire `capsHoldEnded` and disarm instantly; the
  watchdog is only the hard-kill backstop. HyperCapslock is purely reactive — it
  never pings.
- **Hyper is mutually exclusive** with the flag chips: selecting one clears the
  other (`ModifierChipRow`), and `ModifierCombination.hyperNormalized` sanitizes
  any stale persisted "Hyper + flags" value on load (Hyper wins). This keeps the
  UI honest, since the engine arms on a hold OR a flag combo, never a mix.

## Accepted edges / tradeoffs

- **Sub-200 ms flick-drag** may be misclassified by HyperCapslock as a short tap
  (its tap can't see the mouse), firing the CapsLock tap action. Rare; accepted.
- **Hard-kill** of HyperCapslock leaves AnyDrag armed for up to ~1 s until the
  watchdog fires. Accepted (bounded by the heartbeat).
- **Plain-var tap-thread reads** of `modifiers`/feature flags in AnyDrag are the
  app's pre-existing lock-free convention; not changed here.

## Failure modes (all benign)

- AnyDrag not running / setting off → HC posts into the void.
- HC not running / plugin removed → no began/ended; AnyDrag's source never arms,
  and a mid-hold removal disarms via the watchdog.

## Out of scope

- Toggle/sticky drag mode (we chose hold-to-drag).
- Any payload beyond the four bare names.
