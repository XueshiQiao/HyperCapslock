use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::UpdaterExt;

#[cfg(target_os = "macos")]
mod hook_macos;
#[cfg(target_os = "windows")]
mod hook_windows;

// Global state (shared across platforms)
static CAPS_DOWN: AtomicBool = AtomicBool::new(false);
static CAPS_PRESSED_AT_MS: AtomicU64 = AtomicU64::new(0);
static DID_REMAP: AtomicBool = AtomicBool::new(false);
static IS_PAUSED: AtomicBool = AtomicBool::new(false);
static TRAY_TOGGLE_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static TRAY_STATUS_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static SHELL_MAPPINGS: Mutex<Option<HashMap<u16, String>>> = Mutex::new(None);
static INPUT_SOURCE_MAPPINGS: Mutex<Option<HashMap<u16, String>>> = Mutex::new(None);
static ACTION_MAPPINGS: Mutex<Option<Vec<ActionMappingEntry>>> = Mutex::new(None);

const DEFAULT_ABC_KEYCODE: u16 = 188;
const DEFAULT_WECHAT_KEYCODE: u16 = 190;
const DEFAULT_ABC_INPUT_SOURCE_ID: &str = "com.apple.keylayout.ABC";
const DEFAULT_WECHAT_INPUT_SOURCE_ID: &str = "com.tencent.inputmethod.wetype.pinyin";

const JS_H_KEYCODE: u16 = 72;
const JS_J_KEYCODE: u16 = 74;
const JS_K_KEYCODE: u16 = 75;
const JS_L_KEYCODE: u16 = 76;
const JS_P_KEYCODE: u16 = 80;
const JS_Y_KEYCODE: u16 = 89;
const JS_A_KEYCODE: u16 = 65;
const JS_E_KEYCODE: u16 = 69;
const JS_U_KEYCODE: u16 = 85;
const JS_D_KEYCODE: u16 = 68;
const JS_I_KEYCODE: u16 = 73;
const JS_N_KEYCODE: u16 = 78;
const JS_O_KEYCODE: u16 = 79;

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum DirectionalActionKind {
    Left,
    Right,
    Up,
    Down,
    WordForward,
    WordBack,
    Home,
    End,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum JumpDirection {
    Up,
    Down,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum IndependentActionKind {
    Backspace,
    NextLine,
    InsertQuotes,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum ActionConfig {
    Directional { action: DirectionalActionKind },
    Jump { direction: JumpDirection, count: u8 },
    Independent { action: IndependentActionKind },
    InputSource { input_source_id: String },
    Command { command: String },
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
pub(crate) struct ActionMappingEntry {
    pub(crate) key: u16,
    pub(crate) with_shift: bool,
    pub(crate) action: ActionConfig,
}

#[derive(serde::Serialize)]
struct PermissionStatuses {
    platform: &'static str,
    accessibility: &'static str,
    input_monitoring: &'static str,
}

#[cfg(target_os = "macos")]
fn macos_accessibility_granted() -> bool {
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
    }
    unsafe { AXIsProcessTrusted() }
}

#[cfg(target_os = "macos")]
fn macos_input_monitoring_granted() -> bool {
    extern "C" {
        fn CGPreflightListenEventAccess() -> bool;
    }
    unsafe { CGPreflightListenEventAccess() }
}

#[tauri::command]
fn get_permission_statuses() -> PermissionStatuses {
    #[cfg(target_os = "macos")]
    {
        return PermissionStatuses {
            platform: "macos",
            accessibility: if macos_accessibility_granted() {
                "granted"
            } else {
                "not_granted"
            },
            input_monitoring: if macos_input_monitoring_granted() {
                "granted"
            } else {
                "not_granted"
            },
        };
    }

    #[cfg(not(target_os = "macos"))]
    {
        PermissionStatuses {
            platform: "other",
            accessibility: "not_required",
            input_monitoring: "not_required",
        }
    }
}

fn get_shell_mappings_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("shell_mappings.json"))
}

fn get_input_source_mappings_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("input_source_mappings.json"))
}

fn get_action_mappings_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("action_mappings.yml"))
}

fn get_action_mappings_legacy_json_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("action_mappings.json"))
}

fn default_action_mappings() -> Vec<ActionMappingEntry> {
    let mut defaults = vec![
        ActionMappingEntry {
            key: JS_H_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Left,
            },
        },
        ActionMappingEntry {
            key: JS_J_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Down,
            },
        },
        ActionMappingEntry {
            key: JS_K_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Up,
            },
        },
        ActionMappingEntry {
            key: JS_L_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Right,
            },
        },
        ActionMappingEntry {
            key: JS_P_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::WordForward,
            },
        },
        ActionMappingEntry {
            key: JS_Y_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::WordBack,
            },
        },
        ActionMappingEntry {
            key: JS_A_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Home,
            },
        },
        ActionMappingEntry {
            key: JS_E_KEYCODE,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::End,
            },
        },
        ActionMappingEntry {
            key: JS_U_KEYCODE,
            with_shift: false,
            action: ActionConfig::Jump {
                direction: JumpDirection::Up,
                count: 10,
            },
        },
        ActionMappingEntry {
            key: JS_D_KEYCODE,
            with_shift: false,
            action: ActionConfig::Jump {
                direction: JumpDirection::Down,
                count: 10,
            },
        },
        ActionMappingEntry {
            key: JS_I_KEYCODE,
            with_shift: false,
            action: ActionConfig::Independent {
                action: IndependentActionKind::Backspace,
            },
        },
        ActionMappingEntry {
            key: JS_N_KEYCODE,
            with_shift: false,
            action: ActionConfig::Independent {
                action: IndependentActionKind::InsertQuotes,
            },
        },
        ActionMappingEntry {
            key: JS_O_KEYCODE,
            with_shift: false,
            action: ActionConfig::Independent {
                action: IndependentActionKind::NextLine,
            },
        },
    ];

    #[cfg(target_os = "macos")]
    {
        defaults.push(ActionMappingEntry {
            key: DEFAULT_ABC_KEYCODE,
            with_shift: false,
            action: ActionConfig::InputSource {
                input_source_id: DEFAULT_ABC_INPUT_SOURCE_ID.to_string(),
            },
        });
        defaults.push(ActionMappingEntry {
            key: DEFAULT_WECHAT_KEYCODE,
            with_shift: false,
            action: ActionConfig::InputSource {
                input_source_id: DEFAULT_WECHAT_INPUT_SOURCE_ID.to_string(),
            },
        });
    }

    defaults
}

fn read_legacy_mappings(path: Option<PathBuf>) -> HashMap<u16, String> {
    if let Some(path) = path {
        if let Ok(content) = fs::read_to_string(path) {
            return serde_json::from_str::<HashMap<u16, String>>(&content).unwrap_or_default();
        }
    }
    HashMap::new()
}

fn js_keycode_name(key: u16) -> String {
    match key {
        48..=57 => ((b'0' + (key as u8 - 48)) as char).to_string(),
        65..=90 => ((b'A' + (key as u8 - 65)) as char).to_string(),
        8 => "Del".to_string(),
        13 => "Enter".to_string(),
        37 => "Left".to_string(),
        38 => "Up".to_string(),
        39 => "Right".to_string(),
        40 => "Down".to_string(),
        186 => ";".to_string(),
        187 => "=".to_string(),
        188 => ",".to_string(),
        189 => "-".to_string(),
        190 => ".".to_string(),
        191 => "/".to_string(),
        220 => "\\".to_string(),
        222 => "'".to_string(),
        _ => format!("Key{}", key),
    }
}

fn yaml_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

fn directional_action_name(action: &DirectionalActionKind) -> &'static str {
    match action {
        DirectionalActionKind::Left => "left",
        DirectionalActionKind::Right => "right",
        DirectionalActionKind::Up => "up",
        DirectionalActionKind::Down => "down",
        DirectionalActionKind::WordForward => "word_forward",
        DirectionalActionKind::WordBack => "word_back",
        DirectionalActionKind::Home => "home",
        DirectionalActionKind::End => "end",
    }
}

fn jump_direction_name(direction: &JumpDirection) -> &'static str {
    match direction {
        JumpDirection::Up => "up",
        JumpDirection::Down => "down",
    }
}

fn independent_action_name(action: &IndependentActionKind) -> &'static str {
    match action {
        IndependentActionKind::Backspace => "backspace",
        IndependentActionKind::NextLine => "next_line",
        IndependentActionKind::InsertQuotes => "insert_quotes",
    }
}

fn render_action_mappings_yaml_with_comments(mappings: &[ActionMappingEntry]) -> String {
    let mut lines = vec![
        "# HyperCapslock action mappings".to_string(),
        "# key uses JavaScript keyCode".to_string(),
        "# with_shift=false -> Caps+Key, with_shift=true -> Caps+Shift+Key".to_string(),
    ];

    for entry in mappings {
        lines.push(format!(
            "- key: {} # {}",
            entry.key,
            js_keycode_name(entry.key)
        ));
        lines.push(format!("  with_shift: {}", entry.with_shift));
        lines.push("  action:".to_string());
        match &entry.action {
            ActionConfig::Directional { action } => {
                lines.push("    kind: directional".to_string());
                lines.push(format!("    action: {}", directional_action_name(action)));
            }
            ActionConfig::Jump { direction, count } => {
                lines.push("    kind: jump".to_string());
                lines.push(format!("    direction: {}", jump_direction_name(direction)));
                lines.push(format!("    count: {}", count));
            }
            ActionConfig::Independent { action } => {
                lines.push("    kind: independent".to_string());
                lines.push(format!("    action: {}", independent_action_name(action)));
            }
            ActionConfig::InputSource { input_source_id } => {
                lines.push("    kind: input_source".to_string());
                lines.push(format!(
                    "    input_source_id: {}",
                    yaml_quote(input_source_id)
                ));
            }
            ActionConfig::Command { command } => {
                lines.push("    kind: command".to_string());
                lines.push(format!("    command: {}", yaml_quote(command)));
            }
        }
    }

    lines.join("\n") + "\n"
}

fn upsert_action_mapping_in_vec(
    mappings: &mut Vec<ActionMappingEntry>,
    entry: ActionMappingEntry,
) -> bool {
    if let Some(existing) = mappings
        .iter_mut()
        .find(|m| m.key == entry.key && m.with_shift == entry.with_shift)
    {
        if *existing != entry {
            *existing = entry;
            return true;
        }
        return false;
    }
    mappings.push(entry);
    true
}

fn remove_action_mapping_from_vec(
    mappings: &mut Vec<ActionMappingEntry>,
    key: u16,
    with_shift: bool,
) -> bool {
    let before = mappings.len();
    mappings.retain(|m| !(m.key == key && m.with_shift == with_shift));
    before != mappings.len()
}

fn normalize_action_mappings(mappings: &mut Vec<ActionMappingEntry>) {
    let mut deduped: Vec<ActionMappingEntry> = Vec::new();
    for entry in mappings.drain(..) {
        if let Some(existing) = deduped
            .iter_mut()
            .find(|m| m.key == entry.key && m.with_shift == entry.with_shift)
        {
            *existing = entry;
        } else {
            deduped.push(entry);
        }
    }
    *mappings = deduped;
}

fn sync_legacy_mappings_cache_from_actions(mappings: &[ActionMappingEntry]) {
    let mut shell = HashMap::new();
    let mut input_sources = HashMap::new();

    for entry in mappings {
        match &entry.action {
            ActionConfig::Command { command } if entry.with_shift => {
                shell.insert(entry.key, command.clone());
            }
            ActionConfig::InputSource { input_source_id } if !entry.with_shift => {
                input_sources.insert(entry.key, input_source_id.clone());
            }
            _ => {}
        }
    }

    *SHELL_MAPPINGS.lock().unwrap() = Some(shell);
    *INPUT_SOURCE_MAPPINGS.lock().unwrap() = Some(input_sources);
}

fn save_action_mappings_to_disk(app: &AppHandle) {
    if let Some(path) = get_action_mappings_path(app) {
        if let Some(mappings) = &*ACTION_MAPPINGS.lock().unwrap() {
            let content = render_action_mappings_yaml_with_comments(mappings);
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = fs::write(path, content);
        }
    }
}

fn load_action_mappings_from_disk(app: &AppHandle) {
    let mut loaded_from_disk = false;
    let mut mappings = Vec::new();
    let mut changed = false;

    if let Some(path) = get_action_mappings_path(app) {
        if let Ok(content) = fs::read_to_string(path) {
            loaded_from_disk = true;
            mappings =
                serde_yaml::from_str::<Vec<ActionMappingEntry>>(&content).unwrap_or_default();
        }
    }

    if !loaded_from_disk {
        if let Some(path) = get_action_mappings_legacy_json_path(app) {
            if let Ok(content) = fs::read_to_string(path) {
                loaded_from_disk = true;
                mappings =
                    serde_json::from_str::<Vec<ActionMappingEntry>>(&content).unwrap_or_default();
                changed = true;
            }
        }
    }

    if !loaded_from_disk || mappings.is_empty() {
        mappings = default_action_mappings();
        changed = true;
    }

    let legacy_shell = read_legacy_mappings(get_shell_mappings_path(app));
    for (key, command) in legacy_shell {
        changed |= upsert_action_mapping_in_vec(
            &mut mappings,
            ActionMappingEntry {
                key,
                with_shift: true,
                action: ActionConfig::Command { command },
            },
        );
    }

    #[cfg(target_os = "macos")]
    {
        let legacy_input = read_legacy_mappings(get_input_source_mappings_path(app));
        for (key, input_source_id) in legacy_input {
            changed |= upsert_action_mapping_in_vec(
                &mut mappings,
                ActionMappingEntry {
                    key,
                    with_shift: false,
                    action: ActionConfig::InputSource { input_source_id },
                },
            );
        }
    }

    normalize_action_mappings(&mut mappings);
    sync_legacy_mappings_cache_from_actions(&mappings);
    *ACTION_MAPPINGS.lock().unwrap() = Some(mappings);

    if changed {
        save_action_mappings_to_disk(app);
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
fn upsert_action_mapping(
    app: AppHandle,
    key: u16,
    with_shift: bool,
    action: ActionConfig,
) -> Result<(), String> {
    match &action {
        ActionConfig::Command { command } if command.trim().is_empty() => {
            return Err("command cannot be empty".to_string());
        }
        ActionConfig::InputSource { input_source_id } if input_source_id.trim().is_empty() => {
            return Err("input_source_id cannot be empty".to_string());
        }
        ActionConfig::Jump { count, .. } if *count == 0 => {
            return Err("jump count must be >= 1".to_string());
        }
        _ => {}
    }

    {
        let mut guard = ACTION_MAPPINGS.lock().unwrap();
        let mappings = guard.get_or_insert_with(Vec::new);
        let entry = ActionMappingEntry {
            key,
            with_shift,
            action,
        };
        upsert_action_mapping_in_vec(mappings, entry);
        normalize_action_mappings(mappings);
        sync_legacy_mappings_cache_from_actions(mappings);
    }
    save_action_mappings_to_disk(&app);
    Ok(())
}

#[tauri::command]
fn remove_action_mapping(app: AppHandle, key: u16, with_shift: bool) {
    {
        let mut guard = ACTION_MAPPINGS.lock().unwrap();
        if let Some(mappings) = guard.as_mut() {
            remove_action_mapping_from_vec(mappings, key, with_shift);
            sync_legacy_mappings_cache_from_actions(mappings);
        }
    }
    save_action_mappings_to_disk(&app);
}

#[tauri::command]
fn get_action_mappings() -> Vec<ActionMappingEntry> {
    ACTION_MAPPINGS.lock().unwrap().clone().unwrap_or_default()
}

// Legacy API wrappers kept for compatibility.
#[tauri::command]
fn add_mapping(app: AppHandle, key: u16, command: String) -> Result<(), String> {
    upsert_action_mapping(app, key, true, ActionConfig::Command { command })
}

#[tauri::command]
fn remove_mapping(app: AppHandle, key: u16) {
    remove_action_mapping(app, key, true);
}

#[tauri::command]
fn get_mappings() -> HashMap<u16, String> {
    let mut out = HashMap::new();
    for entry in get_action_mappings() {
        if let ActionConfig::Command { command } = entry.action {
            if entry.with_shift {
                out.insert(entry.key, command);
            }
        }
    }
    out
}

#[tauri::command]
fn add_input_source_mapping(
    app: AppHandle,
    key: u16,
    input_source_id: String,
) -> Result<(), String> {
    upsert_action_mapping(
        app,
        key,
        false,
        ActionConfig::InputSource { input_source_id },
    )
}

#[tauri::command]
fn remove_input_source_mapping(app: AppHandle, key: u16) {
    let should_remove = ACTION_MAPPINGS
        .lock()
        .unwrap()
        .as_ref()
        .map(|mappings| {
            mappings.iter().any(|m| {
                m.key == key
                    && !m.with_shift
                    && matches!(m.action, ActionConfig::InputSource { .. })
            })
        })
        .unwrap_or(false);

    if should_remove {
        remove_action_mapping(app, key, false);
    }
}

#[tauri::command]
fn get_input_source_mappings() -> HashMap<u16, String> {
    let mut out = HashMap::new();
    for entry in get_action_mappings() {
        if let ActionConfig::InputSource { input_source_id } = entry.action {
            if !entry.with_shift {
                out.insert(entry.key, input_source_id);
            }
        }
    }
    out
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

#[cfg(target_os = "macos")]
fn handle_reopen_event(app_handle: &AppHandle, event: &tauri::RunEvent) {
    if let tauri::RunEvent::Reopen { .. } = event {
        if let Some(window) = app_handle.get_webview_window("main") {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

#[cfg(not(target_os = "macos"))]
fn handle_reopen_event(_: &AppHandle, _: &tauri::RunEvent) {}

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
            load_action_mappings_from_disk(app.handle());
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
            get_permission_statuses,
            upsert_action_mapping,
            remove_action_mapping,
            get_action_mappings,
            add_mapping,
            remove_mapping,
            get_mappings,
            add_input_source_mapping,
            remove_input_source_mapping,
            get_input_source_mappings
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            handle_reopen_event(&app_handle, &event);
        });
}

#[cfg(test)]
mod tests {
    use crate::{
        default_action_mappings, render_action_mappings_yaml_with_comments,
        upsert_action_mapping_in_vec, ActionConfig, ActionMappingEntry, DirectionalActionKind,
        IndependentActionKind, JumpDirection, JS_H_KEYCODE, JS_N_KEYCODE, JS_U_KEYCODE,
    };

    #[test]
    fn test_action_mapping_serialization() {
        let entry = ActionMappingEntry {
            key: 77,
            with_shift: true,
            action: ActionConfig::Command {
                command: "open -a Calculator".to_string(),
            },
        };

        let yaml = serde_yaml::to_string(&entry).unwrap();
        let decoded: ActionMappingEntry = serde_yaml::from_str(&yaml).unwrap();
        assert_eq!(decoded, entry);
    }

    #[test]
    fn test_yaml_render_contains_key_name_comment() {
        let entries = vec![ActionMappingEntry {
            key: 87,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::WordForward,
            },
        }];

        let yaml = render_action_mappings_yaml_with_comments(&entries);
        assert!(yaml.contains("key: 87 # W"));

        let decoded: Vec<ActionMappingEntry> = serde_yaml::from_str(&yaml).unwrap();
        assert_eq!(decoded, entries);
    }

    #[test]
    fn test_default_action_mappings_include_core_behaviors() {
        let defaults = default_action_mappings();
        assert!(defaults.iter().any(|m| {
            m.key == JS_H_KEYCODE
                && !m.with_shift
                && matches!(
                    m.action,
                    ActionConfig::Directional {
                        action: DirectionalActionKind::Left
                    }
                )
        }));
        assert!(defaults.iter().any(|m| {
            m.key == JS_U_KEYCODE
                && matches!(
                    m.action,
                    ActionConfig::Jump {
                        direction: JumpDirection::Up,
                        count: 10
                    }
                )
        }));
        assert!(defaults.iter().any(|m| {
            m.key == JS_N_KEYCODE
                && matches!(
                    m.action,
                    ActionConfig::Independent {
                        action: IndependentActionKind::InsertQuotes
                    }
                )
        }));
    }

    #[test]
    fn test_upsert_replaces_existing_binding() {
        let mut mappings = vec![ActionMappingEntry {
            key: 65,
            with_shift: false,
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Left,
            },
        }];

        let changed = upsert_action_mapping_in_vec(
            &mut mappings,
            ActionMappingEntry {
                key: 65,
                with_shift: false,
                action: ActionConfig::Directional {
                    action: DirectionalActionKind::Right,
                },
            },
        );

        assert!(changed);
        assert_eq!(mappings.len(), 1);
        assert!(matches!(
            mappings[0].action,
            ActionConfig::Directional {
                action: DirectionalActionKind::Right
            }
        ));
    }
}
