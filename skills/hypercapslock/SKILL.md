---
name: hypercapslock
description: Configure, inspect, validate, and hot-reload HyperCapslock macOS keyboard mappings, CapsLock+key shortcuts, double-tap modifiers, per-app bindings, input-source switching, and app settings, or answer questions about supported HyperCapslock features. Use when the user mentions HyperCapslock, CapsLock/Hyper remapping, action_mappings.yml, or app_config.yml.
---

# HyperCapslock Agent Skill

HyperCapslock is a native macOS menu-bar app that remaps physical `CapsLock` → `F18` via `hidutil` and intercepts `F18` chords and modifier double-taps via a `CGEventTap`. All mappings and preferences live in human-readable YAML files and can be validated, backed up, applied, hot-reloaded, and rolled back without restarting the app via the built-in zero-UI CLI.

## Reference Documentation

Load these companion references (relative to this `SKILL.md`) whenever authoring or reviewing YAML configs:

- **[`./references/schema-and-actions.md`](./references/schema-and-actions.md)** — Complete YAML schemas for `action_mappings.yml` and `app_config.yml`, all 15 permanent `builtin.*` action IDs, all 4 `Trigger` kinds, all 8 `ActionConfig` kinds, conditional per-app `bindings[]`, `key_remaps`, CJKV IME fix strategies, and real-world YAML recipes.
- **[`./references/keycodes.md`](./references/keycodes.md)** — Exhaustive lookup table of every valid numeric JavaScript `KeyboardEvent.keyCode` (`UInt16`), reserved `F18` (`129`), all 9 `ModifierKey` strings, and `key_remaps` `source`/`destination` enums.

---

## Capability Summary (Answering User Q&A)

When the user asks *"What can HyperCapslock do?"* or *"Can I set up X shortcut?"*, use this capability matrix:

### Supported Triggers (4 kinds)
1. **`CapsLock + Key` & `CapsLock + Shift + Key` (`hyper_plus_key`)**: Hold `CapsLock` (optionally with `Shift`) and press any of the 79 supported keys (`A–Z`, `0–9`, punctuation, arrows, `Space`/`Enter`/`Tab`/`Esc`/`Backspace`/`Fwd Del`, `PgUp`/`PgDn`/`Home`/`End`, `F1–F17`, `F19`).
   - *Automatic Shift-selection fallback*: If `Caps + Shift + <Key>` is not explicitly mapped and `Caps + <Key>` resolves to a `directional`, `jump`, or `backspace` action, holding `Shift` automatically selects text (e.g., `Caps + H` moves left `←`, so `Caps + Shift + H` selects left `⇧←` with zero extra config).
2. **`Single-Tap CapsLock` (`single_tap_hyper`)**: Tap and release `CapsLock` (`≤ 200ms`) without pressing another key. When unmapped, a short tap toggles hardware Caps Lock as usual; map it to `Esc`, an English input source, or `builtin.noop` (to prevent accidental Caps Lock).
3. **`Double-Tap CapsLock` (`double_tap_hyper`)**: Tap `CapsLock` twice within `double_tap_window_ms` (`100–500ms`, default `200ms`).
4. **`Double-Tap Modifier` (`double_tap_modifier`)**: Tap a specific left/right modifier (`left_shift`, `right_shift`, `left_control`, `right_control`, `left_option`, `right_option`, `left_command`, `right_command`, or `fn`) twice within `double_tap_window_ms`.

### Supported Actions (8 kinds + 15 built-ins)
1. **Cursor, Word & Line Navigation (`directional`)**: `left`, `right`, `up`, `down`, `word_forward` (`⌥→`), `word_back` (`⌥←`), `home` (`⌘←`), `end` (`⌘→`).
2. **Multi-Line Vertical Jump (`jump`)**: Jump `up` or `down` by `count` lines (`>= 1`, e.g. `10` lines via `builtin.jump_up_10` / `builtin.jump_down_10`).
3. **Editing & Utility (`independent`)**: `backspace` (composes with `⌥`/`⌘`), `next_line` (`⌘→` then `↵` — opens a new line below from mid-line), `insert_quotes` (types `"""|"""` triple quotes with cursor centered), `toggle_caps_lock`, and `noop` (swallows the shortcut cleanly).
4. **Deterministic Input Source / IME Switching (`input_source`)**: Switches directly to a specific Carbon TIS input source ID (e.g. `com.apple.keylayout.ABC` or a Chinese/Japanese/Korean IME), with optional CJKV reliability workarounds (`cjkv_fix_strategy`: `none`, `shortcut_simulation`, `switching_focus`).
5. **Synthesized Key Combos (`key_combo`)**: Sends any key with `Ctrl`, `Option` (`with_alt`), `Cmd`, and/or `Shift` (`with_target_shift`), e.g. `⌘⇧4` screenshot, `⌃⇥` tab switch, `⌘K` command palette.
6. **Launch / Focus / Toggle-Hide Apps (`open_app`)**: Launches or focuses an app by macOS `bundle_id`. By default (`hide_if_frontmost: true`), pressing the shortcut again while the app is frontmost hides it (`⌘H` quake-style toggle).
7. **Shell Commands (`command`)**: Runs any shell snippet asynchronously via `/bin/sh -c "<command>"` (open URLs, Raycast deeplinks, AppleScript, CLI scripts, shortcuts).
8. **Push-to-Talk Held Modifier (`hold_modifier`)**: Holds a side-specific modifier (`left/right` `shift`/`control`/`option`/`command` — **not `fn`**) down for as long as a `Caps + Key` chord is held, releasing on key-up. Ideal for voice dictation / push-to-talk apps (Wispr Flow, Superwhisper, Typeless).

### Per-App Conditional Bindings & Low-Level Key Remaps
- **Per-App Rules (`bindings[]`)**: Any trigger can attach ordered `frontmost_app` rules (`include` allowlist and/or `exclude` denylist of bundle IDs) to run app-specific actions or disable a global mapping (`builtin.noop`) in specific apps (such as Terminal, Xcode, Emacs, or games).
- **Right-Modifier → F13–F19 Remaps (`key_remaps` in `app_config.yml`)**: Repurpose seldom-used right-hand modifiers (`right_command`, `right_option`, `right_control`, `right_shift`) via `hidutil` into conflict-free function keys (`f13`–`f17`, `f19`) for global hotkeys across macOS, while keeping all left-hand modifiers intact.
- **Not Supported**: Remapping arbitrary standalone keys unrelated to `CapsLock`/modifiers, mouse button remapping, binding `F18` (`129`), or holding `fn` via `hold_modifier`.

---

## Critical Safety Rules

1. **NEVER guess numeric `key` or `target_key` codes**: HyperCapslock uses **JavaScript `KeyboardEvent.keyCode`** (`UInt16`) numbers (e.g., `A=65`, `H=72`, `4=52`, `Space=32`, `Enter=13`, `Esc=27`, `;=186`), **NOT** macOS `CGKeyCode` (`kVK_*`) and **NOT** HID usage codes. Always look up [`./references/keycodes.md`](./references/keycodes.md) or run `cli list-keys`.
2. **NEVER use `129` (`F18`)**: `129` (`F18` / `0x4F`) is reserved as HyperCapslock's internal `CapsLock → F18` target. `cli validate` and the engine reject `129` everywhere.
3. **NEVER use `fn` in `hold_modifier`**: `modifier: fn` works **only** in `trigger: { kind: double_tap_modifier, modifier: fn }`. It is forbidden in `action: { kind: hold_modifier, ... }`.
4. **NEVER wipe existing user mappings or unknown keys**: Always read the user's current `action_mappings.yml` / `app_config.yml` first. Modify only what the user asked for, keeping all existing custom `actions`, unrelated `mappings`, and any unrecognized top-level or per-entry YAML keys intact.
5. **Prefer `builtin.*` IDs and reusable `actions[]` IDs**:
   - Reference built-in actions via their 15 permanent `builtin.*` IDs (never invent or rename a `builtin.*` ID).
   - Define custom actions in top-level `actions:` with a fresh UUID (e.g., from `uuidgen`) and reference them via `action_id`—especially when shared across multiple triggers or per-app `bindings`.
   - Never use the retired `builtin.switch_input_source` or `independent: switch_input_source` tombstone (it is a no-op); always use `kind: input_source` with a real `input_source_id`.
6. **NEVER guess `input_source_id` or `bundle_id`**: Run `cli list-input-sources` to inspect exact Carbon TIS IDs on this Mac, and verify app bundle IDs via `osascript -e 'id of app "AppName"'` or `mdls -name kMDItemCFBundleIdentifier -r "/Applications/AppName.app"`.

---

## CLI Interface

### Resolving the Binary (`<BIN>`)
1. If the user prompt specifies a binary path, use it.
2. Otherwise check if an instance is running (`pgrep -lf "HyperCapslock(-Dev)?\.app/Contents/MacOS/"`) or default to:
   - **Release**: `/Applications/HyperCapslock.app/Contents/MacOS/HyperCapslock`
     - Default `data_dir`: `~/Library/Application Support/me.xueshi.hypercapslock`
   - **Dev**: `<DerivedData>/Build/Products/Debug/HyperCapslock-Dev.app/Contents/MacOS/HyperCapslock-Dev`
     - Default `data_dir`: `~/Library/Application Support/me.xueshi.hypercapslock.debug`

### CLI Subcommands
Syntax: `"<BIN>" cli <subcommand> [--data-dir <dir>] [--json]`

| Subcommand | Purpose |
| :--- | :--- |
| `cli info` | Prints active `data_dir`, `action_mappings.yml` & `app_config.yml` paths, bundled `SKILL.md` / `SKILL.zh.md` paths, running app status/PID, active mapping & custom-action counts, and backup count. |
| `cli list-keys` | Prints every valid key name ↔ numeric JS `keyCode` (`UInt16`), all 9 `ModifierKey` values, reserved `F18` (`129`), and `key_remaps` enums. |
| `cli list-builtins` | Lists all 15 permanent `builtin.*` action IDs with English and Chinese descriptions. |
| `cli list-input-sources` | Lists installed/enabled macOS Carbon TIS input sources (`id`, `name`, `isCurrent`, `isCJKV`) on this Mac. |
| `cli validate [--mappings <path>] [--app-config <path>] [--strict]` | Strictly validates YAML syntax, schema, JS keyCodes (`!= 129`), `hold_modifier != fn`, `action_id` resolution, duplicate triggers/IDs, and `app_config` bounds (`hud_duration_ms: 300...6000`, `double_tap_window_ms: 100...500`). Warns on missing local input sources or app `bundle_id`s (`--strict` turns warnings into errors). |
| `cli apply [--mappings <path>] [--app-config <path>] [--strict]` | **Recommended transactional command**: validates staged file(s) → backs up replaced config to `<data_dir>/backups/<name>-<YYYYMMDD-HHmmss>-<UUID>.yml` → writes atomically → triggers live hot-reload in the running app with synchronous IPC ack. |
| `cli reload [--strict]` | Validates on-disk files in `<data_dir>`, backs up the previous in-memory version with `<timestamp>-<UUID>` if changed on disk, and hot-reloads the running app (engine + open SwiftUI UI). |
| `cli backups [--kind mappings\|app-config]` | Lists all `<name>-<YYYYMMDD-HHmmss>-<UUID>.yml` snapshots in `<data_dir>/backups/` (newest first). |
| `cli rollback [--latest \| --file <filename-or-path>] [--kind mappings\|app-config]` | Backs up the current file with `<timestamp>-<UUID>`, restores the selected snapshot (defaults to `--latest`), and hot-reloads immediately. |
| `cli install-skill [--target all\|claude\|codex\|cursor\|antigravity\|windsurf\|cline\|copilot]` | Installs the bundled skill into `~/.agents/skills/hypercapslock` and symlinks it into local coding agents. |
| `cli prompt [--lang zh\|en]` | Prints the localized AI bootstrap prompt with runtime paths for this Mac. |

---

## Step-by-Step Golden Workflow

Always follow this 4-step transactional workflow when reading or changing HyperCapslock configuration:

### Step 1: Inspect Environment & Read Existing YAML
```bash
BIN="/Applications/HyperCapslock.app/Contents/MacOS/HyperCapslock"
"$BIN" cli info --json
```
- Read the existing `action_mappings.yml` and/or `app_config.yml` at the exact paths reported by `cli info`.
- If configuring input sources, run `"$BIN" cli list-input-sources`.
- Consult [`./references/keycodes.md`](./references/keycodes.md) (or `"$BIN" cli list-keys`) and [`./references/schema-and-actions.md`](./references/schema-and-actions.md) for exact schemas and numeric JS `keyCode`s.

### Step 2: Stage Updated YAML to a Temporary File
- Construct the updated YAML preserving all existing custom `actions`, unrelated `mappings`, and unknown keys.
- Write the complete staged YAML to a temporary path (e.g. `/tmp/hypercapslock_mappings_staged.yml` or `/tmp/hypercapslock_app_config_staged.yml`) rather than editing `<data_dir>` directly.

### Step 3: Validate & Apply Transactionally
```bash
"$BIN" cli apply --mappings /tmp/hypercapslock_mappings_staged.yml --json
# Or when updating app settings too:
# "$BIN" cli apply --mappings /tmp/hypercapslock_mappings_staged.yml --app-config /tmp/hypercapslock_app_config_staged.yml --json
```
- If validation fails, fix the staged file using the reported diagnostics and re-run `cli apply` (the user's live config has not been touched).
- *(If a file in `<data_dir>` was already edited directly on disk, run `"$BIN" cli validate` followed by `"$BIN" cli reload`.)*

### Step 4: Verify Reload Ack & Report to User
- Confirm exit code `0` and check the `reload` acknowledgment in the CLI output (if the app is not currently running, inform the user that the validated config was written and will activate when HyperCapslock launches).
- Remove temporary staged file(s) (`rm -f /tmp/hypercapslock_*_staged.yml`).
- Report to the user:
  1. The exact shortcuts/settings added or modified.
  2. The automatic backup snapshot created in `<data_dir>/backups/` (`<name>-<YYYYMMDD-HHmmss>-<UUID>.yml`).
  3. How to revert instantly if needed (`"$BIN" cli rollback --latest --kind mappings`).
