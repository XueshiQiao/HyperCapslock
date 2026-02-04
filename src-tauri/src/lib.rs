use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri::image::Image;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::UpdaterExt;
use windows::Win32::Foundation::{HMODULE, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP,
    KEYEVENTF_UNICODE, VIRTUAL_KEY, VK_A, VK_B, VK_BACK, VK_CAPITAL, VK_D, VK_DELETE, VK_DOWN, VK_E, VK_END,
    VK_H, VK_HOME, VK_I, VK_J, VK_K, VK_L, VK_LCONTROL, VK_LEFT, VK_N, VK_O, VK_RETURN, VK_RIGHT,
    VK_U, VK_UP, VK_W,
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
// Store the menu item handle safely
static TRAY_TOGGLE_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static TRAY_STATUS_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);

static ICON_RUNNING: &[u8] = include_bytes!("../icons/icon.png");
static ICON_DISABLED: &[u8] = include_bytes!("../icons/icon_disabled.png");

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

// Helper to send unicode character
unsafe fn send_unicode(ch: u16) {
    // Key Down
    let input_down = INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: windows::Win32::UI::Input::KeyboardAndMouse::INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(0),
                wScan: ch,
                dwFlags: KEYEVENTF_UNICODE,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };

    // Key Up
    let input_up = INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: windows::Win32::UI::Input::KeyboardAndMouse::INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(0),
                wScan: ch,
                dwFlags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    };

    SendInput(&[input_down, input_up], std::mem::size_of::<INPUT>() as i32);
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
        let mut handled = false;

        match vk {
            // Standard Vim
            VK_H => {
                send_key(VK_LEFT, is_up);
                handled = true;
            }
            VK_J => {
                send_key(VK_DOWN, is_up);
                handled = true;
            }
            VK_K => {
                send_key(VK_UP, is_up);
                handled = true;
            }
            VK_L => {
                send_key(VK_RIGHT, is_up);
                handled = true;
            }

            // Editing
            VK_I => {
                send_key(VK_BACK, is_up);
                handled = true;
            }

            // Code Snippets
            VK_N => {
                if is_down {
                    for _ in 0..6 {
                        send_unicode(34);
                    }
                    for _ in 0..3 {
                        send_key(VK_LEFT, false);
                        send_key(VK_LEFT, true);
                    }
                }
                handled = true;
            }

            // Word Navigation
            VK_W => {
                // Ctrl + Right
                if is_down {
                    send_key(VK_LCONTROL, false);
                    send_key(VK_RIGHT, false);
                } else {
                    send_key(VK_RIGHT, true);
                    send_key(VK_LCONTROL, true);
                }
                handled = true;
            }
            VK_B => {
                // Ctrl + Left
                if is_down {
                    send_key(VK_LCONTROL, false);
                    send_key(VK_LEFT, false);
                } else {
                    send_key(VK_LEFT, true);
                    send_key(VK_LCONTROL, true);
                }
                handled = true;
            }

            // Home / End
            VK_A => {
                send_key(VK_HOME, is_up);
                handled = true;
            }
            VK_E => {
                send_key(VK_END, is_up);
                handled = true;
            }

            // Fast Scroll (10x)
            VK_U => {
                if is_down {
                    for _ in 0..10 {
                        send_key(VK_UP, false);
                        send_key(VK_UP, true);
                    }
                }
                handled = true;
            }
            VK_D => {
                if is_down {
                    for _ in 0..10 {
                        send_key(VK_DOWN, false);
                        send_key(VK_DOWN, true);
                    }
                }
                handled = true;
            }

            // New Line (End + Enter)
            VK_O => {
                if is_down {
                    send_key(VK_END, false);
                    send_key(VK_END, true);
                    send_key(VK_RETURN, false);
                    send_key(VK_RETURN, true);
                }
                handled = true;
            }

            _ => {}
        }

        if handled {
            DID_REMAP.store(true, Ordering::SeqCst);
            return LRESULT(1); // Swallow original key
        }
    }

    CallNextHookEx(HOOK, code, wparam, lparam)
}

fn start_keyboard_hook() {
    thread::spawn(|| unsafe {
        let hook = SetWindowsHookExA(WH_KEYBOARD_LL, Some(low_level_keyboard_proc), HMODULE(0), 0);

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

fn update_tray_visuals(app: &AppHandle, paused: bool) {
    // Update Menu Text
    if let Ok(guard) = TRAY_TOGGLE_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(if paused { "Start Service" } else { "Stop Service" });
        }
    }
    if let Ok(guard) = TRAY_STATUS_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(if paused { "Status: Paused" } else { "Status: Running" });
        }
    }

    // Update Tray Icon
    let icon_bytes = if paused { ICON_DISABLED } else { ICON_RUNNING };
    if let Ok(image) = Image::from_bytes(icon_bytes) {
        if let Some(tray) = app.tray_by_id("tray") {
            let _ = tray.set_icon(Some(image));
        }
    }
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
fn set_paused(app: AppHandle, paused: bool) -> String {
    IS_PAUSED.store(paused, Ordering::SeqCst);

    update_tray_visuals(&app, paused);

    // Emit event for UI to stay in sync if called from elsewhere (sanity check)
    let _ = app.emit("status-update", paused);

    get_status()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    start_keyboard_hook();

    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_autostart::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .setup(|app| {
            let status_i = MenuItem::with_id(app, "status", "Status: Running", false, None::<&str>)?;
            let toggle_i = MenuItem::with_id(app, "toggle", "Stop Service", true, None::<&str>)?;
            let check_update_i = MenuItem::with_id(app, "check_update", "Check for Updates", true, None::<&str>)?;
            let sep = PredefinedMenuItem::separator(app)?;
            let show_i = MenuItem::with_id(app, "show", "Open window", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

            // Store handles
            if let Ok(mut guard) = TRAY_TOGGLE_ITEM.lock() {
                *guard = Some(toggle_i.clone());
            }
            if let Ok(mut guard) = TRAY_STATUS_ITEM.lock() {
                *guard = Some(status_i.clone());
            }

            let menu = Menu::with_items(app, &[&status_i, &toggle_i, &check_update_i, &sep, &show_i, &quit_i])?;

                        let _tray = TrayIconBuilder::with_id("tray")
                            .menu(&menu)
                            .icon(app.default_window_icon().unwrap().clone())
                            .on_menu_event(move |app, event| {
                                match event.id.as_ref() {
                                    "check_update" => {
                                        let app_handle = app.clone();
                                        tauri::async_runtime::spawn(async move {
                                            if let Ok(updater) = app_handle.updater() {
                                                match updater.check().await {
                                                    Ok(Some(update)) => {
                                                        let should_install = app_handle.dialog()
                                                            .message(format!("Version {} is available. Do you want to install it?", update.version))
                                                            .title("Update Available")
                                                            .kind(MessageDialogKind::Info)
                                                            .buttons(MessageDialogButtons::OkCancel)
                                                            .blocking_show();
                                                        
                                                        if should_install {
                                                            if let Err(e) = update.download_and_install(|_,_| {}, || {}).await {
                                                                app_handle.dialog()
                                                                    .message(format!("Failed to install update: {}", e))
                                                                    .kind(MessageDialogKind::Error)
                                                                    .blocking_show();
                                                            } else {
                                                                app_handle.dialog()
                                                                    .message("Update installed. Application will restart.")
                                                                    .kind(MessageDialogKind::Info)
                                                                    .blocking_show();
                                                                app_handle.restart();
                                                            }
                                                        }
                                                    }
                                                    Ok(None) => {
                                                         app_handle.dialog()
                                                            .message("You are on the latest version.")
                                                            .title("No Update Available")
                                                            .kind(MessageDialogKind::Info)
                                                            .blocking_show();
                                                    }
                                                    Err(e) => {
                                                        app_handle.dialog()
                                                            .message(format!("Failed to check for updates: {}", e))
                                                            .kind(MessageDialogKind::Error)
                                                            .blocking_show();
                                                    }
                                                }
                                            }
                                        });
                                    }
                                    "show" => {
                                        if let Some(window) = app.get_webview_window("main") {
                                            let _ = window.show();
                                            let _ = window.set_focus();
                                        }
                                    }
                                    "quit" => {
                                        app.exit(0);
                                    }
                                    "toggle" => {
                                        let paused = !IS_PAUSED.load(Ordering::SeqCst);
                                        IS_PAUSED.store(paused, Ordering::SeqCst);
                                        
                                        update_tray_visuals(app, paused);
                                        
                                        // Emit event to frontend
                                        let _ = app.emit("status-update", paused); 
                                    }
                                    _ => {}
                                }
                            })
                            .on_tray_icon_event(|tray, event| {
                                if let tauri::tray::TrayIconEvent::DoubleClick {
                                    button: tauri::tray::MouseButton::Left,
                                    ..
                                } = event {
                                    let app = tray.app_handle();
                                    if let Some(window) = app.get_webview_window("main") {
                                        let _ = window.show();
                                        let _ = window.set_focus();
                                    }
                                }
                            })
                            .build(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_status, set_paused])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
