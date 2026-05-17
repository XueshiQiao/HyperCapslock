use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, WebviewUrl, WebviewWindowBuilder, Wry};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_opener::OpenerExt;
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
static TRAY_CHECK_UPDATE_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static TRAY_SHOW_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static TRAY_QUIT_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static TRAY_MORE_APPS_ITEM: Mutex<Option<MenuItem<Wry>>> = Mutex::new(None);
static ACTION_MAPPINGS: Mutex<Option<Vec<ActionMappingEntry>>> = Mutex::new(None);
static MENU_LOCALE: Mutex<&'static str> = Mutex::new("en");
static APP_CONFIG: Mutex<AppConfig> = Mutex::new(AppConfig {
    hide_dock_icon: false,
    show_hud: false,
    hud_duration_ms: 1350,
});
// Set once in setup(); lets the keyboard hook emit HUD events to the frontend.
static APP_HANDLE: Mutex<Option<AppHandle>> = Mutex::new(None);
// Throttle token for HUD emits (held nav keys autorepeat fast).
static LAST_HUD_EMIT_MS: AtomicU64 = AtomicU64::new(0);
static LAST_HUD_KEY: Mutex<String> = Mutex::new(String::new());
const HUD_THROTTLE_MS: u64 = 120;

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
    Directional {
        action: DirectionalActionKind,
    },
    Jump {
        direction: JumpDirection,
        count: u8,
    },
    Independent {
        action: IndependentActionKind,
    },
    InputSource {
        input_source_id: String,
    },
    Command {
        command: String,
    },
    KeyCombo {
        target_key: u16,
        #[serde(default)]
        with_ctrl: bool,
        #[serde(default)]
        with_alt: bool,
        #[serde(default)]
        with_cmd: bool,
        #[serde(default)]
        with_target_shift: bool,
    },
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ModifierKey {
    LeftShift,
    RightShift,
    LeftControl,
    RightControl,
    LeftOption,
    RightOption,
    LeftCommand,
    RightCommand,
    Fn,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum Trigger {
    HyperPlusKey {
        key: u16,
        #[serde(default)]
        with_shift: bool,
    },
    DoubleTapHyper,
    DoubleTapModifier {
        modifier: ModifierKey,
    },
}

#[derive(serde::Serialize, Clone, Debug, PartialEq, Eq)]
pub(crate) struct ActionMappingEntry {
    pub(crate) trigger: Trigger,
    pub(crate) action: ActionConfig,
}

// Custom deserializer to support legacy YAML (top-level `key` / `with_shift`).
// Old entries: `{ key: 72, with_shift: false, action: ... }`
// New entries: `{ trigger: { kind: hyper_plus_key, key: 72, with_shift: false }, action: ... }`
impl<'de> serde::Deserialize<'de> for ActionMappingEntry {
    fn deserialize<D: serde::Deserializer<'de>>(de: D) -> Result<Self, D::Error> {
        #[derive(serde::Deserialize)]
        struct Raw {
            #[serde(default)]
            trigger: Option<Trigger>,
            #[serde(default)]
            key: Option<u16>,
            #[serde(default)]
            with_shift: Option<bool>,
            action: ActionConfig,
        }
        let raw = Raw::deserialize(de)?;
        let trigger = if let Some(t) = raw.trigger {
            t
        } else if let Some(key) = raw.key {
            Trigger::HyperPlusKey {
                key,
                with_shift: raw.with_shift.unwrap_or(false),
            }
        } else {
            return Err(serde::de::Error::custom(
                "action mapping entry missing both 'trigger' and legacy 'key' fields",
            ));
        };
        Ok(ActionMappingEntry {
            trigger,
            action: raw.action,
        })
    }
}

impl Trigger {
    pub(crate) fn hyper_plus_key(&self) -> Option<(u16, bool)> {
        match self {
            Trigger::HyperPlusKey { key, with_shift } => Some((*key, *with_shift)),
            _ => None,
        }
    }
}

fn default_hud_duration_ms() -> u32 {
    1350
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct AppConfig {
    #[serde(default)]
    pub(crate) hide_dock_icon: bool,
    #[serde(default)]
    pub(crate) show_hud: bool,
    #[serde(default = "default_hud_duration_ms")]
    pub(crate) hud_duration_ms: u32,
}

#[derive(serde::Serialize)]
struct PermissionStatuses {
    platform: &'static str,
    accessibility: &'static str,
    input_monitoring: &'static str,
}

#[tauri::command]
fn open_privacy_settings(app: AppHandle, pane: String) -> Result<(), String> {
    let url = match pane.as_str() {
        "accessibility" => {
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        "input_monitoring" => {
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        other => return Err(format!("unknown settings pane: {}", other)),
    };
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|e| format!("failed to open settings pane: {}", e))
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

fn get_action_mappings_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("action_mappings.yml"))
}

fn default_action_mappings() -> Vec<ActionMappingEntry> {
    let mut defaults = vec![
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_H_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Left,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_J_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Down,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_K_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Up,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_L_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Right,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_P_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::WordForward,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_Y_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::WordBack,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_A_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Home,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_E_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::End,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_U_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Jump {
                direction: JumpDirection::Up,
                count: 10,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_D_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Jump {
                direction: JumpDirection::Down,
                count: 10,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_I_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Independent {
                action: IndependentActionKind::Backspace,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_N_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Independent {
                action: IndependentActionKind::InsertQuotes,
            },
        },
        ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: JS_O_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::Independent {
                action: IndependentActionKind::NextLine,
            },
        },
    ];

    #[cfg(target_os = "macos")]
    {
        defaults.push(ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: DEFAULT_ABC_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::InputSource {
                input_source_id: DEFAULT_ABC_INPUT_SOURCE_ID.to_string(),
            },
        });
        defaults.push(ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: DEFAULT_WECHAT_KEYCODE,
                with_shift: false,
            },
            action: ActionConfig::InputSource {
                input_source_id: DEFAULT_WECHAT_INPUT_SOURCE_ID.to_string(),
            },
        });
    }

    defaults
}

pub(crate) fn js_keycode_name(key: u16) -> String {
    match key {
        48..=57 => ((b'0' + (key as u8 - 48)) as char).to_string(),
        65..=90 => ((b'A' + (key as u8 - 65)) as char).to_string(),
        112..=123 => format!("F{}", key - 111),
        8 => "Backspace".to_string(),
        9 => "Tab".to_string(),
        13 => "Enter".to_string(),
        27 => "Esc".to_string(),
        32 => "Space".to_string(),
        46 => "Fwd Del".to_string(),
        33 => "PgUp".to_string(),
        34 => "PgDn".to_string(),
        35 => "End".to_string(),
        36 => "Home".to_string(),
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
        192 => "`".to_string(),
        219 => "[".to_string(),
        220 => "\\".to_string(),
        221 => "]".to_string(),
        222 => "'".to_string(),
        _ => format!("Key{}", key),
    }
}

fn yaml_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

pub(crate) fn directional_action_name(action: &DirectionalActionKind) -> &'static str {
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

pub(crate) fn jump_direction_name(direction: &JumpDirection) -> &'static str {
    match direction {
        JumpDirection::Up => "up",
        JumpDirection::Down => "down",
    }
}

pub(crate) fn independent_action_name(action: &IndependentActionKind) -> &'static str {
    match action {
        IndependentActionKind::Backspace => "backspace",
        IndependentActionKind::NextLine => "next_line",
        IndependentActionKind::InsertQuotes => "insert_quotes",
    }
}

fn modifier_key_name(modifier: ModifierKey) -> &'static str {
    match modifier {
        ModifierKey::LeftShift => "left_shift",
        ModifierKey::RightShift => "right_shift",
        ModifierKey::LeftControl => "left_control",
        ModifierKey::RightControl => "right_control",
        ModifierKey::LeftOption => "left_option",
        ModifierKey::RightOption => "right_option",
        ModifierKey::LeftCommand => "left_command",
        ModifierKey::RightCommand => "right_command",
        ModifierKey::Fn => "fn",
    }
}

fn render_action_mappings_yaml_with_comments(mappings: &[ActionMappingEntry]) -> String {
    let mut lines = vec![
        "# HyperCapslock action mappings".to_string(),
        "# trigger.kind: hyper_plus_key (Caps+Key), double_tap_hyper (Caps tapped twice),"
            .to_string(),
        "#   or double_tap_modifier (a modifier key tapped twice)".to_string(),
        "# key uses JavaScript keyCode".to_string(),
    ];

    for entry in mappings {
        match &entry.trigger {
            Trigger::HyperPlusKey { key, with_shift } => {
                lines.push("- trigger:".to_string());
                lines.push("    kind: hyper_plus_key".to_string());
                lines.push(format!("    key: {} # {}", key, js_keycode_name(*key)));
                lines.push(format!("    with_shift: {}", with_shift));
            }
            Trigger::DoubleTapHyper => {
                lines.push("- trigger:".to_string());
                lines.push("    kind: double_tap_hyper".to_string());
            }
            Trigger::DoubleTapModifier { modifier } => {
                lines.push("- trigger:".to_string());
                lines.push("    kind: double_tap_modifier".to_string());
                lines.push(format!("    modifier: {}", modifier_key_name(*modifier)));
            }
        }
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
            ActionConfig::KeyCombo {
                target_key,
                with_ctrl,
                with_alt,
                with_cmd,
                with_target_shift,
            } => {
                lines.push("    kind: key_combo".to_string());
                lines.push(format!(
                    "    target_key: {} # {}",
                    target_key,
                    js_keycode_name(*target_key)
                ));
                if *with_ctrl {
                    lines.push("    with_ctrl: true".to_string());
                }
                if *with_alt {
                    lines.push("    with_alt: true".to_string());
                }
                if *with_cmd {
                    lines.push("    with_cmd: true".to_string());
                }
                if *with_target_shift {
                    lines.push("    with_target_shift: true".to_string());
                }
            }
        }
    }

    lines.join("\n") + "\n"
}

fn upsert_action_mapping_in_vec(
    mappings: &mut Vec<ActionMappingEntry>,
    entry: ActionMappingEntry,
) -> bool {
    if let Some(existing) = mappings.iter_mut().find(|m| m.trigger == entry.trigger) {
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
    trigger: &Trigger,
) -> bool {
    let before = mappings.len();
    mappings.retain(|m| m.trigger != *trigger);
    before != mappings.len()
}

fn normalize_action_mappings(mappings: &mut Vec<ActionMappingEntry>) {
    let mut deduped: Vec<ActionMappingEntry> = Vec::new();
    for entry in mappings.drain(..) {
        if let Some(existing) = deduped.iter_mut().find(|m| m.trigger == entry.trigger) {
            *existing = entry;
        } else {
            deduped.push(entry);
        }
    }
    *mappings = deduped;
}

fn get_app_config_path(app: &AppHandle) -> Option<PathBuf> {
    app.path()
        .app_data_dir()
        .ok()
        .map(|p| p.join("app_config.yml"))
}

fn load_app_config_from_disk(app: &AppHandle) {
    if let Some(path) = get_app_config_path(app) {
        if let Ok(content) = fs::read_to_string(&path) {
            match serde_yaml::from_str::<AppConfig>(&content) {
                Ok(cfg) => {
                    *APP_CONFIG.lock().unwrap() = cfg;
                }
                Err(e) => {
                    eprintln!("[HYPERCAPS] app_config.yml parse error: {}", e);
                }
            }
        }
    }
}

fn persist_app_config(app: &AppHandle, cfg: AppConfig) -> Result<(), String> {
    let path = get_app_config_path(app)
        .ok_or_else(|| "Could not determine application data directory".to_string())?;
    let content = serde_yaml::to_string(&cfg)
        .map_err(|e| format!("Failed to serialize app config: {}", e))?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create config directory: {}", e))?;
    }
    fs::write(path, content).map_err(|e| format!("Failed to write app config: {}", e))
}

#[cfg(target_os = "macos")]
fn apply_activation_policy(app: &AppHandle, hide: bool) {
    let policy = if hide {
        tauri::ActivationPolicy::Accessory
    } else {
        tauri::ActivationPolicy::Regular
    };
    if let Err(e) = app.set_activation_policy(policy) {
        eprintln!("[HYPERCAPS] set_activation_policy failed: {}", e);
    }
}

#[cfg(not(target_os = "macos"))]
fn apply_activation_policy(_: &AppHandle, _: bool) {}

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
    let mut mappings = Vec::new();
    let mut changed = false;

    if let Some(path) = get_action_mappings_path(app) {
        eprintln!("[HYPERCAPS] Loading action mappings from: {:?}", path);
        if let Ok(content) = fs::read_to_string(&path) {
            match serde_yaml::from_str::<Vec<ActionMappingEntry>>(&content) {
                Ok(m) => {
                    eprintln!("[HYPERCAPS] Loaded {} mappings from YAML", m.len());
                    mappings = m;
                }
                Err(e) => {
                    eprintln!("[HYPERCAPS] YAML parse error: {}", e);
                }
            }
        } else {
            eprintln!("[HYPERCAPS] File not found: {:?}", path);
        }
    }

    if mappings.is_empty() {
        eprintln!("[HYPERCAPS] Using default mappings");
        mappings = default_action_mappings();
        changed = true;
    }

    normalize_action_mappings(&mut mappings);
    eprintln!(
        "[HYPERCAPS] Final mappings count: {}, changed: {}",
        mappings.len(),
        changed
    );

    *ACTION_MAPPINGS.lock().unwrap() = Some(mappings);

    if changed {
        eprintln!("[HYPERCAPS] Saving default mappings to disk");
        save_action_mappings_to_disk(app);
    }
}

#[cfg(not(target_os = "macos"))]
static ICON_RUNNING: &[u8] = include_bytes!("../icons/icon.png");
#[cfg(not(target_os = "macos"))]
static ICON_DISABLED: &[u8] = include_bytes!("../icons/icon_disabled.png");
#[cfg(target_os = "macos")]
static ICON_TRAY_TEMPLATE_RUNNING: &[u8] = include_bytes!("../icons/capslock.fill.png");
#[cfg(target_os = "macos")]
static ICON_TRAY_TEMPLATE_PAUSED: &[u8] = include_bytes!("../icons/capslock.png");

fn detect_system_locale() -> &'static str {
    if let Some(locale) = sys_locale::get_locale() {
        let code = locale.to_lowercase();
        if code.starts_with("zh") {
            return "zh";
        }
        if code.starts_with("ja") {
            return "ja";
        }
        if code.starts_with("de") {
            return "de";
        }
    }
    "en"
}

fn menu_text(key: &'static str) -> &'static str {
    let locale = *MENU_LOCALE.lock().unwrap();
    match (locale, key) {
        ("zh", "status_running") => "\u{72B6}\u{6001}: \u{8FD0}\u{884C}\u{4E2D}",
        ("zh", "status_paused") => "\u{72B6}\u{6001}: \u{5DF2}\u{6682}\u{505C}",
        ("zh", "start") => "\u{542F}\u{52A8}\u{670D}\u{52A1}",
        ("zh", "stop") => "\u{505C}\u{6B62}\u{670D}\u{52A1}",
        ("zh", "check_update") => "\u{68C0}\u{67E5}\u{66F4}\u{65B0}",
        ("zh", "open") => "\u{6253}\u{5F00}\u{7A97}\u{53E3}",
        ("zh", "quit") => "\u{9000}\u{51FA} HyperCapslock",
        ("zh", "more_apps") => "\u{4F5C}\u{8005}\u{7684}\u{66F4}\u{591A}\u{5E94}\u{7528}\u{2026}",

        ("ja", "status_running") => {
            "\u{30B9}\u{30C6}\u{30FC}\u{30BF}\u{30B9}: \u{5B9F}\u{884C}\u{4E2D}"
        }
        ("ja", "status_paused") => {
            "\u{30B9}\u{30C6}\u{30FC}\u{30BF}\u{30B9}: \u{4E00}\u{6642}\u{505C}\u{6B62}"
        }
        ("ja", "start") => "\u{30B5}\u{30FC}\u{30D3}\u{30B9}\u{3092}\u{958B}\u{59CB}",
        ("ja", "stop") => "\u{30B5}\u{30FC}\u{30D3}\u{30B9}\u{3092}\u{505C}\u{6B62}",
        ("ja", "check_update") => {
            "\u{30A2}\u{30C3}\u{30D7}\u{30C7}\u{30FC}\u{30C8}\u{3092}\u{78BA}\u{8A8D}"
        }
        ("ja", "open") => "\u{30A6}\u{30A3}\u{30F3}\u{30C9}\u{30A6}\u{3092}\u{958B}\u{304F}",
        ("ja", "quit") => "HyperCapslock \u{3092}\u{7D42}\u{4E86}",
        ("ja", "more_apps") => {
            "\u{4F5C}\u{8005}\u{306E}\u{4ED6}\u{306E}\u{30A2}\u{30D7}\u{30EA}\u{2026}"
        }

        ("de", "status_running") => "Status: L\u{00E4}uft",
        ("de", "status_paused") => "Status: Pausiert",
        ("de", "start") => "Dienst starten",
        ("de", "stop") => "Dienst stoppen",
        ("de", "check_update") => "Nach Updates suchen",
        ("de", "open") => "Fenster \u{00F6}ffnen",
        ("de", "quit") => "HyperCapslock beenden",
        ("de", "more_apps") => "Weitere Apps des Autors\u{2026}",

        (_, "status_running") => "Status: Running",
        (_, "status_paused") => "Status: Paused",
        (_, "start") => "Start Service",
        (_, "stop") => "Stop Service",
        (_, "check_update") => "Check for Updates",
        (_, "open") => "Open Window",
        (_, "quit") => "Quit HyperCapslock",
        (_, "more_apps") => "More Apps by Author\u{2026}",
        _ => key,
    }
}

fn refresh_tray_texts(paused: bool) {
    if let Ok(guard) = TRAY_TOGGLE_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(if paused {
                menu_text("start")
            } else {
                menu_text("stop")
            });
        }
    }
    if let Ok(guard) = TRAY_STATUS_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(if paused {
                menu_text("status_paused")
            } else {
                menu_text("status_running")
            });
        }
    }
    if let Ok(guard) = TRAY_CHECK_UPDATE_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(menu_text("check_update"));
        }
    }
    if let Ok(guard) = TRAY_SHOW_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(menu_text("open"));
        }
    }
    if let Ok(guard) = TRAY_QUIT_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(menu_text("quit"));
        }
    }
    if let Ok(guard) = TRAY_MORE_APPS_ITEM.lock() {
        if let Some(item) = &*guard {
            let _ = item.set_text(menu_text("more_apps"));
        }
    }
}

fn update_tray_visuals(app: &AppHandle, paused: bool) {
    refresh_tray_texts(paused);

    #[cfg(target_os = "macos")]
    // macOS menu bar uses template icons (alpha mask) for proper monochrome rendering.
    let icon_bytes = if paused {
        ICON_TRAY_TEMPLATE_PAUSED
    } else {
        ICON_TRAY_TEMPLATE_RUNNING
    };
    #[cfg(not(target_os = "macos"))]
    let icon_bytes = if paused { ICON_DISABLED } else { ICON_RUNNING };
    if let Ok(image) = Image::from_bytes(icon_bytes) {
        if let Some(tray) = app.tray_by_id("tray") {
            let _ = tray.set_icon(Some(image));
            #[cfg(target_os = "macos")]
            let _ = tray.set_icon_as_template(true);
        }
    }
}

#[tauri::command]
fn upsert_action_mapping(
    app: AppHandle,
    trigger: Trigger,
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
        let entry = ActionMappingEntry { trigger, action };
        upsert_action_mapping_in_vec(mappings, entry);
        normalize_action_mappings(mappings);
    }
    save_action_mappings_to_disk(&app);
    Ok(())
}

#[tauri::command]
fn remove_action_mapping(app: AppHandle, trigger: Trigger) {
    {
        let mut guard = ACTION_MAPPINGS.lock().unwrap();
        if let Some(mappings) = guard.as_mut() {
            remove_action_mapping_from_vec(mappings, &trigger);
        }
    }
    save_action_mappings_to_disk(&app);
}

#[tauri::command]
fn get_action_mappings() -> Vec<ActionMappingEntry> {
    ACTION_MAPPINGS.lock().unwrap().clone().unwrap_or_default()
}

#[derive(Clone, serde::Serialize)]
struct HudPayload {
    trigger: String,
    combo: String,
    caption: String,
    duration: u32,
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Emit a HUD event to the frontend overlay window. No-op unless the user
/// enabled the HUD. Throttled per identical (trigger,combo) so a held nav key
/// autorepeating doesn't flood IPC; a *different* mapping emits immediately.
/// Called from the keyboard-hook thread.
pub(crate) fn emit_hud(trigger: String, combo: String, caption: String) {
    let (enabled, duration) = {
        let c = APP_CONFIG.lock().unwrap();
        (c.show_hud, c.hud_duration_ms)
    };
    if !enabled {
        return;
    }
    let key = format!("{trigger}\u{1}{combo}\u{1}{caption}");
    let now = now_ms();
    {
        let mut last_key = LAST_HUD_KEY.lock().unwrap();
        let same = *last_key == key;
        let last = LAST_HUD_EMIT_MS.load(Ordering::SeqCst);
        if same && now.saturating_sub(last) < HUD_THROTTLE_MS {
            return;
        }
        *last_key = key;
        LAST_HUD_EMIT_MS.store(now, Ordering::SeqCst);
    }
    if let Some(app) = APP_HANDLE.lock().unwrap().as_ref() {
        let _ = app.emit(
            "hud-show",
            HudPayload {
                trigger,
                combo,
                caption,
                duration,
            },
        );
    }
}

#[tauri::command]
fn get_app_config() -> AppConfig {
    *APP_CONFIG.lock().unwrap()
}

#[tauri::command]
fn set_hide_dock_icon(app: AppHandle, hide: bool) -> Result<(), String> {
    // Hold the lock for the whole sequence so concurrent toggles can't leave
    // in-memory state, the persisted file, and the live activation policy
    // disagreeing. If persistence fails we revert the in-memory flip so the
    // next read matches disk.
    let mut cfg = APP_CONFIG.lock().unwrap();
    let previous = cfg.hide_dock_icon;
    cfg.hide_dock_icon = hide;
    if let Err(e) = persist_app_config(&app, *cfg) {
        cfg.hide_dock_icon = previous;
        return Err(e);
    }
    apply_activation_policy(&app, hide);
    drop(cfg);

    // Switching activation policy can drop window focus; reassert visibility
    // so the user does not lose the settings window after toggling.
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
    Ok(())
}

#[tauri::command]
fn set_show_hud(app: AppHandle, show: bool) -> Result<(), String> {
    let mut cfg = APP_CONFIG.lock().unwrap();
    let previous = cfg.show_hud;
    cfg.show_hud = show;
    if let Err(e) = persist_app_config(&app, *cfg) {
        cfg.show_hud = previous;
        return Err(e);
    }
    Ok(())
}

#[tauri::command]
fn set_hud_duration(app: AppHandle, duration_ms: u32) -> Result<(), String> {
    let clamped = duration_ms.clamp(300, 6000);
    let mut cfg = APP_CONFIG.lock().unwrap();
    let previous = cfg.hud_duration_ms;
    cfg.hud_duration_ms = clamped;
    if let Err(e) = persist_app_config(&app, *cfg) {
        cfg.hud_duration_ms = previous;
        return Err(e);
    }
    Ok(())
}

#[derive(serde::Serialize)]
struct ImportResult {
    imported: usize,
}

// Sentinel returned when the caller did not opt in to overwriting and the
// target already exists. The frontend matches on this string and prompts the
// user before retrying with `overwrite: true`.
pub(crate) const EXPORT_FILE_EXISTS_ERR: &str = "FILE_EXISTS";

#[tauri::command]
fn export_action_mappings_to_path(path: String, overwrite: bool) -> Result<(), String> {
    if !overwrite && std::path::Path::new(&path).exists() {
        return Err(EXPORT_FILE_EXISTS_ERR.to_string());
    }
    let mappings = ACTION_MAPPINGS.lock().unwrap().clone().unwrap_or_default();
    let content = render_action_mappings_yaml_with_comments(&mappings);
    if let Some(parent) = std::path::Path::new(&path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("Failed to create directory: {}", e))?;
        }
    }
    fs::write(&path, content).map_err(|e| format!("Failed to write file: {}", e))
}

#[tauri::command]
fn import_action_mappings_from_path(app: AppHandle, path: String) -> Result<ImportResult, String> {
    let content = fs::read_to_string(&path).map_err(|e| format!("Failed to read file: {}", e))?;
    let mut imported: Vec<ActionMappingEntry> =
        serde_yaml::from_str(&content).map_err(|e| format!("Invalid YAML: {}", e))?;

    if imported.is_empty() {
        return Err("Imported file contains no mappings".into());
    }

    for entry in &imported {
        match &entry.action {
            ActionConfig::Command { command } if command.trim().is_empty() => {
                return Err("Imported entry has empty command".into());
            }
            ActionConfig::InputSource { input_source_id } if input_source_id.trim().is_empty() => {
                return Err("Imported entry has empty input_source_id".into());
            }
            ActionConfig::Jump { count, .. } if *count == 0 => {
                return Err("Imported entry has jump count of 0".into());
            }
            _ => {}
        }
    }

    normalize_action_mappings(&mut imported);
    let imported_count = imported.len();

    // Update in-memory state and snapshot YAML under a single lock so the
    // file we write matches what the hooks now see.
    let yaml_content = {
        let mut guard = ACTION_MAPPINGS.lock().unwrap();
        *guard = Some(imported);
        render_action_mappings_yaml_with_comments(guard.as_ref().unwrap())
    };

    let dest = get_action_mappings_path(&app)
        .ok_or_else(|| "Could not determine application data directory".to_string())?;
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create config directory: {}", e))?;
    }
    fs::write(&dest, yaml_content)
        .map_err(|e| format!("Failed to persist imported mappings: {}", e))?;

    Ok(ImportResult {
        imported: imported_count,
    })
}

// Legacy API wrappers kept for compatibility.
#[tauri::command]
fn add_mapping(app: AppHandle, key: u16, command: String) -> Result<(), String> {
    upsert_action_mapping(
        app,
        Trigger::HyperPlusKey {
            key,
            with_shift: true,
        },
        ActionConfig::Command { command },
    )
}

#[tauri::command]
fn remove_mapping(app: AppHandle, key: u16) {
    remove_action_mapping(
        app,
        Trigger::HyperPlusKey {
            key,
            with_shift: true,
        },
    );
}

#[tauri::command]
fn get_mappings() -> HashMap<u16, String> {
    let mut out = HashMap::new();
    for entry in get_action_mappings() {
        if let Some((key, true)) = entry.trigger.hyper_plus_key() {
            if let ActionConfig::Command { command } = entry.action {
                out.insert(key, command);
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
        Trigger::HyperPlusKey {
            key,
            with_shift: false,
        },
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
                matches!(
                    m.trigger,
                    Trigger::HyperPlusKey {
                        key: k,
                        with_shift: false,
                    } if k == key
                ) && matches!(m.action, ActionConfig::InputSource { .. })
            })
        })
        .unwrap_or(false);

    if should_remove {
        remove_action_mapping(
            app,
            Trigger::HyperPlusKey {
                key,
                with_shift: false,
            },
        );
    }
}

#[tauri::command]
fn get_input_source_mappings() -> HashMap<u16, String> {
    let mut out = HashMap::new();
    for entry in get_action_mappings() {
        if let Some((key, false)) = entry.trigger.hyper_plus_key() {
            if let ActionConfig::InputSource { input_source_id } = entry.action {
                out.insert(key, input_source_id);
            }
        }
    }
    out
}

fn locale_str_to_static(s: &str) -> &'static str {
    match s {
        "zh" => "zh",
        "ja" => "ja",
        "de" => "de",
        _ => "en",
    }
}

#[tauri::command]
fn set_tray_locale(locale: String) {
    *MENU_LOCALE.lock().unwrap() = locale_str_to_static(&locale);
    let paused = IS_PAUSED.load(Ordering::SeqCst);
    refresh_tray_texts(paused);
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
            *MENU_LOCALE.lock().unwrap() = detect_system_locale();
            load_action_mappings_from_disk(app.handle());
            load_app_config_from_disk(app.handle());
            if APP_CONFIG.lock().unwrap().hide_dock_icon {
                apply_activation_policy(app.handle(), true);
            }

            *APP_HANDLE.lock().unwrap() = Some(app.handle().clone());

            // Transparent, click-through, non-focusing overlay for the mapping
            // HUD. Created hidden; the frontend repositions (bottom-center of
            // the active monitor) and shows/hides it on `hud-show` events.
            let hud = WebviewWindowBuilder::new(
                app,
                "hud",
                WebviewUrl::App("index.html#hud".into()),
            )
            .title("HyperCapslock HUD")
            .inner_size(760.0, 240.0)
            .decorations(false)
            .transparent(true)
            .always_on_top(true)
            .shadow(false)
            .skip_taskbar(true)
            .focused(false)
            .visible(false)
            .resizable(false)
            .build()?;
            let _ = hud.set_ignore_cursor_events(true);
            let status_i =
                MenuItem::with_id(app, "status", menu_text("status_running"), false, None::<&str>)?;
            let toggle_i =
                MenuItem::with_id(app, "toggle", menu_text("stop"), true, None::<&str>)?;
            let check_update_i =
                MenuItem::with_id(app, "check_update", menu_text("check_update"), true, None::<&str>)?;
            let more_apps_i =
                MenuItem::with_id(app, "more_apps", menu_text("more_apps"), true, None::<&str>)?;
            let sep = PredefinedMenuItem::separator(app)?;
            let show_i = MenuItem::with_id(app, "show", menu_text("open"), true, None::<&str>)?;
            let quit_i =
                MenuItem::with_id(app, "quit", menu_text("quit"), true, None::<&str>)?;

            if let Ok(mut guard) = TRAY_TOGGLE_ITEM.lock() {
                *guard = Some(toggle_i.clone());
            }
            if let Ok(mut guard) = TRAY_STATUS_ITEM.lock() {
                *guard = Some(status_i.clone());
            }
            if let Ok(mut guard) = TRAY_CHECK_UPDATE_ITEM.lock() {
                *guard = Some(check_update_i.clone());
            }
            if let Ok(mut guard) = TRAY_SHOW_ITEM.lock() {
                *guard = Some(show_i.clone());
            }
            if let Ok(mut guard) = TRAY_QUIT_ITEM.lock() {
                *guard = Some(quit_i.clone());
            }
            if let Ok(mut guard) = TRAY_MORE_APPS_ITEM.lock() {
                *guard = Some(more_apps_i.clone());
            }

            let menu = Menu::with_items(
                app,
                &[
                    &status_i,
                    &toggle_i,
                    &check_update_i,
                    &more_apps_i,
                    &sep,
                    &show_i,
                    &quit_i,
                ],
            )?;

            #[cfg(target_os = "macos")]
            let tray_icon = Image::from_bytes(ICON_TRAY_TEMPLATE_RUNNING)
                .unwrap_or_else(|_| app.default_window_icon().unwrap().clone());
            #[cfg(not(target_os = "macos"))]
            let tray_icon = app.default_window_icon().unwrap().clone();

            let tray_builder = TrayIconBuilder::with_id("tray")
                .menu(&menu)
                .icon(tray_icon);

            #[cfg(target_os = "macos")]
            let tray_builder = tray_builder.icon_as_template(true);

            let _tray = tray_builder
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
                    "more_apps" => {
                        if let Err(e) =
                            app.opener().open_url("https://xueshi.dev", None::<&str>)
                        {
                            eprintln!("[HYPERCAPS] failed to open xueshi.dev: {}", e);
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
            get_app_config,
            set_hide_dock_icon,
            set_show_hud,
            set_hud_duration,
            open_privacy_settings,
            export_action_mappings_to_path,
            import_action_mappings_from_path,
            add_mapping,
            remove_mapping,
            get_mappings,
            add_input_source_mapping,
            remove_input_source_mapping,
            get_input_source_mappings,
            set_tray_locale
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
        default_action_mappings, normalize_action_mappings,
        render_action_mappings_yaml_with_comments, upsert_action_mapping_in_vec, ActionConfig,
        ActionMappingEntry, DirectionalActionKind, IndependentActionKind, JumpDirection,
        ModifierKey, Trigger, JS_H_KEYCODE, JS_N_KEYCODE, JS_U_KEYCODE,
    };

    #[test]
    fn test_action_mapping_serialization() {
        let entry = ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: 77,
                with_shift: true,
            },
            action: ActionConfig::Command {
                command: "open -a Calculator".to_string(),
            },
        };

        let yaml = serde_yaml::to_string(&entry).unwrap();
        let decoded: ActionMappingEntry = serde_yaml::from_str(&yaml).unwrap();
        assert_eq!(decoded, entry);
    }

    #[test]
    fn test_double_tap_modifier_roundtrip_all_variants() {
        let modifiers = [
            ModifierKey::LeftShift,
            ModifierKey::RightShift,
            ModifierKey::LeftControl,
            ModifierKey::RightControl,
            ModifierKey::LeftOption,
            ModifierKey::RightOption,
            ModifierKey::LeftCommand,
            ModifierKey::RightCommand,
            ModifierKey::Fn,
        ];
        for modifier in modifiers {
            let entry = ActionMappingEntry {
                trigger: Trigger::DoubleTapModifier { modifier },
                action: ActionConfig::Independent {
                    action: IndependentActionKind::Backspace,
                },
            };
            let yaml = serde_yaml::to_string(&entry).unwrap();
            let decoded: ActionMappingEntry = serde_yaml::from_str(&yaml).unwrap();
            assert_eq!(decoded, entry, "serde round-trip failed for {:?}", modifier);
        }
    }

    #[test]
    fn test_double_tap_modifier_yaml_render_and_reparse() {
        let entries = vec![ActionMappingEntry {
            trigger: Trigger::DoubleTapModifier {
                modifier: ModifierKey::LeftCommand,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Left,
            },
        }];
        let yaml = render_action_mappings_yaml_with_comments(&entries);
        assert!(yaml.contains("kind: double_tap_modifier"));
        assert!(yaml.contains("modifier: left_command"));
        let decoded: Vec<ActionMappingEntry> = serde_yaml::from_str(&yaml).unwrap();
        assert_eq!(decoded, entries);
    }

    #[test]
    fn test_double_tap_modifier_sides_are_distinct() {
        let mut mappings = vec![ActionMappingEntry {
            trigger: Trigger::DoubleTapModifier {
                modifier: ModifierKey::LeftShift,
            },
            action: ActionConfig::Independent {
                action: IndependentActionKind::Backspace,
            },
        }];
        // Right shift, double-tap hyper, and a hyper+key binding must all
        // coexist as distinct entries (no dedup collision).
        upsert_action_mapping_in_vec(
            &mut mappings,
            ActionMappingEntry {
                trigger: Trigger::DoubleTapModifier {
                    modifier: ModifierKey::RightShift,
                },
                action: ActionConfig::Independent {
                    action: IndependentActionKind::NextLine,
                },
            },
        );
        upsert_action_mapping_in_vec(
            &mut mappings,
            ActionMappingEntry {
                trigger: Trigger::DoubleTapHyper,
                action: ActionConfig::Independent {
                    action: IndependentActionKind::InsertQuotes,
                },
            },
        );
        normalize_action_mappings(&mut mappings);
        assert_eq!(mappings.len(), 3);
    }

    #[test]
    fn test_double_tap_trigger_serialization() {
        let entry = ActionMappingEntry {
            trigger: Trigger::DoubleTapHyper,
            action: ActionConfig::KeyCombo {
                target_key: 32,
                with_ctrl: true,
                with_alt: true,
                with_cmd: false,
                with_target_shift: false,
            },
        };

        let yaml = serde_yaml::to_string(&entry).unwrap();
        let decoded: ActionMappingEntry = serde_yaml::from_str(&yaml).unwrap();
        assert_eq!(decoded, entry);
    }

    #[test]
    fn test_legacy_yaml_loads_as_hyper_plus_key() {
        let legacy =
            "- key: 72\n  with_shift: false\n  action:\n    kind: directional\n    action: left\n";
        let decoded: Vec<ActionMappingEntry> = serde_yaml::from_str(legacy).unwrap();
        assert_eq!(decoded.len(), 1);
        assert_eq!(
            decoded[0].trigger,
            Trigger::HyperPlusKey {
                key: 72,
                with_shift: false,
            }
        );
    }

    #[test]
    fn test_yaml_render_contains_key_name_comment() {
        let entries = vec![ActionMappingEntry {
            trigger: Trigger::HyperPlusKey {
                key: 87,
                with_shift: false,
            },
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
            matches!(
                m.trigger,
                Trigger::HyperPlusKey {
                    key: JS_H_KEYCODE,
                    with_shift: false,
                }
            ) && matches!(
                m.action,
                ActionConfig::Directional {
                    action: DirectionalActionKind::Left
                }
            )
        }));
        assert!(defaults.iter().any(|m| {
            matches!(
                m.trigger,
                Trigger::HyperPlusKey {
                    key: JS_U_KEYCODE,
                    ..
                }
            ) && matches!(
                m.action,
                ActionConfig::Jump {
                    direction: JumpDirection::Up,
                    count: 10
                }
            )
        }));
        assert!(defaults.iter().any(|m| {
            matches!(
                m.trigger,
                Trigger::HyperPlusKey {
                    key: JS_N_KEYCODE,
                    ..
                }
            ) && matches!(
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
            trigger: Trigger::HyperPlusKey {
                key: 65,
                with_shift: false,
            },
            action: ActionConfig::Directional {
                action: DirectionalActionKind::Left,
            },
        }];

        let changed = upsert_action_mapping_in_vec(
            &mut mappings,
            ActionMappingEntry {
                trigger: Trigger::HyperPlusKey {
                    key: 65,
                    with_shift: false,
                },
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

    #[test]
    fn test_double_tap_dedups_by_trigger() {
        let mut mappings = vec![ActionMappingEntry {
            trigger: Trigger::DoubleTapHyper,
            action: ActionConfig::Command {
                command: "first".into(),
            },
        }];
        upsert_action_mapping_in_vec(
            &mut mappings,
            ActionMappingEntry {
                trigger: Trigger::DoubleTapHyper,
                action: ActionConfig::Command {
                    command: "second".into(),
                },
            },
        );
        assert_eq!(mappings.len(), 1);
        if let ActionConfig::Command { command } = &mappings[0].action {
            assert_eq!(command, "second");
        } else {
            panic!("expected command action");
        }
    }
}
