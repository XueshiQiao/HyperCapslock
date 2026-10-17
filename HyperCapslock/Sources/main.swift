import AppKit

// Pure-AppKit entry (no SwiftUI @main scene) so the app fully controls its
// tray, HUD panel, and close-to-hide window behavior. SwiftUI views are hosted
// inside AppKit windows via NSHostingController/NSHostingView.
// `--capslock-watchdog <pid>`: we were re-executed as the CapsLock remap
// watchdog (#28). Must branch before NSApplication exists — no UI at all.
let args = CommandLine.arguments
if let i = args.firstIndex(of: CapsLockWatchdog.argument), i + 1 < args.count,
   let parent = pid_t(args[i + 1]) {
  CapsLockWatchdog.run(watching: parent)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // bootstrap() adjusts this for hide-dock
app.run()
