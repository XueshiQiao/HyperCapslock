# Modifier forwarding behavior

_Last updated: 2026-05-26 (issue #5)_

When the engine synthesizes a keystroke for an action, it can optionally let the
user's **live-held modifiers** (Shift / Control / Option / Command / fn) "ride
along" into the produced event so the held modifier composes with the action.

The held modifiers are read once per real key event by
`activeModifierFlags(_:)` (`Constants.swift`), which intersects the raw
`CGEventFlags` down to just `[.maskShift, .maskControl, .maskAlternate,
.maskCommand, .maskSecondaryFn]` — auxiliary bits (`maskNumericPad`,
`maskNonCoalesced`, …) are never forwarded. The resulting set is threaded into
`ActionExecutor.execute(_:keyDown:activeModifiers:)` as `activeModifiers`.

`CGEventFlags` is a set, so forwarding is **idempotent**: a modifier an action
already carries (e.g. a `keyCombo` with `cmd: true`) cannot double-apply. The
only risk of forwarding is **semantic** — an accidental extra modifier changing
a canned shortcut — never technical.

## Per trigger path: what `activeModifiers` carries

The decision to forward is split across two layers. First, *how* the action was
triggered determines whether `execute` even receives the held modifiers:

| Trigger path | Code | `activeModifiers` passed to `execute` |
|---|---|---|
| **Caps + key chord** | `handleCapsRemap` | the **real** held flags (this is the path that matters) |
| Caps **single tap** | `fireCapsShortTap` | `[]` — a tap has no "held key" gesture |
| Caps **double tap** | `handleShortTap` | `[]` |
| **Double-tapped modifier** | `fireDoubleTapModifierAction` | **does not call** `execute` for `keyCombo` (synthesizes config-only modifiers in a separate timed sequence); other action kinds call `execute(…, activeModifiers: [])` |

> Double-tap triggers intentionally forward **nothing**. The gesture is "tap a
> key/modifier twice," not "hold modifiers + press," so there is no held-modifier
> intent to carry. Only the **Caps + key chord** path has live modifiers worth
> forwarding.

## Per action kind: what `execute` does with `activeModifiers`

Second, *which* action kind resolved decides what happens to the forwarded
flags. This is the matrix `ActionExecutor.execute` implements:

| Action kind | Sub-case | Forwards held modifiers? | Notes |
|---|---|---|---|
| `directional` | left / right / up / down | ✅ yes | base movement primitive |
| `directional` | wordForward / wordBack | ✅ yes, **+ Option** | `activeModifiers.union(.maskAlternate)` |
| `directional` | home / end | ✅ yes, **+ Cmd** | `activeModifiers.union(.maskCommand)` |
| `jump` | up / down × count | ✅ yes | each repeated tap forwards |
| `independent` | `.backspace` | ✅ yes | single keystroke; e.g. Option+Delete = delete word |
| `independent` | `.nextLine` | ❌ no | fixed compound macro (`Cmd+Right` then `Return`); a stray held Cmd/Option has no coherent meaning and could corrupt a step |
| `independent` | `.insertQuotes` | ❌ no | emits literal `"` text + cursor taps, not a modified keystroke |
| `independent` | `.toggleCapsLock` | n/a | no synthesized target key |
| `independent` | `.switchInputSource` / `.noop` | n/a | no target key (retired tombstone / disabled) |
| `inputSource` | switch to id | n/a | no target key — must NOT forward |
| `command` | shell | n/a | no target key — must NOT forward |
| `keyCombo` | configured combo | ✅ yes | **since issue #5** — seeds flags with `activeModifiers`, then adds configured ctrl/alt/cmd/shift |
| `openApp` | open bundle id | n/a | no target key — must NOT forward |

## Design principle (Option A)

Any action that ultimately **synthesizes a keystroke** forwards the live-held
modifiers, so the same physical `Caps + mod + key` gesture behaves consistently
regardless of which action kind a trigger resolves to. Actions that don't
synthesize a keystroke (run a command, open an app, switch input source) have no
target key to attach modifiers to and keep ignoring them.

Known accepted trade-off: an explicit `Caps + Shift + key → keyCombo` mapping
now has Shift injected into its output. The user must physically hold the extra
modifier for it to apply. If this ever proves annoying, the fallback is a
per-`keyCombo` opt-in toggle (`forward_held_modifiers`, default true) — not built
preemptively (YAGNI).
