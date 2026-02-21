use std::ffi::c_void;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use core_foundation::base::TCFType;
use core_foundation::runloop::CFRunLoop;
use core_foundation::string::CFString;
use core_graphics::event::{
    CGEvent, CGEventFlags, CGEventTap, CGEventTapLocation, CGEventTapOptions, CGEventTapPlacement,
    CGEventType, EventField,
};
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

use crate::{
    ActionConfig, ActionMappingEntry, DirectionalActionKind, IndependentActionKind, JumpDirection,
    ACTION_MAPPINGS, CAPS_DOWN, CAPS_PRESSED_AT_MS, DID_REMAP, IS_PAUSED,
};

// Magic value stamped on injected events to prevent feedback loops
const INJECTED_EVENT_MAGIC: i64 = 0x4756_4C4E; // "GVLN"

// macOS keycodes
const KC_CAPS_LOCK: u16 = 0x39;
const KC_F18: u16 = 0x4F; // CapsLock is remapped to F18 via hidutil
const KC_RETURN: u16 = 0x24;
const KC_DELETE: u16 = 0x33; // Backspace on macOS
const KC_LEFT: u16 = 0x7B;
const KC_RIGHT: u16 = 0x7C;
const KC_DOWN: u16 = 0x7D;
const KC_UP: u16 = 0x7E;

const MACOS_LOG_PATH: &str = "/tmp/hypercapslock-macos.log";
const CAPS_TAP_MAX_MS: u64 = 200;
static LOG_LOCK: OnceLock<Mutex<()>> = OnceLock::new();
static EVENT_TAP_PORT: AtomicUsize = AtomicUsize::new(0);

#[repr(C)]
struct DispatchObject {
    _private: [u8; 0],
}

type DispatchQueue = *mut DispatchObject;

fn log_macos(level: &str, msg: &str) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let line = format!("[HYPERCAPS][macOS][{}][{}] {}", ts, level, msg);
    eprintln!("{}", line);

    let lock = LOG_LOCK.get_or_init(|| Mutex::new(()));
    if let Ok(_guard) = lock.lock() {
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(MACOS_LOG_PATH)
        {
            use std::io::Write;
            let _ = writeln!(f, "{}", line);
        }
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn reenable_event_tap() -> bool {
    extern "C" {
        fn CGEventTapEnable(tap: *mut std::ffi::c_void, enable: bool);
    }

    let tap_port = EVENT_TAP_PORT.load(Ordering::SeqCst);
    if tap_port == 0 {
        return false;
    }

    unsafe {
        CGEventTapEnable(tap_port as *mut std::ffi::c_void, true);
    }
    true
}

fn switch_input_source_by_id(input_source_id: &str) -> Result<(), String> {
    #[link(name = "Carbon", kind = "framework")]
    extern "C" {
        fn TISCreateInputSourceList(
            properties: *const std::ffi::c_void,
            include_all_installed: u8,
        ) -> *const std::ffi::c_void;
        fn TISSelectInputSource(input_source: *const std::ffi::c_void) -> i32;
        static kTISPropertyInputSourceID: *const std::ffi::c_void;
    }
    extern "C" {
        fn CFDictionaryCreate(
            allocator: *const std::ffi::c_void,
            keys: *const *const std::ffi::c_void,
            values: *const *const std::ffi::c_void,
            num_values: isize,
            key_callbacks: *const std::ffi::c_void,
            value_callbacks: *const std::ffi::c_void,
        ) -> *const std::ffi::c_void;
        fn CFArrayGetCount(the_array: *const std::ffi::c_void) -> isize;
        fn CFArrayGetValueAtIndex(
            the_array: *const std::ffi::c_void,
            idx: isize,
        ) -> *const std::ffi::c_void;
        fn CFRelease(cf: *const std::ffi::c_void);
        static kCFTypeDictionaryKeyCallBacks: std::ffi::c_void;
        static kCFTypeDictionaryValueCallBacks: std::ffi::c_void;
    }

    let source_id = CFString::new(input_source_id);

    unsafe {
        let keys = [kTISPropertyInputSourceID];
        let values = [source_id.as_concrete_TypeRef() as *const std::ffi::c_void];
        let filter = CFDictionaryCreate(
            std::ptr::null(),
            keys.as_ptr(),
            values.as_ptr(),
            1,
            &kCFTypeDictionaryKeyCallBacks as *const _ as *const std::ffi::c_void,
            &kCFTypeDictionaryValueCallBacks as *const _ as *const std::ffi::c_void,
        );
        if filter.is_null() {
            return Err("CFDictionaryCreate returned null".to_string());
        }

        let input_sources = TISCreateInputSourceList(filter, 0);
        CFRelease(filter);

        if input_sources.is_null() {
            return Err("TISCreateInputSourceList returned null".to_string());
        }

        let count = CFArrayGetCount(input_sources);
        if count <= 0 {
            CFRelease(input_sources);
            return Err(format!("Input source not found: {}", input_source_id));
        }

        let source = CFArrayGetValueAtIndex(input_sources, 0);
        if source.is_null() {
            CFRelease(input_sources);
            return Err("Resolved input source pointer is null".to_string());
        }

        let status = TISSelectInputSource(source);
        CFRelease(input_sources);

        if status != 0 {
            return Err(format!(
                "TISSelectInputSource failed with status {}",
                status
            ));
        }
    }

    Ok(())
}

extern "C" fn switch_input_source_on_main_queue(context: *mut c_void) {
    let source_id = unsafe { Box::from_raw(context as *mut String) };
    let result = std::panic::catch_unwind(|| switch_input_source_by_id(&source_id));

    match result {
        Ok(Ok(())) => {
            log_macos(
                "INFO",
                &format!(
                    "Input source mapping switched on main queue: source_id={}",
                    source_id
                ),
            );
        }
        Ok(Err(e)) => {
            log_macos(
                "WARN",
                &format!(
                    "Input source mapping failed on main queue: source_id={} error={}",
                    source_id, e
                ),
            );
        }
        Err(_) => {
            log_macos(
                "ERROR",
                &format!(
                    "Input source mapping panicked on main queue: source_id={}",
                    source_id
                ),
            );
        }
    }
}

fn queue_input_source_switch_on_main(source_id: String) {
    #[link(name = "System", kind = "dylib")]
    extern "C" {
        static _dispatch_main_q: DispatchObject;
        fn dispatch_async_f(
            queue: DispatchQueue,
            context: *mut c_void,
            work: extern "C" fn(*mut c_void),
        );
    }

    let context_ptr = Box::into_raw(Box::new(source_id)) as *mut c_void;
    unsafe {
        // HIToolbox asserts these APIs run on the main queue; calling from the event-tap thread can crash.
        let main_queue = &_dispatch_main_q as *const _ as DispatchQueue;
        dispatch_async_f(main_queue, context_ptr, switch_input_source_on_main_queue);
    }
}

fn mac_keycode_to_js_keycode(mac_keycode: u16) -> Option<u16> {
    match mac_keycode {
        0x00 => Some(65),  // A
        0x0B => Some(66),  // B
        0x08 => Some(67),  // C
        0x02 => Some(68),  // D
        0x0E => Some(69),  // E
        0x03 => Some(70),  // F
        0x05 => Some(71),  // G
        0x04 => Some(72),  // H
        0x22 => Some(73),  // I
        0x26 => Some(74),  // J
        0x28 => Some(75),  // K
        0x25 => Some(76),  // L
        0x2E => Some(77),  // M
        0x2D => Some(78),  // N
        0x1F => Some(79),  // O
        0x23 => Some(80),  // P
        0x0C => Some(81),  // Q
        0x0F => Some(82),  // R
        0x01 => Some(83),  // S
        0x11 => Some(84),  // T
        0x20 => Some(85),  // U
        0x09 => Some(86),  // V
        0x0D => Some(87),  // W
        0x07 => Some(88),  // X
        0x10 => Some(89),  // Y
        0x06 => Some(90),  // Z
        0x1D => Some(48),  // 0
        0x12 => Some(49),  // 1
        0x13 => Some(50),  // 2
        0x14 => Some(51),  // 3
        0x15 => Some(52),  // 4
        0x16 => Some(53),  // 5
        0x17 => Some(54),  // 6
        0x18 => Some(55),  // 7
        0x19 => Some(56),  // 8
        0x1A => Some(57),  // 9
        0x2B => Some(188), // ,
        0x2F => Some(190), // .
        _ => None,
    }
}

/// Helper to compare CGEventType values (the enum doesn't implement PartialEq)
fn event_type_matches(a: CGEventType, b: CGEventType) -> bool {
    (a as u32) == (b as u32)
}

/// Toggle CapsLock state via IOKit (the only reliable way on macOS).
fn toggle_caps_lock() {
    #[link(name = "IOKit", kind = "framework")]
    extern "C" {
        fn IOServiceGetMatchingService(mainPort: u32, matching: *mut std::ffi::c_void) -> u32;
        fn IOServiceMatching(name: *const i8) -> *mut std::ffi::c_void;
        fn IOServiceOpen(service: u32, owning_task: u32, r#type: u32, connect: *mut u32) -> i32;
        fn IOServiceClose(connect: u32) -> i32;
        fn IOObjectRelease(object: u32) -> i32;
        fn IOHIDGetModifierLockState(handle: u32, selector: i32, state: *mut bool) -> i32;
        fn IOHIDSetModifierLockState(handle: u32, selector: i32, state: bool) -> i32;
    }
    extern "C" {
        static mach_task_self_: u32;
    }

    const KIO_HID_PARAM_CONNECT_TYPE: u32 = 1;
    const KIO_HID_CAPS_LOCK_STATE: i32 = 1;

    unsafe {
        let matching = IOServiceMatching(b"IOHIDSystem\0".as_ptr() as *const i8);
        if matching.is_null() {
            log_macos("ERROR", "IOServiceMatching(IOHIDSystem) returned null.");
            return;
        }
        let service = IOServiceGetMatchingService(0, matching);
        if service == 0 {
            log_macos(
                "ERROR",
                "IOServiceGetMatchingService(IOHIDSystem) returned 0.",
            );
            return;
        }

        let mut connect: u32 = 0;
        let kr = IOServiceOpen(
            service,
            mach_task_self_,
            KIO_HID_PARAM_CONNECT_TYPE,
            &mut connect,
        );
        IOObjectRelease(service);
        if kr != 0 {
            log_macos("ERROR", &format!("IOServiceOpen failed with code {}.", kr));
            return;
        }

        let mut current_state = false;
        IOHIDGetModifierLockState(connect, KIO_HID_CAPS_LOCK_STATE, &mut current_state);
        IOHIDSetModifierLockState(connect, KIO_HID_CAPS_LOCK_STATE, !current_state);
        log_macos(
            "INFO",
            &format!(
                "CapsLock toggled via IOKit: previous_state={} new_state={}",
                current_state, !current_state
            ),
        );

        IOServiceClose(connect);
    }
}

fn post_key(keycode: u16, key_down: bool, flags: CGEventFlags) {
    if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
        if let Ok(event) = CGEvent::new_keyboard_event(source, keycode, key_down) {
            event.set_flags(flags);
            event.set_integer_value_field(EventField::EVENT_SOURCE_USER_DATA, INJECTED_EVENT_MAGIC);
            event.post(CGEventTapLocation::HID);
        }
    }
}

fn post_key_tap(keycode: u16, flags: CGEventFlags) {
    post_key(keycode, true, flags);
    post_key(keycode, false, flags);
}

fn post_key_simple(keycode: u16, key_down: bool, flags: CGEventFlags) {
    post_key(keycode, key_down, flags);
}

fn active_modifier_flags(flags: CGEventFlags) -> CGEventFlags {
    flags
        & (CGEventFlags::CGEventFlagShift
            | CGEventFlags::CGEventFlagControl
            | CGEventFlags::CGEventFlagAlternate
            | CGEventFlags::CGEventFlagCommand
            | CGEventFlags::CGEventFlagSecondaryFn)
}

fn allow_shift_fallback(action: &ActionConfig) -> bool {
    !matches!(
        action,
        ActionConfig::InputSource { .. } | ActionConfig::Command { .. }
    )
}

fn resolve_action_mapping(js_keycode: u16, shift_held: bool) -> Option<ActionMappingEntry> {
    let guard = ACTION_MAPPINGS.lock().unwrap();
    let mappings = guard.as_ref()?;

    if let Some(entry) = mappings
        .iter()
        .find(|m| m.key == js_keycode && m.with_shift == shift_held)
    {
        return Some(entry.clone());
    }

    if shift_held {
        if let Some(entry) = mappings
            .iter()
            .find(|m| m.key == js_keycode && !m.with_shift && allow_shift_fallback(&m.action))
        {
            return Some(entry.clone());
        }
    }

    None
}

fn execute_action_mapping(action: &ActionConfig, key_down: bool, active_modifiers: CGEventFlags) {
    match action {
        ActionConfig::Directional { action } => match action {
            DirectionalActionKind::Left => post_key_simple(KC_LEFT, key_down, active_modifiers),
            DirectionalActionKind::Right => post_key_simple(KC_RIGHT, key_down, active_modifiers),
            DirectionalActionKind::Up => post_key_simple(KC_UP, key_down, active_modifiers),
            DirectionalActionKind::Down => post_key_simple(KC_DOWN, key_down, active_modifiers),
            DirectionalActionKind::WordForward => post_key(
                KC_RIGHT,
                key_down,
                active_modifiers | CGEventFlags::CGEventFlagAlternate,
            ),
            DirectionalActionKind::WordBack => post_key(
                KC_LEFT,
                key_down,
                active_modifiers | CGEventFlags::CGEventFlagAlternate,
            ),
            DirectionalActionKind::Home => post_key(
                KC_LEFT,
                key_down,
                active_modifiers | CGEventFlags::CGEventFlagCommand,
            ),
            DirectionalActionKind::End => post_key(
                KC_RIGHT,
                key_down,
                active_modifiers | CGEventFlags::CGEventFlagCommand,
            ),
        },
        ActionConfig::Jump { direction, count } => {
            if key_down {
                let keycode = match direction {
                    JumpDirection::Up => KC_UP,
                    JumpDirection::Down => KC_DOWN,
                };
                for _ in 0..*count {
                    post_key_tap(keycode, active_modifiers);
                }
            }
        }
        ActionConfig::Independent { action } => match action {
            IndependentActionKind::Backspace => {
                post_key_simple(KC_DELETE, key_down, active_modifiers);
            }
            IndependentActionKind::NextLine => {
                if key_down {
                    post_key_tap(KC_RIGHT, CGEventFlags::CGEventFlagCommand);
                    post_key_tap(KC_RETURN, CGEventFlags::empty());
                }
            }
            IndependentActionKind::InsertQuotes => {
                if key_down {
                    for _ in 0..6 {
                        if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
                            if let Ok(event) = CGEvent::new_keyboard_event(source, 0, true) {
                                event.set_string("\"");
                                event.set_integer_value_field(
                                    EventField::EVENT_SOURCE_USER_DATA,
                                    INJECTED_EVENT_MAGIC,
                                );
                                event.post(CGEventTapLocation::HID);
                            }
                        }
                    }
                    for _ in 0..3 {
                        post_key_tap(KC_LEFT, CGEventFlags::empty());
                    }
                }
            }
        },
        ActionConfig::InputSource { input_source_id } => {
            if key_down {
                log_macos(
                    "INFO",
                    &format!(
                        "Queueing input source mapping switch: source_id={}",
                        input_source_id
                    ),
                );
                queue_input_source_switch_on_main(input_source_id.clone());
            }
        }
        ActionConfig::Command { command } => {
            if key_down {
                let cmd_str = command.clone();
                log_macos(
                    "INFO",
                    &format!("Shell mapping triggered: command={}", cmd_str),
                );
                thread::spawn(move || {
                    let spawn_result = std::process::Command::new("sh")
                        .arg("-c")
                        .arg(&cmd_str)
                        .spawn();
                    if let Err(e) = spawn_result {
                        log_macos("ERROR", &format!("Failed to spawn shell mapping: {}", e));
                    }
                });
            }
        }
    }
}

fn handle_caps_remap(keycode: u16, key_down: bool, active_modifiers: CGEventFlags) -> bool {
    let shift_held = active_modifiers.contains(CGEventFlags::CGEventFlagShift);
    let Some(js_keycode) = mac_keycode_to_js_keycode(keycode) else {
        return false;
    };

    let Some(mapping) = resolve_action_mapping(js_keycode, shift_held) else {
        return false;
    };

    execute_action_mapping(&mapping.action, key_down, active_modifiers);
    true
}

/// Check if Accessibility permission is granted.
fn check_accessibility_permission() -> bool {
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
    }
    unsafe { AXIsProcessTrusted() }
}

/// Prompt the user for Accessibility permission via system dialog.
fn prompt_accessibility_permission() {
    extern "C" {
        fn AXIsProcessTrustedWithOptions(options: *const std::ffi::c_void) -> bool;
    }
    extern "C" {
        fn CFDictionaryCreate(
            allocator: *const std::ffi::c_void,
            keys: *const *const std::ffi::c_void,
            values: *const *const std::ffi::c_void,
            num_values: isize,
            key_callbacks: *const std::ffi::c_void,
            value_callbacks: *const std::ffi::c_void,
        ) -> *const std::ffi::c_void;
        fn CFRelease(cf: *const std::ffi::c_void);
        static kAXTrustedCheckOptionPrompt: *const std::ffi::c_void;
        static kCFBooleanTrue: *const std::ffi::c_void;
        static kCFTypeDictionaryKeyCallBacks: std::ffi::c_void;
        static kCFTypeDictionaryValueCallBacks: std::ffi::c_void;
    }
    unsafe {
        let keys = [kAXTrustedCheckOptionPrompt];
        let values = [kCFBooleanTrue];
        let options = CFDictionaryCreate(
            std::ptr::null(),
            keys.as_ptr(),
            values.as_ptr(),
            1,
            &kCFTypeDictionaryKeyCallBacks as *const _ as *const std::ffi::c_void,
            &kCFTypeDictionaryValueCallBacks as *const _ as *const std::ffi::c_void,
        );
        AXIsProcessTrustedWithOptions(options);
        if !options.is_null() {
            CFRelease(options);
        }
    }
}

/// Remap CapsLock to F18 at the HID level using hidutil.
/// This gives us proper KeyDown/KeyUp events instead of the unreliable
/// FlagsChanged toggle events that macOS sends for CapsLock.
fn setup_capslock_remap() -> bool {
    let output = std::process::Command::new("hidutil")
        .args([
            "property",
            "--set",
            r#"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#,
        ])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            log_macos("INFO", "hidutil remapped CapsLock to F18 successfully.");
            true
        }
        Ok(o) => {
            log_macos(
                "ERROR",
                &format!(
                    "hidutil remap failed (status={}): {}",
                    o.status,
                    String::from_utf8_lossy(&o.stderr)
                ),
            );
            false
        }
        Err(e) => {
            log_macos(
                "ERROR",
                &format!("Failed to execute hidutil remap command: {}", e),
            );
            false
        }
    }
}

/// Restore original key mapping (remove our CapsLock→F18 remap).
pub fn cleanup_capslock_remap() {
    let output = std::process::Command::new("hidutil")
        .args(["property", "--set", r#"{"UserKeyMapping":[]}"#])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            log_macos("INFO", "hidutil remap removed.");
        }
        Ok(o) => {
            log_macos(
                "WARN",
                &format!(
                    "Failed to remove hidutil remap (status={}): {}",
                    o.status,
                    String::from_utf8_lossy(&o.stderr)
                ),
            );
        }
        Err(e) => {
            log_macos(
                "WARN",
                &format!("Failed to execute hidutil cleanup command: {}", e),
            );
        }
    }
}

pub fn start_keyboard_hook() {
    EVENT_TAP_PORT.store(0, Ordering::SeqCst);
    log_macos("INFO", "Starting macOS keyboard hook.");
    log_macos("INFO", &format!("Log file path: {}", MACOS_LOG_PATH));

    if !check_accessibility_permission() {
        log_macos(
            "WARN",
            "Accessibility permission not granted. Prompting system dialog.",
        );
        prompt_accessibility_permission();
    } else {
        log_macos("INFO", "Accessibility permission already granted.");
    }

    // Remap CapsLock → F18 via hidutil so we get proper KeyDown/KeyUp events
    if !setup_capslock_remap() {
        log_macos(
            "WARN",
            "Could not remap CapsLock via hidutil. Caps modifier may be unreliable.",
        );
    }

    thread::spawn(|| {
        log_macos("INFO", "macOS hook thread spawned.");
        let current = CFRunLoop::get_current();

        let tap = CGEventTap::new(
            CGEventTapLocation::HID,
            CGEventTapPlacement::HeadInsertEventTap,
            CGEventTapOptions::Default,
            vec![
                CGEventType::KeyDown,
                CGEventType::KeyUp,
                CGEventType::FlagsChanged,
            ],
            |_proxy, event_type, event| {
                // Re-enable tap if macOS disabled it due to timeout
                if event_type_matches(event_type, CGEventType::TapDisabledByTimeout)
                    || event_type_matches(event_type, CGEventType::TapDisabledByUserInput)
                {
                    if reenable_event_tap() {
                        log_macos(
                            "WARN",
                            &format!(
                                "Event tap disabled by system (event_type={:?}); requested re-enable.",
                                event_type
                            ),
                        );
                    } else {
                        log_macos(
                            "ERROR",
                            &format!(
                                "Event tap disabled by system (event_type={:?}); could not re-enable because tap port is unknown.",
                                event_type
                            ),
                        );
                    }
                    return None;
                }

                // Skip our own injected events
                if event.get_integer_value_field(EventField::EVENT_SOURCE_USER_DATA)
                    == INJECTED_EVENT_MAGIC
                {
                    return None;
                }

                // If paused, pass everything through
                if IS_PAUSED.load(Ordering::SeqCst) {
                    return None;
                }

                let keycode =
                    event.get_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE) as u16;
                let flags = event.get_flags();

                // F18 = physical CapsLock (remapped via hidutil)
                // Now we get proper KeyDown/KeyUp instead of FlagsChanged toggle
                if keycode == KC_F18 {
                    let is_down = event_type_matches(event_type, CGEventType::KeyDown);
                    let is_up = event_type_matches(event_type, CGEventType::KeyUp);

                    if is_down {
                        let was_down = CAPS_DOWN.swap(true, Ordering::SeqCst);
                        if !was_down {
                            CAPS_PRESSED_AT_MS.store(now_millis(), Ordering::SeqCst);
                            DID_REMAP.store(false, Ordering::SeqCst);
                            log_macos("INFO", "Caps(F18) down.");
                        }
                    } else if is_up {
                        let was_down = CAPS_DOWN.swap(false, Ordering::SeqCst);
                        let pressed_at_ms = CAPS_PRESSED_AT_MS.swap(0, Ordering::SeqCst);
                        let held_ms = now_millis().saturating_sub(pressed_at_ms);

                        if was_down && !DID_REMAP.load(Ordering::SeqCst) {
                            if held_ms <= CAPS_TAP_MAX_MS {
                                // Toggle native CapsLock only for short taps.
                                log_macos(
                                    "INFO",
                                    &format!(
                                        "Caps(F18) short tap detected ({}ms). Toggling CapsLock.",
                                        held_ms
                                    ),
                                );
                                toggle_caps_lock();
                            } else {
                                log_macos(
                                    "INFO",
                                    &format!(
                                        "Caps(F18) held {}ms (> {}ms). Suppressing native CapsLock toggle.",
                                        held_ms, CAPS_TAP_MAX_MS
                                    ),
                                );
                            }
                        } else if was_down {
                            log_macos("INFO", "Caps(F18) up after remap sequence.");
                        }
                    }
                    // Swallow the F18 event
                    event.set_type(CGEventType::Null);
                    return None;
                }

                // Also handle raw CapsLock FlagsChanged in case hidutil isn't active
                if event_type_matches(event_type, CGEventType::FlagsChanged)
                    && keycode == KC_CAPS_LOCK
                {
                    // Swallow — we handle CapsLock via F18 now
                    event.set_type(CGEventType::Null);
                    return None;
                }

                // Handle remapping when CapsLock is held
                if CAPS_DOWN.load(Ordering::SeqCst) {
                    let key_down = event_type_matches(event_type, CGEventType::KeyDown);
                    let active_modifiers = active_modifier_flags(flags);
                    let shift_held = active_modifiers.contains(CGEventFlags::CGEventFlagShift);

                    if handle_caps_remap(keycode, key_down, active_modifiers) {
                        DID_REMAP.store(true, Ordering::SeqCst);
                        if key_down {
                            log_macos(
                                "INFO",
                                &format!(
                                    "Caps remap handled keydown: keycode={} shift={}",
                                    keycode, shift_held
                                ),
                            );
                        }
                        event.set_type(CGEventType::Null);
                        return None;
                    }
                }

                None
            },
        );

        match tap {
            Ok(tap) => unsafe {
                EVENT_TAP_PORT.store(
                    tap.mach_port.as_concrete_TypeRef() as usize,
                    Ordering::SeqCst,
                );
                let loop_source = tap
                    .mach_port
                    .create_runloop_source(0)
                    .expect("Failed to create run loop source");
                current.add_source(
                    &loop_source,
                    core_foundation::runloop::kCFRunLoopCommonModes,
                );
                tap.enable();
                log_macos("INFO", "macOS keyboard event tap installed and enabled.");
                CFRunLoop::run_current();
            },
            Err(()) => {
                EVENT_TAP_PORT.store(0, Ordering::SeqCst);
                log_macos(
                    "ERROR",
                    "Failed to create CGEventTap. Check Accessibility/Input Monitoring permissions.",
                );
            }
        }
    });
}
