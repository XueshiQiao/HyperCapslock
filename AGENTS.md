# HyperCapslock

## ⚠️ Rule #0 — After any app-code change, rebuild AND relaunch the dev build (kill the old one first)
Whenever you modify app code (anything affecting runtime behavior), the moment
the build succeeds you MUST relaunch the latest dev build — do NOT wait to be
asked. The user verifies behavior by interacting with the running app; the agent
cannot test interactive behavior itself, so an un-relaunched build means the
change is untested.

**Relaunch is kill-then-open, always in this order** — a second `open` while an
instance is already running is a no-op (the new process never takes over), so a
stale binary keeps running and you'd be "testing" old code.

**Kill EVERY HyperCapslock instance first — both Dev AND Release.** Both builds
install the same global `CGEventTap` + hidutil CapsLock→F18 remap. If the user's
**Release** app (`HyperCapslock.app`) is running, it already owns that global
keyboard hook, so a freshly-launched Dev instance fights it for the same global
state and your test is invalid/unreliable. So before launching Dev, terminate
the Release one too — do NOT spare it.
```bash
# match the app BINARIES (Dev + Release), not unrelated procs whose cwd merely
# contains "HyperCapslock" (e.g. a Codex broker) — those lack .app/Contents/MacOS/
pkill -f "HyperCapslock(-Dev)?\.app/Contents/MacOS/HyperCapslock" 2>/dev/null
sleep 1
pgrep -lf "HyperCapslock.app/Contents/MacOS"   # confirm NONE remain
open "<DerivedData>/Build/Products/Debug/HyperCapslock-Dev.app"
sleep 1
pgrep -lf "HyperCapslock-Dev"   # confirm exactly one fresh PID
```
This is standard procedure — the user should never have to ask for it. (Restart
the user's Release app yourself only if they ask; the point is the Dev test must
run with no competing instance.)

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
Requires the Accessibility permission (TCC) to install the tap. (Input
Monitoring is NOT needed — that's only for `.listenOnly` taps; this app uses an
active `.defaultTap`, which macOS gates on Accessibility.)

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
