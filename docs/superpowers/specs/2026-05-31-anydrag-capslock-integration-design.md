# HyperCapslock ↔ AnyDrag — CapsLock-Hold Window Drag Integration — Design

Date: 2026-05-31 · Spans two repos: **HyperCapslock** (publisher) and **AnyDrag** (subscriber)

## Goal

Let the user **hold CapsLock and left-drag any window to move it**, by reusing
AnyDrag's existing window-server title-bar drag — instead of holding one of
AnyDrag's modifier keys (Option/Cmd/Ctrl/fn). Plain CapsLock vim-chords stay
100% free; the gesture is hold-to-drag (no toggle, no mode).

## Why a cross-app signal is required

- AnyDrag arms **only** off modifier `CGEventFlags` carried on the mouse-down
  event (`DragEngine.matchesConfiguredModifier`). CapsLock is **not** a modifier
  flag.
- HyperCapslock remaps CapsLock→F18 at the HID level and its tap **swallows F18
  entirely** (`KeyboardHook.swift` `return nil`), so AnyDrag can neither see a
  CapsLock modifier flag nor an F18 keypress. (We deliberately keep swallowing
  F18 — leaking it would fire F18 in other apps.)
- Therefore the two apps cooperate via an explicit, lightweight, **one-way
  signal**: HyperCapslock broadcasts "CapsLock is held / released"; AnyDrag
  treats that as an arming source. No mouse-event tampering; no reliance on
  event-tap ordering (which would be fragile).

## Transport: `DistributedNotificationCenter`

Built-in macOS cross-process pub/sub. Chosen over CFMessagePort/XPC (point-to-
point, far heavier than a boolean) and app-group UserDefaults (needs entitlement
+ polling). Neither app is sandboxed, so DNC works with no entitlement. There is
always human reaction-time between pressing CapsLock and clicking, so DNC's
tens-of-ms latency is invisible for this gesture.

### Shared contract (must match byte-for-byte in both repos)

Two distinct notification names, **no `userInfo` payload** (avoids any
cross-process plist-serialization quirk — state is encoded by *which* name fires):

| Name | Posted when |
|------|-------------|
| `me.xueshi.hypercapslock.capsHoldBegan` | F18 (CapsLock) key-down, on fresh `capsDown` transition |
| `me.xueshi.hypercapslock.capsHoldEnded` | F18 (CapsLock) key-up |

Posted with `deliverImmediately: true`, `object: nil`, `userInfo: nil`.
One-to-one with the physical CapsLock key. The names are a **permanent contract**
between the two apps — treat like a public API; don't rename.

## HyperCapslock side (publisher)

**Setting** — add to `AppConfig` / `app_config.yml`, **default `false`**:
`broadcastCapsHoldForAnyDrag` (UI label e.g. *"Broadcast CapsLock hold for
AnyDrag"*, with a one-line explainer). Unknown-key preservation rules already
guarantee older builds keep the field on save. When `false`, **post nothing** —
zero chatter for users who don't run AnyDrag.

**Emit points** — in `KeyboardHook.swift`, inside the existing F18 branch:
- F18 keyDown, **only on the fresh `!wasDown` transition** (mirror line ~54): if
  the setting is on, post `capsHoldBegan`.
- F18 keyUp (`wasDown`): if the setting is on, post `capsHoldEnded`.

**Threading** — the tap callback runs on the dedicated tap thread. Post **off
the tap thread** (`DispatchQueue.main.async { … }`) so the callback stays lean.
Latency tolerance is high, so this dispatch costs nothing perceptible.

**Pairing guarantee** — emit Began only on the `!wasDown` edge and Ended on every
key-up, matching the existing state transitions, so Began/Ended stay balanced
even across rapid taps. (A short tap sends Began then Ended quickly; with no
intervening click, AnyDrag does nothing.)

**Read of setting from the tap thread** — read the bool through the same
lock-guarded accessor pattern used for other engine-visible config
(`EngineState`/registry), so the tap thread sees updates safely. Detail to pin
down in the plan after reading how `isPaused`/config currently reach the tap.

## AnyDrag side (subscriber)

**New arming source** — add a *"CapsLock (via HyperCapslock)"* selectable entry
to AnyDrag's modifier picker, persisted in `Preferences`. Model it as a source
distinct from the flag-based `ModifierCombination` (it is not a flag). When
enabled, it is OR-ed into the arming decision.

**Observer + state** — register `DistributedNotificationCenter` observers for the
two names; maintain a single `capsHeldExternally` bool (set true on Began, false
on Ended). Observers fire on the main thread; publish the bool to the drag engine
via whatever thread-safe path the engine already uses for its config/flags.

**Arming hook** — in `DragEngine`, when the CapsLock source is enabled, treat the
modifier requirement as satisfied at mouse-down whenever `capsHeldExternally ==
true` (i.e. `matchesConfiguredModifier` returns true via this path). Because
AnyDrag hands the drag to the window server, **arming only needs to be true at
the instant of mouse-down**; releasing CapsLock mid-drag harmlessly lets the
in-flight drag finish at mouse-up. No need to react to Ended during a drag.

## Behavior that falls out for free

- **Chords stay free** — CapsLock vim-chords are keyboard-only; dragging is
  mouse-only. They never collide. Holding CapsLock while *also* clicking is the
  intended drag gesture.
- **No accidental CapsLock** — any real drag is held >200ms, and HyperCapslock
  already suppresses the native CapsLock toggle for holds >`capsTapMaxMs`
  (=200ms).
- **Accepted edge (decision: Approach A)** — HyperCapslock's tap can't see the
  mouse, so a **sub-200ms flick-drag** may be misclassified as a short tap and
  fire the CapsLock short-tap action. Rare; explicitly accepted. (Approach B —
  an AnyDrag→HyperCapslock back-signal to suppress it — was considered and
  declined for simplicity.)

## Failure modes (all benign)

- AnyDrag not running / observer absent → HyperCapslock posts into the void.
- HyperCapslock not running, or setting off → no notifications → AnyDrag's
  `capsHeldExternally` stays false → the CapsLock source simply never arms.
- Either app updated independently → the notification-name contract is the only
  coupling; keep the strings identical.

## Out of scope

- Toggle / sticky "drag mode" (we chose hold-to-drag).
- Any payload beyond the two bare names (no key identity, no timing data).
- AnyDrag's double-click-maximize / right-click tiling via CapsLock — only the
  move-drag is in scope.

## Touch list

**HyperCapslock**: `AppConfig` (new bool + persistence), settings UI (toggle),
`KeyboardHook.swift` (two posts), a small constant/helper for the notification
names.
**AnyDrag**: `Preferences.swift` (new source pref), modifier picker UI (new
entry), `DragEngine.swift` (observers + `capsHeldExternally` + arming hook),
matching notification-name constants.
