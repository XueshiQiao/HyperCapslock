import Carbon
import Foundation

/// macOS **Secure Event Input** — the system-wide switch an app turns on while a
/// password field is up (a password manager's unlock screen, a `sudo` prompt in
/// a terminal, a browser password box, the login window). Its whole purpose is
/// to stop keyloggers, so while it is on macOS delivers **no key events to any
/// `CGEventTap`**.
///
/// That is the exact mechanism this app is built on, so every CapsLock/F18
/// mapping goes dead — silently, and through no fault of ours. Worse, the
/// failure looks like a bug in HyperCapslock: modifier-only events
/// (`flagsChanged`) keep flowing, so a double-tap-⌘ mapping still fires while
/// every CapsLock chord stops responding.
///
/// We can only observe this, never clear it: the fix is always for the user to
/// dismiss whatever password prompt is open. So the app's job is to *say so*,
/// which is what `SecureInputMonitor` and the menu-bar icon do.
///
/// **We deliberately do not try to name the app responsible.** The obvious
/// source, `kCGSSessionSecureInputPID` in the IORegistry's `IOConsoleUsers`, is
/// NOT the process that called `EnableSecureEventInput` — measured here on
/// 2026-08-23, it recorded whichever app merely held keyboard focus at the
/// moment secure input came on (a CLI tool enabling it was reported as "Google
/// Chrome"), and it can also name a process that has since exited. Showing that
/// name would confidently accuse an innocent app, which is worse than saying
/// nothing, so the UI describes the *kind* of prompt to look for instead.
enum SecureInput {
  /// Whether macOS is currently withholding key events from event taps.
  static var isEnabled: Bool { IsSecureEventInputEnabled() }
}
