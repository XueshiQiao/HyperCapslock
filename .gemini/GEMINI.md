
# Project: HyperCapslock
The project 'HyperCapslock' is a Tauri app (React+TS frontend, Rust backend) that remaps CapsLock+H/J/K/L to Arrow keys using 'windows'
  crate for low-level hooks. Now support more than 10 key mappings.
## General Instructions
  - Fixed the white screen (FOUC) issue on startup for HyperCapslock by hiding the main window in tauri.conf.json and showing it via the
  frontend after initialization.

## Coding Style
  - Use two spaces for indentation.
  - For Rust/Typescript code, encapsulate logic to a class if possible.

  -
