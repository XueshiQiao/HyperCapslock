use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::UpdaterExt;

#[cfg(target_os = "windows")]
mod hook_windows;
#[cfg(target_os = "macos")]
mod hook_macos;

// Global state (shared across platforms)
static CAPS_DOWN: AtomicBool = AtomicBool::new(false);
static DID_REMAP: AtomicBool = AtomicBool::new(false);
static IS_PAUSED: AtomicBool = AtomicBool::new(false);
static TRAY_TOGGLE_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static TRAY_STATUS_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static SHELL_MAPPINGS: Mutex<Option<HashMap<u16, String>>> = Mutex::new(None);

fn get_config_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("shell_mappings.json"))
}

fn load_mappings_from_disk(app: &AppHandle) {
    if let Some(path) = get_config_path(app) {
        if let Ok(content) = fs::read_to_string(path) {
            if let Ok(mappings) = serde_json::from_str::<HashMap<u16, String>>(&content) {
                *SHELL_MAPPINGS.lock().unwrap() = Some(mappings);
                return;
            }
        }
    }
    let mut guard = SHELL_MAPPINGS.lock().unwrap();
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
}

fn save_mappings_to_disk(app: &AppHandle) {
    if let Some(path) = get_config_path(app) {
        if let Some(mappings) = &*SHELL_MAPPINGS.lock().unwrap() {
            if let Ok(content) = serde_json::to_string(mappings) {
                if let Some(parent) = path.parent() {
                    let _ = fs::create_dir_all(parent);
                }
                let _ = fs::write(path, content);
            }
        }
    }
}

static ICON_RUNNING: &[u8] = include_bytes!("../icons/icon.png");
static ICON_DISABLED: &[u8] = include_bytes!("../icons/icon_disabled.png");

fn update_tray_visuals(app: &AppHandle, paused: bool) {
    if let Ok(guard) = TRAY_TOGGLE_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(if paused {
                "Start Service"
            } else {
                "Stop Service"
            });
        }
    }
    if let Ok(guard) = TRAY_STATUS_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(if paused {
                "Status: Paused"
            } else {
                "Status: Running"
            });
        }
    }

    let icon_bytes = if paused { ICON_DISABLED } else { ICON_RUNNING };
    if let Ok(image) = Image::from_bytes(icon_bytes) {
        if let Some(tray) = app.tray_by_id("tray") {
            let _ = tray.set_icon(Some(image));
        }
    }
}

#[tauri::command]
fn add_mapping(app: AppHandle, key: u16, command: String) {
    {
        let mut guard = SHELL_MAPPINGS.lock().unwrap();
        if let Some(map) = guard.as_mut() {
            map.insert(key, command);
        }
    }
    save_mappings_to_disk(&app);
}

#[tauri::command]
fn remove_mapping(app: AppHandle, key: u16) {
    {
        let mut guard = SHELL_MAPPINGS.lock().unwrap();
        if let Some(map) = guard.as_mut() {
            map.remove(&key);
        }
    }
    save_mappings_to_disk(&app);
}

#[tauri::command]
fn get_mappings() -> HashMap<u16, String> {
    let guard = SHELL_MAPPINGS.lock().unwrap();
    guard.clone().unwrap_or_default()
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
    eprintln!(
        "[HYPERCAPS][STATE] Service {}",
        if paused { "paused" } else { "resumed" }
    );

    update_tray_visuals(&app, paused);

    let _ = app.emit("status-update", paused);

    get_status()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(target_os = "windows")]
    hook_windows::start_keyboard_hook();
    #[cfg(target_os = "macos")]
    hook_macos::start_keyboard_hook();

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
            load_mappings_from_disk(app.handle());
            let status_i =
                MenuItem::with_id(app, "status", "Status: Running", false, None::<&str>)?;
            let toggle_i =
                MenuItem::with_id(app, "toggle", "Stop Service", true, None::<&str>)?;
            let check_update_i =
                MenuItem::with_id(app, "check_update", "Check for Updates", true, None::<&str>)?;
            let sep = PredefinedMenuItem::separator(app)?;
            let show_i = MenuItem::with_id(app, "show", "Open window", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

            if let Ok(mut guard) = TRAY_TOGGLE_ITEM.lock() {
                *guard = Some(toggle_i.clone());
            }
            if let Ok(mut guard) = TRAY_STATUS_ITEM.lock() {
                *guard = Some(status_i.clone());
            }

            let menu = Menu::with_items(
                app,
                &[
                    &status_i,
                    &toggle_i,
                    &check_update_i,
                    &sep,
                    &show_i,
                    &quit_i,
                ],
            )?;

            let _tray = TrayIconBuilder::with_id("tray")
                .menu(&menu)
                .icon(app.default_window_icon().unwrap().clone())
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "check_update" => {
                        let app_handle = app.clone();
                        tauri::async_runtime::spawn(async move {
                            if let Ok(updater) = app_handle.updater() {
                                match updater.check().await {
                                    Ok(Some(update)) => {
                                        let should_install = app_handle
                                            .dialog()
                                            .message(format!(
                                                "Version {} is available. Do you want to install it?",
                                                update.version
                                            ))
                                            .title("Update Available")
                                            .kind(MessageDialogKind::Info)
                                            .buttons(MessageDialogButtons::OkCancel)
                                            .blocking_show();

                                        if should_install {
                                            if let Err(e) =
                                                update.download_and_install(|_, _| {}, || {}).await
                                            {
                                                app_handle
                                                    .dialog()
                                                    .message(format!(
                                                        "Failed to install update: {}",
                                                        e
                                                    ))
                                                    .kind(MessageDialogKind::Error)
                                                    .blocking_show();
                                            } else {
                                                app_handle
                                                    .dialog()
                                                    .message(
                                                        "Update installed. Application will restart.",
                                                    )
                                                    .kind(MessageDialogKind::Info)
                                                    .blocking_show();
                                                app_handle.restart();
                                            }
                                        }
                                    }
                                    Ok(None) => {
                                        app_handle
                                            .dialog()
                                            .message("You are on the latest version.")
                                            .title("No Update Available")
                                            .kind(MessageDialogKind::Info)
                                            .blocking_show();
                                    }
                                    Err(e) => {
                                        app_handle
                                            .dialog()
                                            .message(format!(
                                                "Failed to check for updates: {}",
                                                e
                                            ))
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
                        #[cfg(target_os = "macos")]
                        hook_macos::cleanup_capslock_remap();
                        app.exit(0);
                    }
                    "toggle" => {
                        let paused = !IS_PAUSED.load(Ordering::SeqCst);
                        IS_PAUSED.store(paused, Ordering::SeqCst);

                        update_tray_visuals(app, paused);

                        let _ = app.emit("status-update", paused);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let tauri::tray::TrayIconEvent::DoubleClick {
                        button: tauri::tray::MouseButton::Left,
                        ..
                    } = event
                    {
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
        .invoke_handler(tauri::generate_handler![
            get_status,
            set_paused,
            add_mapping,
            remove_mapping,
            get_mappings
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let tauri::RunEvent::Reopen { .. } = event {
                if let Some(window) = app_handle.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        });
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    #[test]
    fn test_mapping_serialization() {
        let mut map = HashMap::new();
        map.insert(65, "calc.exe".to_string());

        let json = serde_json::to_string(&map).unwrap();
        assert_eq!(json, "{\"65\":\"calc.exe\"}");

        let decoded: HashMap<u16, String> = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.get(&65).unwrap(), "calc.exe");
    }
}
