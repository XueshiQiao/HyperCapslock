import AppKit

// Pure-AppKit entry (no SwiftUI @main scene) so the app fully controls its
// tray, HUD panel, and close-to-hide window behavior. SwiftUI views are hosted
// inside AppKit windows via NSHostingController/NSHostingView.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // bootstrap() adjusts this for hide-dock
app.run()
