# Global Vim-Like Navi

**Global Vim-Like Navi** is a lightweight Windows utility that brings Vim-style navigation (H/J/K/L) to the entire operating system. It allows you to use `CapsLock` + `H/J/K/L` as Arrow keys in any application.

## Features

-   **Global Remapping:** Works in every application (Editors, Browser, Explorer, etc.).
-   **Vim-Style Navigation:**
    -   `CapsLock` + `H` → Left Arrow
    -   `CapsLock` + `J` → Down Arrow
    -   `CapsLock` + `K` → Up Arrow
    -   `CapsLock` + `L` → Right Arrow
-   **Smart CapsLock Handling:**
    -   If used as a modifier (held down with H/J/K/L), the CapsLock state (and light) does **not** toggle.
    -   If tapped and released quickly (without pressing H/J/K/L), it toggles CapsLock on/off as normal.
-   **Native Performance:** Built with **Rust** and the Windows API for zero-latency interception.
-   **Modern UI:** Simple dashboard built with React + TypeScript.

## Screenshots

![](.\public\GlobalVimLikeNavi.png)

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
    git clone https://github.com/your-username/global-vim-like-navi.git
    cd global-vim-like-navi
    ```

2.  **Install dependencies:**
    ```bash
    npm install
    ```

3.  **Run in development mode:**
    ```bash
    npm run tauri dev
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

## License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.
