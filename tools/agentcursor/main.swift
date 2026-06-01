import AppKit
import ApplicationServices

// agentcursor — a tiny computer-use engine for HyperCapslock.
//
// Usage:  agentcursor <step> [<step> ...]
//   press:<ax-id>            AXPress the control (buttons, etc.)
//   type:<ax-id>:<char>      focus the control + synthesize that key (a-z)
//   menu:<ax-id>:<title>     open a menu/popup control + click the item titled <title>
//   <ax-id>                  shorthand for press:<ax-id>
//
// For each step it AX-finds the control in the running HyperCapslock(-Dev) app,
// glides an INDEPENDENT fake cursor to it (a transparent click-through overlay —
// the real system mouse is never touched), then performs the action. So an agent
// can script real operations against the app's UI without hijacking the mouse.
// Build: `swiftc -O main.swift -o agentcursor`. Needs the host terminal to have
// Accessibility permission (inherited; no separate grant).

// ---- AX helpers ----
func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func find(_ el: AXUIElement, _ id: String, _ d: Int = 0) -> AXUIElement? {
    if d > 100 { return nil }
    if let s = attr(el, "AXIdentifier") as? String, s == id { return el }
    if let kids = attr(el, kAXChildrenAttribute as String) as? [AXUIElement] {
        for k in kids { if let f = find(k, id, d + 1) { return f } }
    }
    return nil
}
func findByRoleTitle(_ el: AXUIElement, role: String, title: String, _ d: Int = 0) -> AXUIElement? {
    if d > 100 { return nil }
    if let r = attr(el, kAXRoleAttribute as String) as? String, r == role,
       let t = attr(el, kAXTitleAttribute as String) as? String, t == title { return el }
    if let kids = attr(el, kAXChildrenAttribute as String) as? [AXUIElement] {
        for k in kids { if let f = findByRoleTitle(k, role: role, title: title, d + 1) { return f } }
    }
    return nil
}
func frameOf(_ el: AXUIElement) -> CGRect? {
    guard let pv = attr(el, kAXPositionAttribute as String), CFGetTypeID(pv) == AXValueGetTypeID(),
          let sv = attr(el, kAXSizeAttribute as String), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

// a-z -> ANSI virtual keycode
let keyCodes: [Character: CGKeyCode] = [
    "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,
    "e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,
    "n":45,"m":46,
]

// ---- fake cursor ----
final class CursorView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath()
        let pts: [NSPoint] = [(1,1),(1,20),(6,15),(10,23),(13,22),(9,14),(16,14)].map { NSPoint(x: $0.0, y: $0.1) }
        p.move(to: pts[0]); for q in pts.dropFirst() { p.line(to: q) }; p.close()
        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 4, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        NSColor.white.setStroke(); p.lineWidth = 3; p.stroke()
        NSColor.systemBlue.setFill(); p.fill()
    }
    func pulse() {
        let r: CGFloat = 9
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2*r, height: 2*r), transform: nil)
        ring.position = CGPoint(x: 3, y: 3)
        ring.fillColor = NSColor.clear.cgColor; ring.strokeColor = NSColor.systemBlue.cgColor; ring.lineWidth = 2; ring.opacity = 0
        layer?.addSublayer(ring)
        let sc = CABasicAnimation(keyPath: "transform.scale"); sc.fromValue = 0.3; sc.toValue = 2.4
        let fd = CABasicAnimation(keyPath: "opacity"); fd.fromValue = 0.9; fd.toValue = 0
        let g = CAAnimationGroup(); g.animations = [sc, fd]; g.duration = 0.45
        ring.add(g, forKey: "p")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ring.removeFromSuperlayer() }
    }
}

enum Step {
    case press(String), type(String, Character), menu(String, String)
    // Parse by prefix so colons inside an id (e.g. mapping.delete.hyper:72:n) survive.
    init?(_ s: String) {
        if s.hasPrefix("press:") { self = .press(String(s.dropFirst(6))); return }
        if s.hasPrefix("type:") {                       // type:<id>:<char>  (char = after last ':')
            let rest = String(s.dropFirst(5))
            guard let c = rest.lastIndex(of: ":") else { return nil }
            let ch = String(rest[rest.index(after: c)...])
            guard ch.count == 1 else { return nil }
            self = .type(String(rest[..<c]), Character(ch)); return
        }
        if s.hasPrefix("menu:") {                       // menu:<id>:<title>  (id = before first ':';
            // menu/picker ids must be colon-free — only press-target trigger ids contain colons)
            let rest = String(s.dropFirst(5))
            guard let c = rest.firstIndex(of: ":") else { return nil }
            self = .menu(String(rest[..<c]), String(rest[rest.index(after: c)...])); return
        }
        self = .press(s)                                // bare id => press
    }
}

final class Driver {
    let axApp: AXUIElement
    let pid: pid_t
    let steps: [Step]
    var i = 0
    let size = NSSize(width: 26, height: 30)
    var panel: NSPanel!

    init(pid: pid_t, steps: [Step]) { self.pid = pid; axApp = AXUIElementCreateApplication(pid); self.steps = steps }

    func makeOverlay() {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .screenSaver; p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = CursorView(frame: NSRect(origin: .zero, size: size)); v.wantsLayer = true
        p.contentView = v
        panel = p
    }

    func origin(forTipAtAX axPt: CGPoint) -> NSPoint {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        return NSPoint(x: axPt.x, y: (primary?.frame.maxY ?? 0) - axPt.y - size.height)
    }

    /// Glide the cursor to a target's center, pulse, then run `act`, then advance.
    func glide(to el: AXUIElement, label: String, act: @escaping () -> Void) {
        guard let fr = frameOf(el) else { print("  no frame for \(label)"); act(); after(0.4) { self.next() }; return }
        let tip = CGPoint(x: fr.midX, y: fr.midY)
        if !panel.isVisible { panel.setFrameOrigin(origin(forTipAtAX: tip)); panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.7; c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel.animator().setFrame(NSRect(origin: self.origin(forTipAtAX: tip), size: self.size), display: true)
        }, completionHandler: { [self] in
            (panel.contentView as? CursorView)?.pulse()
            act()
            after(0.7) { self.next() }
        })
    }

    func run() { makeOverlay(); next() }

    func next() {
        if i >= steps.count { print("DONE"); after(1.2) { NSApp.terminate(nil) }; return }
        let step = steps[i]; i += 1
        let n = i   // 1-based step number, captured for the closures' logs
        switch step {
        case .press(let id):
            guard let el = find(axApp, id) else { print("step \(n): NOT FOUND \(id)"); next(); return }
            glide(to: el, label: id) {
                let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
                print("step \(n): press \(id) => \(r == .success ? "OK" : "err \(r.rawValue)")")
            }
        case .type(let id, let ch):
            guard let el = find(axApp, id) else { print("step \(n): NOT FOUND \(id)"); next(); return }
            glide(to: el, label: id) { [self] in
                let focused = AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
                usleep(200_000)
                if !focused { print("step \(n): WARN couldn't focus \(id) — the key may land elsewhere") }
                if let kc = keyCodes[ch], let src = CGEventSource(stateID: .hidSystemState) {
                    CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: true)?.postToPid(pid)
                    usleep(30_000)
                    CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: false)?.postToPid(pid)
                    print("step \(n): type '\(ch)' into \(id) => sent\(focused ? "" : " (UNFOCUSED)")")
                } else { print("step \(n): type '\(ch)' => no keycode (a-z only)") }
            }
        case .menu(let id, let title):
            guard let el = find(axApp, id) else { print("step \(n): NOT FOUND \(id)"); next(); return }
            glide(to: el, label: id) { [self] in
                let opened = AXUIElementPerformAction(el, kAXPressAction as CFString) == .success   // open the menu
                usleep(450_000)
                // Scope the item search to the picker first (so a same-titled menu-bar
                // item elsewhere can't be hit); fall back to the whole app tree.
                let item = findByRoleTitle(el, role: kAXMenuItemRole as String, title: title)
                        ?? findByRoleTitle(axApp, role: kAXMenuItemRole as String, title: title)
                if let item = item {
                    let r = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    print("step \(n): menu \(id) -> '\(title)' => \(r == .success ? "OK" : "err \(r.rawValue)")")
                } else { print("step \(n): menu item '\(title)' NOT FOUND (picker opened: \(opened))") }
            }
        }
    }

    func after(_ s: TimeInterval, _ b: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: b) }
}

let raw = Array(CommandLine.arguments.dropFirst())
guard !raw.isEmpty else { FileHandle.standardError.write("usage: agentcursor <step>...\n".data(using: .utf8)!); exit(2) }
let steps: [Step] = raw.compactMap { s in
    guard let st = Step(s) else { FileHandle.standardError.write("agentcursor: skipping unparseable step '\(s)'\n".data(using: .utf8)!); return nil }
    return st
}
guard AXIsProcessTrusted() else { print("NOT TRUSTED — grant the host terminal Accessibility (System Settings ▸ Privacy ▸ Accessibility)"); exit(3) }
guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleIdentifier ?? "").contains("hypercapslock.debug") }) else { print("HyperCapslock-Dev not running"); exit(4) }

app.activate(options: [])   // bring app to front so synthesized keys reach the focused field
NSApplication.shared.setActivationPolicy(.accessory)
let driver = Driver(pid: app.processIdentifier, steps: steps)
DispatchQueue.main.async { driver.run() }
NSApplication.shared.run()
