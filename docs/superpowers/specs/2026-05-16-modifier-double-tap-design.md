# Modifier-Key Double-Tap Triggers — Design

GitHub issue: #2 — *Support double-click event mapping from Modifier Key (Fn,
Shift, Ctrl, Alt, Command) other than the Capslock key.*

Date: 2026-05-16
Status: Approved (brainstorming), pending implementation plan.

## Goal

Let users bind an action to a **double-tap of a modifier key** (Left/Right
Shift, Control, Option, Command, plus Fn), in addition to the existing
double-tap CapsLock trigger. Detection is **opt-in per modifier**: a modifier
is only observed if a mapping for that exact modifier exists.

## Background / current state

- CapsLock is remapped to **F18** via `hidutil`, so it produces clean
  `KeyDown`/`KeyUp` events. Its double-tap path (`handle_short_tap`,
  `LAST_TAP_AT_MS`, deferred-toggle thread, in-flight `AlphaShift` patch) is
  intricate and documented as fragile. **It must not be modified by this
  feature.**
- The other modifiers are **not** remapped. They emit only `FlagsChanged`
  events. The CGEventTap already subscribes to `CGEventType::FlagsChanged`.
- `Trigger` enum today:
  `HyperPlusKey { key, with_shift }` | `DoubleTapHyper`.
- Frontend `Trigger` TS union mirrors this; the Add-Mapping modal trigger
  selector has 3 options: `plain` (Caps), `with_shift` (Caps+Shift),
  `double_tap` (Caps×2).

## Decisions locked during brainstorming

1. **Scope:** Left/Right Shift, Control, Option, Command (reliable) **+ Fn as
   experimental** (best-effort, hardware-dependent, labeled as such).
2. **Per-side binding:** Left vs Right are distinct triggers (HyperCapslock
   users are power users). Tapping Left-then-Right does **not** cross-trigger
   (different keycodes). 9 new triggers total (8 L/R + Fn).
3. **Opt-in detection:** a modifier with no configured `DoubleTapModifier`
   mapping gets **zero** tap bookkeeping — its events pass straight through.
4. **Detection model:** fire on the **2nd clean tap's release**; **never
   suppress/mutate** the modifier event; disqualify a tap if combined with any
   other key or modifier.
5. **Code structure (Decision 1 = A):** an independent per-modifier tap
   detector; the Caps(F18) path stays untouched (no shared abstraction).
6. **UI (Decision 2 = UI-A):** flat dropdown — append 9 labeled entries to the
   existing trigger selector.

## Detailed design

### 1. Config model

Rust (`src-tauri/src/lib.rs`):

```rust
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ModifierKey {
    LeftShift, RightShift,
    LeftControl, RightControl,
    LeftOption, RightOption,
    LeftCommand, RightCommand,
    Fn,
}

// added arm to existing Trigger enum (tag = "kind", rename_all snake_case)
DoubleTapModifier { modifier: ModifierKey },
```

- Serialized form: `{ kind: double_tap_modifier, modifier: left_shift }`.
- `render_action_mappings_yaml_with_comments` gains a branch emitting
  `kind: double_tap_modifier` + `modifier: <name>`.
- The custom `ActionMappingEntry` `Deserialize` already routes `trigger`
  through `Option<Trigger>`; the new variant round-trips with no extra work
  beyond the enum.
- Uniqueness/dedup uses `PartialEq`: `DoubleTapModifier{LeftShift}` ≠
  `DoubleTapModifier{RightShift}` ≠ `DoubleTapHyper`. Each is an independent
  binding in the dedup logic (`upsert_action_mapping_in_vec`,
  `normalize_action_mappings`).

TypeScript (`src/App.tsx`):

```ts
type ModifierKey =
  | "left_shift" | "right_shift"
  | "left_control" | "right_control"
  | "left_option" | "right_option"
  | "left_command" | "right_command"
  | "fn";

type Trigger =
  | { kind: "hyper_plus_key"; key: number; with_shift: boolean }
  | { kind: "double_tap_hyper" }
  | { kind: "double_tap_modifier"; modifier: ModifierKey };
```

### 2. Detection — `src-tauri/src/hook_macos.rs` (Approach A)

macOS modifier keycodes (constants to add):

| Modifier | Left | Right |
|---|---|---|
| Shift | 56 | 60 |
| Control | 59 | 62 |
| Option | 58 | 61 |
| Command | 55 | 54 |
| Fn | 63 (single) | — |

State:

```rust
struct ModTapState {
    last_clean_tap_ms: u64, // 0 = no pending first tap
    press_start_ms: u64,    // 0 = not currently pressed
    armed: bool,            // target modifier currently down, candidate tap
    dirty: bool,            // disqualified (combined with other key/modifier)
}
// 9 slots, index = modifier slot id; single Mutex (callback is the only writer)
static MOD_TAP: Mutex<[ModTapState; 9]> = ...;
```

Helpers:

- `modifier_for_keycode(keycode) -> Option<ModifierKey>` (the table above).
- `configured_double_tap_modifiers() -> ModifierMask` derived from
  `ACTION_MAPPINGS` — quick membership test. If the modifier for an incoming
  FlagsChanged is **not** configured, return immediately (no state writes).
- `flag_mask_for(modifier_family) -> CGEventFlags` — shift→Shift,
  control→Control, option→Alternate, command→Command, fn→SecondaryFn. Used to
  decide press vs release: bit set in `event.get_flags()` ⇒ press, cleared ⇒
  release. Side (L/R) comes from the keycode, not the flag.

Event-tap callback additions (a new branch, after the F18/CapsLock blocks,
before/independent of the Caps pre-empt block — must not alter Caps logic):

- **Non-modifier `KeyDown`** (any regular key): mark every `armed` slot
  `dirty` and clear all `last_clean_tap_ms` (a chord/typing is happening).
- **FlagsChanged for a configured modifier:**
  - *Press* (mask bit now set): if any *other* modifier is currently held →
    set this slot `dirty=true`; else `dirty=false`. Set `armed=true`,
    `press_start_ms=now`. Also mark every *other* armed slot `dirty` (a second
    modifier joined → not a lone tap for either).
  - *Release* (mask bit now cleared): let `held = now - press_start_ms`.
    Clean tap iff `armed && !dirty && held <= CAPS_TAP_MAX_MS` (200ms).
    - If clean and `last_clean_tap_ms != 0 && now - last_clean_tap_ms <=
      DOUBLE_TAP_WINDOW_MS` (300ms) → **fire** the configured action; reset
      slot (`last_clean_tap_ms=0`).
    - Else if clean → `last_clean_tap_ms = now` (pending first tap).
    - Else → leave `last_clean_tap_ms` unchanged (a dirty/long press neither
      arms nor cancels a prior pending first tap from a genuine earlier tap;
      but a chord already cleared pending taps via the KeyDown rule).
    - Always clear `armed`, `press_start_ms`, `dirty` for the slot.
- The FlagsChanged event is returned unmodified (`return None`, never
  `set_type(Null)`), so the modifier behaves 100% normally.
- No timer, no spawned thread, no `AlphaShift` patch — action fires
  synchronously inside the release branch.

Action dispatch reuses whatever `DoubleTapHyper` already does: resolve
`ActionConfig` then execute via the existing action-execution function. See §3.

### 3. Action lookup

`find_double_tap_action()` currently finds the `DoubleTapHyper` mapping.
Generalize to resolve any double-tap trigger:

```rust
fn find_double_tap_action(trigger: &Trigger) -> Option<ActionConfig>
```

(or a sibling `find_double_tap_modifier_action(ModifierKey)`), returning the
`ActionConfig` for `Trigger::DoubleTapModifier{modifier}`. The Caps caller is
updated to pass `Trigger::DoubleTapHyper`; behavior identical. The execution
path (the function that actually performs an `ActionConfig`) is reused as-is.

### 4. UI — `src/App.tsx` + `src/i18n.ts` (UI-A)

- `newTriggerSel` union extends with: `dt_lshift, dt_rshift, dt_lctrl,
  dt_rctrl, dt_lalt, dt_ralt, dt_lcmd, dt_rcmd, dt_fn`.
- Trigger `FormSelect` options: existing 3, then 9 appended, e.g.
  `Double-tap ⇧ Left Shift`, `Double-tap ⌘ Right Command`, `Double-tap 🌐 Fn
  (experimental)`.
- `buildDraftTrigger()` maps each new value to
  `{ kind: "double_tap_modifier", modifier }`.
- `triggerUniqueId` / `triggerSortKey`: stable id/sort per modifier
  (e.g. `dtm:left_shift`); double-tap group sorts before `hyper_plus_key`.
- Mapping-list Kbd render branch for `double_tap_modifier`: render the symbol
  + side + `×2`, e.g. `⇧L ×2` (consistent with the existing `Caps ×2`
  rendering and the ⌘⌃⌥⇧ convention from the modifier-toggle UI work).
- i18n: one label key per modifier across en/zh/ja/de. Symbols (⌘⌃⌥⇧🌐) and
  `×2` are literal; only the descriptive words ("Left"/"Right"/
  "experimental") are localized. Never translate symbols.

### 5. Scope / platform

- **macOS only** for detection. `hook_windows.rs` is **not** implemented for
  this trigger (Windows build is already broken via the pre-existing
  `SHELL_MAPPINGS` issue and intentionally ignored). The config model still
  round-trips on any platform, consistent with `input_source` mappings being
  macOS-gated in the UI.
- **Fn is experimental:** `kCGEventFlagMaskSecondaryFn` / keycode 63 surfacing
  to the tap is hardware-dependent (Apple-silicon laptop vs external vs Magic
  Keyboard). Labeled experimental in the UI; no hardware guarantee.

### 6. Testing

Rust unit tests (extend existing `#[cfg(test)] mod tests` in `lib.rs`):

- serde round-trip for `DoubleTapModifier` for every `ModifierKey` variant.
- `render_action_mappings_yaml_with_comments` output contains
  `kind: double_tap_modifier` and `modifier: <name>` and re-parses equal.
- Legacy YAML (top-level `key`) still loads (regression guard).
- Dedup keeps `LeftShift`/`RightShift`/`DoubleTapHyper` as distinct entries.

Manual on-device verification (macOS):

- Configure double-tap Left ⌘ → an action. Confirm: normal ⌘C and ⌘-Tab
  unaffected; single ⌘ tap = no-op; lone ⌘⌘ within 300ms fires; ⌘ held to
  type ⌘-something never fires.
- Repeat for one Left+Right pair (e.g. L⇧ vs R⇧ bound to different actions —
  each fires only for its own side).
- An **unconfigured** modifier shows zero behavioral change and (per logging)
  zero tap bookkeeping.
- Fn: best-effort check; document result, do not block release on Fn.

No deferred-timer race exists on this path (unlike Caps), so there is no
timing race to test — detection is fully synchronous.

## Risks / notes

- "Other modifier down → mark dirty" must cover the order `⌘ down, ⇧ down, ⇧
  up, ⌘ up` so neither registers a tap. The press-time dirty rule + the
  "other modifier joined → dirty all armed" rule cover this.
- Pure modifiers do not autorepeat, so no FlagsChanged flooding.
- The new branch must be physically separate from, and not reorder, the
  Caps(F18) handling and the documented Caps pre-empt block.

## Out of scope

- Windows implementation.
- Unifying Caps + modifier detection into a shared abstraction (explicitly
  rejected — regression risk to the fragile Caps path).
- Chord triggers on modifiers (e.g. "double-tap Shift then key"); only a bare
  double-tap is in scope.
