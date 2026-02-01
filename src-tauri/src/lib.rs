use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use windows::Win32::Foundation::{HMODULE, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY,
    VK_CAPITAL, VK_DOWN, VK_H, VK_J, VK_K, VK_L, VK_LEFT, VK_RIGHT, VK_UP,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageA, GetMessageA, SetWindowsHookExA, UnhookWindowsHookEx, HHOOK,
    KBDLLHOOKSTRUCT, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP,
};

// Global state
static CAPS_DOWN: AtomicBool = AtomicBool::new(false);
static DID_REMAP: AtomicBool = AtomicBool::new(false);
static IS_PAUSED: AtomicBool = AtomicBool::new(false);
static mut HOOK: HHOOK = HHOOK(0);

// Helper to send key input
unsafe fn send_key(vk: VIRTUAL_KEY, up: bool) {
    let mut flags = KEYBD_EVENT_FLAGS(0);
    if up {
        flags |= KEYEVENTF_KEYUP;
    }

    let input = INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: windows::Win32::UI::Input::KeyboardAndMouse::INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };

    SendInput(&[input], std::mem::size_of::<INPUT>() as i32);
}

// Low-level keyboard hook callback
unsafe extern "system" fn low_level_keyboard_proc(
    code: i32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if code < 0 || IS_PAUSED.load(Ordering::SeqCst) {
        return CallNextHookEx(HOOK, code, wparam, lparam);
    }

    let kbd_struct = &*(lparam.0 as *const KBDLLHOOKSTRUCT);
    let vk = VIRTUAL_KEY(kbd_struct.vkCode as u16);
    let flags = kbd_struct.flags;
    let is_injected = (flags.0 & 0x10) != 0; // LLKHF_INJECTED
    let is_up = wparam.0 as u32 == WM_KEYUP || wparam.0 as u32 == WM_SYSKEYUP;
    let is_down = wparam.0 as u32 == WM_KEYDOWN || wparam.0 as u32 == WM_SYSKEYDOWN;

    // Ignore injected events to prevent loops
    if is_injected {
        return CallNextHookEx(HOOK, code, wparam, lparam);
    }

    // Handle CapsLock Logic
    if vk == VK_CAPITAL {
        if is_down {
            CAPS_DOWN.store(true, Ordering::SeqCst);
            DID_REMAP.store(false, Ordering::SeqCst);
            return LRESULT(1); // Swallow CapsLock Down
        } else if is_up {
            CAPS_DOWN.store(false, Ordering::SeqCst);
            if !DID_REMAP.load(Ordering::SeqCst) {
                // If we didn't use it as a modifier, toggle CapsLock (send Down+Up)
                send_key(VK_CAPITAL, false);
                send_key(VK_CAPITAL, true);
            }
            return LRESULT(1); // Swallow CapsLock Up
        }
    }

    // Handle Remapping (only if CapsLock is held)
    if CAPS_DOWN.load(Ordering::SeqCst) {
        let target = match vk {
            VK_H => Some(VK_LEFT),
            VK_J => Some(VK_DOWN),
            VK_K => Some(VK_UP),
            VK_L => Some(VK_RIGHT),
            _ => None,
        };

        if let Some(target_key) = target {
            DID_REMAP.store(true, Ordering::SeqCst);
            send_key(target_key, is_up);
            return LRESULT(1); // Swallow original key
        }
    }

    CallNextHookEx(HOOK, code, wparam, lparam)
}

fn start_keyboard_hook() {
    thread::spawn(|| unsafe {
        let hook = SetWindowsHookExA(
            WH_KEYBOARD_LL,
            Some(low_level_keyboard_proc),
            HMODULE(0),
            0,
        );

        match hook {
            Ok(h) => {
                HOOK = h;
                println!("Keyboard hook installed successfully.");
                let mut msg = MSG::default();
                while GetMessageA(&mut msg, None, 0, 0).as_bool() {
                    DispatchMessageA(&msg);
                }
                let _ = UnhookWindowsHookEx(HOOK);
            }
            Err(e) => {
                eprintln!("Failed to install keyboard hook: {:?}", e);
            }
        }
    });
}

#[tauri::command]
fn get_status() -> String {
    if IS_PAUSED.load(Ordering::SeqCst) {
        "Paused".to_string()
    } else {
        "Running".to_string()
    }
}

#[tauri::command]
fn set_paused(paused: bool) -> String {
    IS_PAUSED.store(paused, Ordering::SeqCst);
    get_status()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    start_keyboard_hook();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![get_status, set_paused])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}