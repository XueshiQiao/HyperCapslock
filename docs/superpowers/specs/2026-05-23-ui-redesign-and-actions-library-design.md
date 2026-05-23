# UI Redesign + Actions Library — Design

Date: 2026-05-23 · Branch: `feat/ui-redesign`

## Goals
- Replace the single-page UI with a macOS-native **sidebar + content** layout
  (`NavigationSplitView`), visual **Design B (branded)**: blue→purple gradient
  accents, breathing status dot, HUD-style 3D keycaps, glassy cards.
- Sidebar order: **1 Settings · 2 Mappings · 3 Actions · 4 About**.
- **Theme: light / dark / system** (follow OS appearance).
- Use the app's **own AppIcon** in the UI (sidebar brand, status card, About).
- Introduce a first-class **Actions library**: built-in (code-defined) + custom
  (user-defined). Mappings bind a trigger → an action.

## Data Model

### Action (library entry)
- `id: String` — built-in: stable slug `builtin.<name>`; custom: UUID string.
- `name: String` — built-ins localized in code; custom set by user.
- `config: ActionConfig` — the existing action enum (directional / jump /
  independent / input_source / command / key_combo).
- `isBuiltin: Bool` — true iff `id` is in the code-defined catalog.

### Built-in catalog (code-defined, NEVER persisted)
Stable IDs (**permanent contract — never rename/remove**, see Constraints):
`builtin.move_left|move_right|move_up|move_down|word_forward|word_back|`
`line_start|line_end|jump_up_10|jump_down_10|backspace|new_line|insert_quotes|`
`toggle_caps_lock|switch_input_source`. Concrete presets matching current defaults.
Machine-specific input-source-by-id (ABC / WeChat) are NOT built-ins — they ship
as default **mappings with inline** `input_source` actions; users may create
custom input-source actions.

### Mapping
- `trigger: Trigger` (unchanged).
- `actionId: String?` — preferred binding.
- `inlineAction: ActionConfig?` — legacy / unmigrated.
- **Resolution order:** `actionId` resolves in library → use it; else
  `inlineAction` present → use it; else **invalid** (log + ⚠️ badge in UI; the
  binding does nothing but is never silently dropped).

### Config file (`action_mappings.yml` — structured document)
```yaml
actions:                       # custom actions only (built-ins are code-defined)
  - id: <uuid>
    name: "Open Calculator"
    action: { kind: command, command: "open -a Calculator" }
mappings:
  - trigger: { kind: hyper_plus_key, key: 72, with_shift: false }
    action_id: builtin.move_left          # preferred
  - trigger: { kind: hyper_plus_key, key: 188, with_shift: false }
    action: { kind: input_source, input_source_id: com.apple.keylayout.ABC }  # inline (legacy/unmigrated)
```
**Reading (tolerant):**
- Root is a **sequence** → legacy 2.0 format: a bare mappings list, each with an
  inline action; no custom actions.
- Root is a **mapping** with `mappings:` / `actions:` → new format.
- Unknown keys (document-level and per-entry) are **ignored + logged**, and
  **preserved on save** (lossless round-trip). Unrecognized config is NEVER
  stripped/deleted.

### Lossless round-trip (hard requirement)
- No pre-2.0 (Tauri) compat, but **2.0-onward forward/backward compat**: a newer
  version's extra fields read by an older build must survive a save unchanged
  (so downgrading e.g. 3.0→2.8 for testing never washes 3.0's config).
- Implementation: decode known fields; capture remaining keys (doc + each
  action/mapping entry) into `[String: Yams.Node]`; re-emit them on encode. Save
  via Yams `Node` round-trip rather than the old hand-rolled comment renderer
  (losing the `# comments` header is an accepted trade-off for losslessness).

## Migration (gradual inline → id)
- The Mappings editor binds by **selecting a library Action** → stores
  `action_id`, clears `inlineAction`.
- Legacy bare-list configs load with inline actions intact; each migrates to an
  id on next edit. No bulk rewrite.

## Export / Import
- **Export** = write the whole structured document (custom actions + mappings).
  Self-contained & portable: built-ins are universal across 2.x; custom actions
  travel inside the file. No inline-expansion needed.
- **Import** = read document, replace current mappings + merge custom actions;
  tolerant of unknown fields.

## Delete protection
- Deleting a **custom** action scans all mappings for `action_id` references
  (inline copies are self-contained and don't count). If referenced → **block**
  the delete and list the **specific triggers** that use it. Built-in actions
  expose no delete affordance.

## Theme (3-state)
- `ThemeMode { light, dark, system }` persisted in `app_config.yml`.
- Apply: `system` → follow `NSApp.effectiveAppearance` (preferredColorScheme nil);
  `light`/`dark` → force via `NSApp.appearance` + SwiftUI `preferredColorScheme`.

## UI (SwiftUI `NavigationSplitView`, Design B)
- **Sidebar:** app-icon brand + name + version; 4 nav items; running/paused
  status footer.
- **Settings:** status card (app icon, running/paused, Pause/Resume);
  Permissions (Accessibility); General (Start at Login, Hide Dock Icon, Show
  HUD + duration); Appearance (Language, Theme 3-state).
- **Mappings:** grouped list; HUD-style trigger keycaps; resolved action name
  (or ⚠️ invalid); add / edit / delete; import / export. Editor picks an Action
  from the library (with a “+ New Action” shortcut that creates then selects one).
- **Actions:** aggregated list — Built-in section (read-only, shows “what it
  does”, not deletable) + Custom section (add / edit / delete). Each row shows
  name, a description, and how many mappings reference it.
- **About:** app icon, name, version, Check for Updates (Sparkle), GitHub / X /
  xueshi.dev links, license.

## Constraints / Docs
- **Built-in action IDs are a permanent contract.** Document in `AGENTS.md` and
  comment in `BuiltinActions.swift` so future edits never rename/remove them
  (would orphan user mappings).

## Out of scope (for this iteration)
- Reusable triggers, per-app profiles, action import-by-URL. Not now.
