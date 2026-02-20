use std::os::windows::process::CommandExt;
use std::thread;
use windows::Win32::Foundation::{HMODULE, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS,
    KEYEVENTF_KEYUP, KEYEVENTF_UNICODE, VIRTUAL_KEY, VK_A, VK_BACK, VK_CAPITAL, VK_D, VK_DOWN,
    VK_E, VK_END, VK_H, VK_HOME, VK_I, VK_J, VK_K, VK_L, VK_LCONTROL, VK_LEFT, VK_N, VK_O, VK_P,
    VK_RETURN, VK_RIGHT, VK_SHIFT, VK_U, VK_UP, VK_Y,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageA, GetMessageA, SetWindowsHookExA, UnhookWindowsHookEx, HHOOK,
    KBDLLHOOKSTRUCT, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP,
};

use crate::{CAPS_DOWN, DID_REMAP, IS_PAUSED, SHELL_MAPPINGS};
use std::sync::atomic::Ordering;

static mut HOOK: HHOOK = HHOOK(0);

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

unsafe fn send_unicode(ch: u16) {
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
    let is_injected = (flags.0 & 0x10) != 0;
    let is_up = wparam.0 as u32 == WM_KEYUP || wparam.0 as u32 == WM_SYSKEYUP;
    let is_down = wparam.0 as u32 == WM_KEYDOWN || wparam.0 as u32 == WM_SYSKEYDOWN;

    if is_injected {
        return CallNextHookEx(HOOK, code, wparam, lparam);
    }

    if vk == VK_CAPITAL {
        if is_down {
            CAPS_DOWN.store(true, Ordering::SeqCst);
            DID_REMAP.store(false, Ordering::SeqCst);
            return LRESULT(1);
        } else if is_up {
            CAPS_DOWN.store(false, Ordering::SeqCst);
            if !DID_REMAP.load(Ordering::SeqCst) {
                send_key(VK_CAPITAL, false);
                send_key(VK_CAPITAL, true);
            }
            return LRESULT(1);
        }
    }

    if CAPS_DOWN.load(Ordering::SeqCst) {
        let mut handled = false;

        let shift_down = (GetAsyncKeyState(VK_SHIFT.0 as i32) as u16 & 0x8000) != 0;

        if shift_down && is_down {
            let guard = SHELL_MAPPINGS.lock().unwrap();
            if let Some(mappings) = &*guard {
                if let Some(cmd) = mappings.get(&vk.0) {
                    let cmd_str = cmd.clone();
                    thread::spawn(move || {
                        let _ = std::process::Command::new("cmd")
                            .arg("/C")
                            .arg(&cmd_str)
                            .creation_flags(0x08000000)
                            .spawn();
                    });
                    handled = true;
                }
            }
        }

        if !handled {
            match vk {
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
                VK_I => {
                    send_key(VK_BACK, is_up);
                    handled = true;
                }
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
                VK_P => {
                    if is_down {
                        send_key(VK_LCONTROL, false);
                        send_key(VK_RIGHT, false);
                    } else {
                        send_key(VK_RIGHT, true);
                        send_key(VK_LCONTROL, true);
                    }
                    handled = true;
                }
                VK_Y => {
                    if is_down {
                        send_key(VK_LCONTROL, false);
                        send_key(VK_LEFT, false);
                    } else {
                        send_key(VK_LEFT, true);
                        send_key(VK_LCONTROL, true);
                    }
                    handled = true;
                }
                VK_A => {
                    send_key(VK_HOME, is_up);
                    handled = true;
                }
                VK_E => {
                    send_key(VK_END, is_up);
                    handled = true;
                }
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
        }

        if handled {
            DID_REMAP.store(true, Ordering::SeqCst);
            return LRESULT(1);
        }
    }

    CallNextHookEx(HOOK, code, wparam, lparam)
}

pub fn start_keyboard_hook() {
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
