# HyperCapslock

Tauri 2 desktop app that remaps CapsLock to F18 and intercepts F18+key combos for vim-style navigation, editing, input switching, and shell commands.

## Tech Stack
- **Backend:** Rust (edition 2021) — Tauri 2 with `CGEventTap`/`hidutil` on macOS, `windows` crate low-level hooks on Windows
- **Frontend:** React 19 + TypeScript, Vite, Tailwind CSS 4
- **Platforms:** macOS 12+, Windows (partial)
- **State:** Lock-free atomics (`AtomicBool`, `AtomicU64`) for hook callbacks; `Mutex<Option<T>>` for shared config

## Structure
- `src/` — Frontend (single `App.tsx` is the entire UI)
- `src-tauri/src/` — Rust backend: `lib.rs` (core + Tauri commands), `hook_macos.rs`, `hook_windows.rs`
- Config stored as YAML via `serde_yaml`, persisted to app data dir

## Dev Commands
```bash
npm install
npm run tauri dev    # dev with hot reload
npm run tauri build  # production build
```

## Conventions
- 2-space indentation for both Rust and TypeScript
- Encapsulate logic into classes/structs where possible
