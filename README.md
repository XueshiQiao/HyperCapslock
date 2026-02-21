# HyperCapslock

**HyperCapslock**: Make your Capslock Powerful again!

## Features

-   **Global Remapping:** Works in every application (Editors, Browser, Explorer, etc.).
-   **macOS Input Source Mappings:** Configure `CapsLock` + `Key` to switch to a specific macOS input source ID (for example ABC / WeChat).
-   **Smart CapsLock Handling:**
    -   If used as a modifier (held down with mapped keys), the CapsLock state (and light) does **not** toggle.
    -   If tapped and released quickly (without pressing other keys), it toggles CapsLock on/off as normal.
-   **Native Performance:** Built with **Rust** and the Windows API for zero-latency interception.
-   **System Tray:** Supports minimizing to tray, pausing the service (Gaming Mode), and starting with Windows.

## Key Mappings

### Basic Navigation
-   `CapsLock` + `H` → **Left Arrow**
-   `CapsLock` + `J` → **Down Arrow**
-   `CapsLock` + `K` → **Up Arrow**
-   `CapsLock` + `L` → **Right Arrow**

### Extended Navigation
-   `CapsLock` + `P` → **Next Word** (Ctrl + Right)
-   `CapsLock` + `Y` → **Previous Word** (Ctrl + Left)
-   `CapsLock` + `A` → **Home** (Start of line)
-   `CapsLock` + `E` → **End** (End of line)
-   `CapsLock` + `U` → **Up 10x** (Fast Scroll Up)
-   `CapsLock` + `D` → **Down 10x** (Fast Scroll Down)

### Editing Shortcuts
-   `CapsLock` + `I` → **Backspace**
-   `CapsLock` + `O` → **New Line** (End + Enter)
-   `CapsLock` + `N` → **Docstring Snippet** (Inserts `""""""` and centers cursor)

### Shell Mappings
-   `CapsLock` + `Shift` + `[Key]` → **Execute Shell Command**
    -   User configurable via the UI.
    -   Example: `CapsLock` + `Shift` + `C` → `calc.exe`

### macOS Input Source Mappings
-   `CapsLock` + `[Key]` → **Switch macOS input source** (by exact input source ID)
-   User configurable via the UI on macOS.
-   First-run defaults:
    -   `CapsLock` + `,` → `com.apple.keylayout.ABC`
    -   `CapsLock` + `.` → `com.tencent.inputmethod.wetype.pinyin`
-   Mapping targets use exact source IDs (no fuzzy display-name matching).

## Screenshots

<div align="center">
    <img src="./public/HyperCapslock.png" style="width: 720;" />
</div>

## Architecture

This project is a hybrid application built with [Tauri](https://tauri.app/):

1.  **Frontend (React + TypeScript):**
    -   Displays the application status ("Running") and instructions.
    -   Communicates with the backend via Tauri commands.

2.  **Backend (Rust):**
    -   Uses the `windows` crate to access the Win32 API.
    -   Installs a **Low-Level Keyboard Hook** (`WH_KEYBOARD_LL`) via `SetWindowsHookEx`.
    -   Intercepts keystrokes at the system level to perform remapping before they reach other applications.
    -   Runs in a dedicated background thread to ensure responsiveness.

For a deep dive into the technical implementation, see [how_does_it_work.md](how_does_it_work.md).

## Prerequisites

-   **Windows 10/11**
-   **Node.js** (v16+)
-   **Rust** (latest stable)

## Development Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/XueshiQiao/HyperCapslock.git
    cd HyperCapslock
    ```

2.  **Install dependencies:**
    ```bash
    npm install
    ```

3.  **Run in development mode:**
    ```bash
    npm run tauri dev
    # or
    pnpm tauri dev
    ```
    This will start the React frontend and the Rust backend.

## Building for Production

To create a standalone executable (`.exe`):

```bash
npm run tauri build
```

The output file will be located at:
`src-tauri/target/release/tauri-app.exe`

## Usage Note

**Privilege Levels:**
On Windows, applications running with lower privileges cannot intercept keys from applications running with higher privileges (Administrator).
-   If you want this tool to work inside Task Manager, Admin Powershell, or other Admin-level apps, you must run `tauri-app.exe` as **Administrator**.

## macOS Troubleshooting

If hotkeys stop working intermittently on macOS:

1. Check permissions:
   - `System Settings > Privacy & Security > Accessibility`
   - `System Settings > Privacy & Security > Input Monitoring` (if enabled in your setup)
   - Remove and re-add the app if needed, then relaunch.
2. Check runtime logs:
   - File log: `/tmp/hypercapslock-macos.log`
   - You can also run from terminal and watch stderr output.
3. Look for these log patterns:
   - `Event tap disabled by system` (tap timeout / dropped by macOS)
   - `hidutil remap failed` (CapsLock->F18 remap not applied)
   - `Failed to create CGEventTap` (permission or tap creation issue)
   - `Caps(F18) down` and `Caps remap handled keydown` (normal hotkey path)

## License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.
