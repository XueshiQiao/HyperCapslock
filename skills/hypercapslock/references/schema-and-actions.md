# HyperCapslock YAML Schemas, Actions & Recipes

This reference defines the exact wire schemas for `<data_dir>/action_mappings.yml` and `<data_dir>/app_config.yml` as decoded and validated by HyperCapslock.

- Release `<data_dir>`: `~/Library/Application Support/me.xueshi.hypercapslock`
- Dev `<data_dir>`: `~/Library/Application Support/me.xueshi.hypercapslock.debug`
- Backups directory: `<data_dir>/backups/<name>-<YYYYMMDD-HHmmss>-<UUID>.yml`

---

## 1. `action_mappings.yml` Document Structure

`action_mappings.yml` is a structured YAML mapping with two top-level sequences: `actions` (user-defined reusable custom actions) and `mappings` (trigger-to-action bindings).

```yaml
actions:
  - id: "7E9B2D10-4C8A-4F3B-9D1E-0A2B3C4D5E6F"
    name: "Switch to ABC"
    action:
      kind: input_source
      input_source_id: com.apple.keylayout.ABC

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 72
      with_shift: false
    action_id: builtin.move_left
```

### Lossless Compatibility Rules
- **Built-in actions are NEVER written into `actions:`** — they live in app code and are referenced directly via `action_id: builtin.<name>`.
- **Action resolution order on each mapping**:
  1. Per-app `bindings[]` are evaluated top-to-bottom; the first binding whose `when` conditions all match wins.
  2. Otherwise the mapping's fallback `action_id` (preferred) or legacy inline `action` executes.
- **Preservation guarantee**: `ConfigStore` preserves unrecognized top-level keys and unrecognized per-entry keys across saves. Always read the existing file first and keep all existing custom `actions`, unrelated `mappings`, and unknown keys intact.
- **Legacy 2.0 compatibility (read-only awareness)**: Bare top-level sequences (`- key: 72 ...`) decode as `mappings` with `hyper_plus_key`, but you should always write the structured `{ actions: [...], mappings: [...] }` format with nested `trigger:` objects.
- **Trigger deduplication**: Each `trigger` must be unique across `mappings` (`cli validate` flags duplicate triggers).

---

## 2. Permanent Built-in Action IDs (`builtin.*`)

These 15 IDs are a permanent contract. Reference them via `action_id` in `mappings[]` or `bindings[]`. **Never invent, rename, or add custom entries under `actions:` with a `builtin.` prefix.**

| `action_id` | EN Label | Underlying `ActionConfig` | Runtime Behavior |
| :--- | :--- | :--- | :--- |
| `builtin.move_left` | Left | `directional` → `left` | Posts `←` (forwards held modifiers, e.g. `Shift` selects left) |
| `builtin.move_right` | Right | `directional` → `right` | Posts `→` (forwards held modifiers) |
| `builtin.move_up` | Up | `directional` → `up` | Posts `↑` (forwards held modifiers) |
| `builtin.move_down` | Down | `directional` → `down` | Posts `↓` (forwards held modifiers) |
| `builtin.word_forward` | Word Forward | `directional` → `word_forward` | Posts `⌥→` (composes with `Shift` for `⌥⇧→` word selection) |
| `builtin.word_back` | Word Back | `directional` → `word_back` | Posts `⌥←` (composes with `Shift` for `⌥⇧←` word selection) |
| `builtin.line_start` | Home / Line Start | `directional` → `home` | Posts `⌘←` (composes with `Shift` for `⌘⇧←` line selection) |
| `builtin.line_end` | End / Line End | `directional` → `end` | Posts `⌘→` (composes with `Shift` for `⌘⇧→` line selection) |
| `builtin.jump_up_10` | Jump Up 10 | `jump` → `up`, `count: 10` | Taps `↑` 10 times (forwards held modifiers) |
| `builtin.jump_down_10` | Jump Down 10 | `jump` → `down`, `count: 10` | Taps `↓` 10 times (forwards held modifiers) |
| `builtin.backspace` | Backspace | `independent` → `backspace` | Posts `⌫` Delete (composes with `⌥` for word-delete / `⌘` for line-delete) |
| `builtin.new_line` | Next Line | `independent` → `next_line` | Taps `⌘→` then `↵` (opens a new line below without splitting the current line) |
| `builtin.insert_quotes` | Insert Quotes | `independent` → `insert_quotes` | Inserts `""""""` (6 double quotes) and moves left 3 times (`"""\|"""`) |
| `builtin.toggle_caps_lock` | Toggle Caps Lock | `independent` → `toggle_caps_lock` | Toggles hardware Caps Lock state directly via IOKit |
| `builtin.noop` | Do Nothing | `independent` → `noop` | Swallows the key chord and performs no action |

> **Retired Tombstone Warning**: `builtin.switch_input_source` and `independent` `action: switch_input_source` are retired no-op tombstones kept solely so ancient configs do not fail YAML decoding. Never emit them—always use `kind: input_source` with a real Carbon TIS `input_source_id`.

---

## 3. Custom Actions Library (`actions[]`)

Define reusable custom actions in top-level `actions:` and reference their `id` from `mappings[].action_id` or `bindings[].action_id`.

```yaml
actions:
  - id: "9A1F4E20-8B7C-4D5E-A123-456789ABCDEF"   # Unique string ID (UUID recommended; NEVER `builtin.*`)
    name: "Open Ghostty"                          # Human-readable name shown in UI & HUD
    action:                                       # Any of the 8 ActionConfig shapes below
      kind: open_app
      bundle_id: com.mitchellh.ghostty
      app_name: Ghostty
```

---

## 4. All 4 `Trigger` Kinds

`trigger` is an internally-tagged YAML mapping discriminated by `kind`:

### 4.1 `hyper_plus_key` (`CapsLock + Key` / `CapsLock + Shift + Key`)
```yaml
trigger:
  kind: hyper_plus_key
  key: 72           # Required: UInt16 JS KeyboardEvent.keyCode (see ./keycodes.md; NEVER 129)
  with_shift: false # Optional Bool (defaults to false; true = CapsLock + Shift + Key)
```
- **Automatic Shift-Selection Fallback**: When the user presses `CapsLock + Shift + <Key>` and there is **no** explicit `with_shift: true` entry for `<Key>`, HyperCapslock checks the `with_shift: false` entry for `<Key>`. If its effective action (after evaluating per-app `bindings[]`) is `directional`, `jump`, or `independent` (excluding `noop`), it fires that action and forwards `Shift`. Actions of kind `input_source`, `command`, `key_combo`, `open_app`, `hold_modifier`, and `independent: noop` do **not** fall back on Shift.

### 4.2 `single_tap_hyper` (`CapsLock × 1`)
```yaml
trigger:
  kind: single_tap_hyper
```
- Fires when `CapsLock` is tapped briefly (`≤ 200ms`) and released with no chord key pressed.
- **Default when unmapped**: Toggles hardware Caps Lock. Adding a `single_tap_hyper` mapping replaces that default (e.g. map to `Esc` for Vim, an English input source, or `builtin.noop` to disable Caps Lock completely).

### 4.3 `double_tap_hyper` (`CapsLock × 2`)
```yaml
trigger:
  kind: double_tap_hyper
```
- Fires when `CapsLock` is tapped twice within `double_tap_window_ms` (`100..500`, default `200ms`).
- When configured, a single tap waits `double_tap_window_ms` before executing `single_tap_hyper` (or native Caps Lock toggle) so a second tap can convert it into `double_tap_hyper`.

### 4.4 `double_tap_modifier` (`Modifier × 2`)
```yaml
trigger:
  kind: double_tap_modifier
  modifier: left_shift
```
- `modifier` accepts **all 9** `ModifierKey` values:
  `left_shift`, `right_shift`, `left_control`, `right_control`, `left_option`, `right_option`, `left_command`, `right_command`, `fn`.

---

## 5. All 8 `ActionConfig` Kinds

`action` (inside `actions[].action`, `mappings[].action`, or `bindings[].action`) is an internally-tagged YAML mapping discriminated by `kind`:

### 5.1 `directional` — Cursor, Word & Line Navigation
```yaml
action:
  kind: directional
  action: word_forward # left | right | up | down | word_forward | word_back | home | end
```
*(Tip: All 8 `directional` variants already exist as `builtin.*` IDs—prefer referencing `builtin.move_left`, `builtin.word_forward`, `builtin.line_start`, etc.)*

### 5.2 `jump` — Multi-Line Vertical Jump
```yaml
action:
  kind: jump
  direction: down # up | down
  count: 5        # Int >= 1 (10-line jumps are built in as builtin.jump_up_10 / builtin.jump_down_10)
```

### 5.3 `independent` — Standalone Editing & Utility Actions
```yaml
action:
  kind: independent
  action: backspace # backspace | next_line | insert_quotes | toggle_caps_lock | noop
```
*(Tip: All 5 active `independent` variants exist as `builtin.*` IDs—prefer referencing `builtin.backspace`, `builtin.new_line`, `builtin.insert_quotes`, `builtin.toggle_caps_lock`, `builtin.noop`.)*

### 5.4 `input_source` — Switch macOS Input Source / IME
```yaml
action:
  kind: input_source
  input_source_id: com.apple.keylayout.ABC # Non-empty Carbon TIS ID from `cli list-input-sources`
```
- Always inspect installed input sources on the user's Mac with `"<BIN>" cli list-input-sources` first.
- If switching to a Chinese/Japanese/Korean/Vietnamese IME updates the menu-bar icon without activating the IME engine, set `cjkv_fix_strategy: switching_focus` (or `shortcut_simulation`) in `app_config.yml`.

### 5.5 `command` — Execute Shell Command
```yaml
action:
  kind: command
  command: "open -g 'raycast://extensions/raycast/clipboard-history/clipboard-history'"
```
- `command` must be non-empty. Executed asynchronously off the event-tap thread via `/bin/sh -c "<command>"`.

### 5.6 `key_combo` — Synthesize Keyboard Shortcut
```yaml
action:
  kind: key_combo
  target_key: 52          # UInt16 JS keyCode (see ./keycodes.md; NEVER 129)
  with_ctrl: false        # Bool (default false) — Control ⌃
  with_alt: false         # Bool (default false) — Option ⌥
  with_cmd: true          # Bool (default false) — Command ⌘
  with_target_shift: true # Bool (default false) — Shift ⇧
```
- Live-held physical modifiers compose with the configured flags when triggered from a chord.

### 5.7 `open_app` — Launch, Focus, or Toggle-Hide Application
```yaml
action:
  kind: open_app
  bundle_id: com.google.Chrome # Required non-empty bundle identifier
  app_name: Google Chrome      # Display name for UI & HUD
  hide_if_frontmost: false     # Optional Bool (default true; omitted on save when true)
```
- When `hide_if_frontmost` is `true` (the default), pressing the shortcut while the app is already frontmost hides it (`⌘H`). Set `hide_if_frontmost: false` if pressing the shortcut should always keep the app focused without hiding.

### 5.8 `hold_modifier` — Hold Modifier While Chord Is Pressed (Push-to-Talk)
```yaml
action:
  kind: hold_modifier
  modifier: right_option # left_shift | right_shift | left_control | right_control | left_option | right_option | left_command | right_command
```
- **FORBIDDEN VALUE**: `modifier: fn` is **NOT** allowed in `hold_modifier` (`KeyCodes.modifierKeyAndFlag(.fn)` is `nil`, rejected by `cli validate`).
- **Pair with `hyper_plus_key`**: Holds the synthesized modifier down while `CapsLock + <Key>` stays held and releases it cleanly on key-up (no key-repeat spam). Only one `hold_modifier` chord is held at a time. Do not pair with tap-only triggers (`single_tap_hyper`, `double_tap_hyper`, `double_tap_modifier`), which immediately press and release.

---

## 6. Per-App Conditional Overrides (`bindings[]`)

Every mapping entry in `mappings:` can attach an optional `bindings:` sequence of conditional rules evaluated **in declaration order** before the mapping's default `action_id` / `action`.

```yaml
mappings:
  - trigger:
      kind: hyper_plus_key
      key: 75 # K
      with_shift: false
    action_id: builtin.move_up # Fallback everywhere else
    bindings:
      - when:
          - type: frontmost_app
            include:
              - com.tinyspeck.slackmacgap
              - com.linear
            exclude: [] # Optional; omit when empty
        action_id: "3F11A9C0-1122-4334-9556-778899AABBCC"
```

### Validation & Matching Semantics
- Each binding in `bindings[]` **must** have:
  1. A non-empty `when:` list of conditions (all conditions in `when` must hold — logical AND).
  2. Either `action_id` (referencing a valid `builtin.*` or custom `actions[].id`) or an inline `action`.
- `frontmost_app` condition:
  - Compares bundle identifiers **case-insensitively** against the current frontmost app.
  - At least one of `include` or `exclude` must be non-empty (both empty matches nothing).
  - If `include` is non-empty, the frontmost app must be in `include`.
  - If `exclude` is non-empty, the frontmost app must NOT be in `exclude`.
- **Three common patterns**:
  1. **App-specific override + global default**: Put app overrides in `bindings[]` and keep the normal global `action_id` on the mapping.
  2. **Disable a global shortcut in specific apps**: Add a binding with `include: ["com.apple.Terminal"]` and `action_id: builtin.noop` (note: `noop` swallows the `Caps+Key` chord rather than typing the plain letter).
  3. **Shortcut active ONLY in specific apps**: Set the mapping's fallback `action_id: builtin.noop` and list target apps in `bindings[]`.

---

## 7. `app_config.yml` Schema, `key_remaps` & CJKV Strategies

All keys in `app_config.yml` are optional on decode (missing keys use defaults), and `cli validate` enforces numeric ranges and enum tokens.

```yaml
hide_dock_icon: false
show_hud: true
hud_duration_ms: 1350
double_tap_window_ms: 200
theme_mode: system
cjkv_fix_strategy: switching_focus
broadcast_caps_hold_for_anydrag: false
mappings_view_style: keyboard
stats_show_inline: true
show_window_on_launch: true
analytics_enabled: true
key_remaps:
  - source: right_option
    destination: f17
  - source: right_command
    destination: f19
```

### Field Reference

| Key | Type & Allowed Values | Default | Notes & Bounds |
| :--- | :--- | :--- | :--- |
| `hide_dock_icon` | `Bool` | `false` | `true` hides the Dock icon (menu-bar-only mode). |
| `show_hud` | `Bool` | `false` | Show floating on-screen HUD capsule when mappings trigger. |
| `hud_duration_ms` | `Int` (`300...6000`) | `1350` | HUD visibility duration in milliseconds (`300` min, `6000` max). |
| `double_tap_window_ms` | `Int` (`100...500`) | `200` | Max gap in ms between two taps for `double_tap_hyper` and `double_tap_modifier`. |
| `theme_mode` | `light` \| `dark` \| `system` | `system` | App window appearance mode. |
| `cjkv_fix_strategy` | `none` \| `shortcut_simulation` \| `switching_focus` | `none` | Workaround for macOS CJKV IME switching bug (see below). |
| `broadcast_caps_hold_for_anydrag` | `Bool` | `false` | Broadcasts CapsLock hold notifications over `DistributedNotificationCenter` for **AnyDrag** window dragging. |
| `mappings_view_style` | `keyboard` \| `grouped` | `keyboard` | Mappings tab layout (`keyboard` visual map or `grouped` list). |
| `stats_show_inline` | `Bool` | `true` | Show press counts inline on Mappings page rows. |
| `show_window_on_launch` | `Bool` | `true` | `false` launches silently into the menu bar without opening the main window. |
| `analytics_enabled` | `Bool` | `true` | Anonymous, non-identifying Aptabase telemetry (never sends keystrokes or user content). |
| `key_remaps` | `[KeyRemap]` | `[]` | Low-level `hidutil` remaps from spare right modifiers to free function keys `f13`–`f17`, `f19`. |

### CJKV Input-Source Fix Strategies (`cjkv_fix_strategy`)
On macOS, calling `TISSelectInputSource` directly on Chinese, Japanese, Korean, Vietnamese, or Russian IMEs can update the menu-bar icon while leaving actual typing stuck in the previous layout. HyperCapslock provides three modes (applied **only** when switching to a CJKV/Russian IME; pure keyboard layouts like `ABC` always use fast direct selection):
- `none` *(default)*: Plain `TISSelectInputSource` with zero overhead. Use first; switch strategy only if the user's IME exhibits stale typing state.
- `switching_focus` *(recommended when fixing CJKV bugs)*: Briefly activates an invisible 80ms helper window to force macOS to commit the new IME context (adapted from macism / Input Source Pro). Works without requiring system keyboard shortcuts.
- `shortcut_simulation`: Synthesizes the macOS system input-source switching shortcut after selecting the target IME. Requires *"Select the previous input source"* / *"Select next source in Input menu"* to be enabled in macOS **System Settings → Keyboard → Keyboard Shortcuts → Input Sources**.

### Low-Level Right-Modifier Remaps (`key_remaps`)
Repurposes seldom-used right-hand modifiers via `hidutil` (alongside `CapsLock → F18`) into function keys that macOS leaves unassigned, while keeping left-hand modifiers untouched:
- `source` (must be unique per entry): `right_command` | `right_option` | `right_control` | `right_shift`
- `destination`: `f13` | `f14` | `f15` | `f16` | `f17` | `f19` *(Note: `f18` is reserved and forbidden)*

---

## 8. Real-World Copy-Pasteable YAML Recipes

### Recipe 1: Complete Vim Navigation & Editing Layer (`HJKL` + Word + Line + 10x Jump)
*(Note: Because automatic Shift-fallback is built in, `Caps + Shift + H/J/K/L/W/B/A/E` will automatically select text without needing duplicate `with_shift: true` entries!)*
```yaml
actions: []
mappings:
  - trigger: { kind: hyper_plus_key, key: 72, with_shift: false } # Caps + H
    action_id: builtin.move_left
  - trigger: { kind: hyper_plus_key, key: 74, with_shift: false } # Caps + J
    action_id: builtin.move_down
  - trigger: { kind: hyper_plus_key, key: 75, with_shift: false } # Caps + K
    action_id: builtin.move_up
  - trigger: { kind: hyper_plus_key, key: 76, with_shift: false } # Caps + L
    action_id: builtin.move_right
  - trigger: { kind: hyper_plus_key, key: 87, with_shift: false } # Caps + W
    action_id: builtin.word_forward
  - trigger: { kind: hyper_plus_key, key: 66, with_shift: false } # Caps + B
    action_id: builtin.word_back
  - trigger: { kind: hyper_plus_key, key: 65, with_shift: false } # Caps + A
    action_id: builtin.line_start
  - trigger: { kind: hyper_plus_key, key: 69, with_shift: false } # Caps + E
    action_id: builtin.line_end
  - trigger: { kind: hyper_plus_key, key: 85, with_shift: false } # Caps + U
    action_id: builtin.jump_up_10
  - trigger: { kind: hyper_plus_key, key: 68, with_shift: false } # Caps + D
    action_id: builtin.jump_down_10
  - trigger: { kind: hyper_plus_key, key: 73, with_shift: false } # Caps + I
    action_id: builtin.backspace
  - trigger: { kind: hyper_plus_key, key: 79, with_shift: false } # Caps + O
    action_id: builtin.new_line
```

### Recipe 2: Deterministic EN / ZH Input Source Switching (`Left Shift ×2` / `Right Shift ×2`)
*(Always verify actual IDs on the target Mac with `cli list-input-sources` first.)*
```yaml
actions:
  - id: "11111111-2222-4333-8444-555555555501"
    name: "English (ABC)"
    action:
      kind: input_source
      input_source_id: com.apple.keylayout.ABC
  - id: "11111111-2222-4333-8444-555555555502"
    name: "Simplified Chinese Pinyin"
    action:
      kind: input_source
      input_source_id: com.apple.inputmethod.SCIM.ITABC

mappings:
  - trigger:
      kind: double_tap_modifier
      modifier: left_shift
    action_id: "11111111-2222-4333-8444-555555555501"
  - trigger:
      kind: double_tap_modifier
      modifier: right_shift
    action_id: "11111111-2222-4333-8444-555555555502"
```

### Recipe 3: Single-Tap CapsLock → `Esc` (Vim Modal Escape) & Double-Tap CapsLock → Toggle Caps Lock
```yaml
actions:
  - id: "22222222-3333-4444-8555-666666666601"
    name: "Escape Key"
    action:
      kind: key_combo
      target_key: 27 # Esc
      with_ctrl: false
      with_alt: false
      with_cmd: false
      with_target_shift: false

mappings:
  - trigger:
      kind: single_tap_hyper
    action_id: "22222222-3333-4444-8555-666666666601"
  - trigger:
      kind: double_tap_hyper
    action_id: builtin.toggle_caps_lock
```

### Recipe 4: Quake-Style App Toggle (`Caps + T` Ghostty, `Caps + C` Chrome, `Caps + S` Slack Always-Focus)
```yaml
actions:
  - id: "33333333-4444-4555-8666-777777777701"
    name: "Toggle Ghostty"
    action:
      kind: open_app
      bundle_id: com.mitchellh.ghostty
      app_name: Ghostty
  - id: "33333333-4444-4555-8666-777777777702"
    name: "Toggle Google Chrome"
    action:
      kind: open_app
      bundle_id: com.google.Chrome
      app_name: Google Chrome
  - id: "33333333-4444-4555-8666-777777777703"
    name: "Focus Slack (Never Hide)"
    action:
      kind: open_app
      bundle_id: com.tinyspeck.slackmacgap
      app_name: Slack
      hide_if_frontmost: false

mappings:
  - trigger: { kind: hyper_plus_key, key: 84, with_shift: false } # Caps + T
    action_id: "33333333-4444-4555-8666-777777777701"
  - trigger: { kind: hyper_plus_key, key: 67, with_shift: false } # Caps + C
    action_id: "33333333-4444-4555-8666-777777777702"
  - trigger: { kind: hyper_plus_key, key: 83, with_shift: false } # Caps + S
    action_id: "33333333-4444-4555-8666-777777777703"
```

### Recipe 5: Per-App Conditional Bindings (`Caps + P` Command Palette by App, Disabled in Emacs)
```yaml
actions:
  - id: "44444444-5555-4666-8777-888888888801"
    name: "Cmd+Shift+P Command Palette"
    action:
      kind: key_combo
      target_key: 80 # P
      with_ctrl: false
      with_alt: false
      with_cmd: true
      with_target_shift: true
  - id: "44444444-5555-4666-8777-888888888802"
    name: "Cmd+K Quick Switcher"
    action:
      kind: key_combo
      target_key: 75 # K
      with_ctrl: false
      with_alt: false
      with_cmd: true
      with_target_shift: false

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 80 # Caps + P
      with_shift: false
    action_id: "44444444-5555-4666-8777-888888888802" # Global fallback: Cmd+K
    bindings:
      - when:
          - type: frontmost_app
            include:
              - com.microsoft.VSCode
              - com.todesktop.230313mzl4w4u92 # Cursor
        action_id: "44444444-5555-4666-8777-888888888801" # VS Code / Cursor: Cmd+Shift+P
      - when:
          - type: frontmost_app
            include:
              - org.gnu.Emacs
        action_id: builtin.noop # Inert in Emacs
```

### Recipe 6: Push-to-Talk Voice Dictation (`Caps + Space` → Hold `right_option`) & `Fn ×2` Trigger
```yaml
actions:
  - id: "55555555-6666-4777-8888-999999999901"
    name: "Push-to-Talk (Hold Right Option)"
    action:
      kind: hold_modifier
      modifier: right_option # Hold Caps+Space to talk, release to finish (never use `fn` here!)
  - id: "55555555-6666-4777-8888-999999999902"
    name: "Area Screenshot (Cmd+Shift+4)"
    action:
      kind: key_combo
      target_key: 52 # 4
      with_ctrl: false
      with_alt: false
      with_cmd: true
      with_target_shift: true

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 32 # Space
      with_shift: false
    action_id: "55555555-6666-4777-8888-999999999901"
  - trigger:
      kind: double_tap_modifier
      modifier: fn # `fn` IS valid in double_tap_modifier!
    action_id: "55555555-6666-4777-8888-999999999902"
```

### Recipe 7: Shell Automation (`Caps + R` Raycast Clipboard) & `app_config.yml` with `key_remaps`
`action_mappings.yml` snippet:
```yaml
actions:
  - id: "66666666-7777-4888-8999-AAAAAAAAAA01"
    name: "Raycast Clipboard History"
    action:
      kind: command
      command: "open -g 'raycast://extensions/raycast/clipboard-history/clipboard-history'"

mappings:
  - trigger:
      kind: hyper_plus_key
      key: 82 # Caps + R
      with_shift: false
    action_id: "66666666-7777-4888-8999-AAAAAAAAAA01"
```

`app_config.yml`:
```yaml
hide_dock_icon: true
show_hud: true
hud_duration_ms: 1200
double_tap_window_ms: 220
theme_mode: system
cjkv_fix_strategy: switching_focus
broadcast_caps_hold_for_anydrag: false
mappings_view_style: keyboard
stats_show_inline: true
show_window_on_launch: false
analytics_enabled: true
key_remaps:
  - source: right_option
    destination: f17
  - source: right_command
    destination: f19
```
