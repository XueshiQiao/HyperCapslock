# HyperCapslock

Native macOS (SwiftUI + AppKit) menu-bar app that remaps CapsLock → F18 via
`hidutil` and intercepts F18+key combos with a `CGEventTap` for vim-style
navigation, editing, input-source switching, key combos, and shell commands.

Ported from the original Tauri 2 (Rust + React) implementation; the YAML config
format is byte-compatible, so existing users' `action_mappings.yml` /
`app_config.yml` load unchanged.

## Single Source of Truth
`project.yml` is the ONLY source of truth for project configuration. Do NOT edit
`.pbxproj` directly. Modify `project.yml` and run `xcodegen generate`.

## ⚠️ Built-in action IDs are a permanent contract
The `builtin.*` IDs in `BuiltinActions.swift` are referenced by users' saved
mappings (`action_id`). **Never rename or remove an existing built-in ID** — it
orphans every mapping that references it. You may *add* new built-ins. Treat the
existing IDs like a public API.

## Config compatibility (2.0-onward)
`action_mappings.yml` is a structured doc `{ actions:, mappings: }`; a legacy
2.0 bare-list is read as mappings-with-inline-actions. Unknown top-level keys
are **preserved on save** (lossless) and never stripped — a newer version's
config must survive being opened by an older build (downgrade-test safety).
Custom actions live in the config; built-ins live in code. Mappings reference an
action by `action_id` (preferred) with an inline action as legacy fallback;
editing a mapping migrates it to an id. Export writes the whole self-contained doc.

## Tech Stack
- Swift 5 language mode, SwiftUI + AppKit, macOS 14.0+
- XcodeGen (`project.yml`); SPM deps: **Sparkle** (auto-update), **Yams** (YAML)
- No App Sandbox (incompatible with CGEventTap / hidutil / IOKit / Carbon TIS)
- Concurrency: Swift 5 mode (NOT Swift 6 strict). The CGEventTap callback is a
  C function pointer driving shared global state via `OSAllocatedUnfairLock` /
  `NSLock` (`EngineState`, `MappingsRegistry`) — the same shape as the Rust
  atomics/mutexes. Strict concurrency fights this pattern; keep Swift 5 mode.

## Structure
- `HyperCapslock/Sources/Engine/` — keyboard engine: `KeyboardHook` (CGEventTap),
  `ActionExecutor`, `ModifierDoubleTap`, `CapsLockState` (IOKit), `InputSource`
  (Carbon TIS), `HidUtil`, `KeyPoster`, `KeyCodes`, `EngineState`, `Constants`
- `HyperCapslock/Sources/Model/` — `ActionModel` (Codable, serde-compatible YAML),
  `ConfigStore`, `AppConfig`, `MappingsRegistry`
- `HyperCapslock/Sources/UI/` — `ContentView` + cards, `AddEditMappingView`,
  `TrayController`, `HudController`/`HudView`, `MainWindowController`, `AppDelegate`
- `HyperCapslock/Sources/Support/` — `FileLog`, `Permissions`, `LaunchAtLogin`,
  `UpdaterManager`, `HudCenter`
- `HyperCapslock/Sources/Localization/L10n.swift` — en/zh/ja/de
- Config persisted to `~/Library/Application Support/me.xueshi.hypercapslock/`

## Build & Run
```bash
brew install xcodegen
xcodegen generate
open HyperCapslock.xcodeproj   # Cmd+R
# or: xcodebuild -scheme HyperCapslock -destination 'platform=macOS' build
```
Requires Accessibility + Input Monitoring permissions (TCC) to install the tap.

## Versioning
- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`; CI overrides
  them from the git tag + run number on release.
- Git tags (`v*`) trigger the signed release pipeline.

## CI/CD (`.github/workflows/build.yml`)
Universal build → Developer ID sign (inside-out, incl. embedded Sparkle.framework)
→ notarize/staple → DMG → Sparkle `sign_update` + `appcast.xml` → GitHub Release
→ `repository-dispatch` to `XueshiQiao/homebrew_tap` and the apps gallery.

### GitHub Secrets Required
- `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD` — Developer ID signing
- `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` (`584KQTRF3B`) — notarization
- `SPARKLE_EDDSA_KEY` — Sparkle private EdDSA key (export: `generate_keys -x key.pem`)
- `HOMEBREW_TAP_PAT`, `GALLERY_UPDATE_PAT` — downstream dispatch tokens

The Sparkle public key (`SUPublicEDKey`) lives in `project.yml`; regenerating the
keypair requires updating both it and the `SPARKLE_EDDSA_KEY` secret.

## Conventions
- 2-space indentation. Encapsulate logic into structs/enums; keep the engine's
  global runtime state behind the lock wrappers in `EngineState`/`MappingsRegistry`.
