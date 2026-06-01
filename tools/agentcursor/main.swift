import AppKit
import ApplicationServices

// agentcursor — a tiny computer-use engine for HyperCapslock.
//
// Usage:  agentcursor <ax-id> [<ax-id> ...]
//
// For each accessibility identifier, it: AX-finds the control in the running
// HyperCapslock(-Dev) app, glides an INDEPENDENT fake cursor to it (a transparent
// click-through overlay window — the real system mouse is never touched), then
// triggers it for real via the accessibility press action (AXPress). So an agent
// can script a series of real operations against the app's UI without hijacking
// the user's mouse. Build: `swiftc -O main.swift -o agentcursor`. Needs the host
// terminal to have Accessibility permission (inherited; no separate grant).

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
func frameOf(_ el: AXUIElement) -> CGRect? {
    // Verify the values are actually AXValues before casting (guard the force-cast).
    guard let pv = attr(el, kAXPositionAttribute as String), CFGetTypeID(pv) == AXValueGetTypeID(),
          let sv = attr(el, kAXSizeAttribute as String), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)   // top-left (global AX) coords
}

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

final class Driver {
    let axApp: AXUIElement
    let steps: [String]
    var i = 0
    let size = NSSize(width: 26, height: 30)
    var panel: NSPanel!

    init(pid: pid_t, steps: [String]) { axApp = AXUIElementCreateApplication(pid); self.steps = steps }

    func makeOverlay() {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .screenSaver; p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = CursorView(frame: NSRect(origin: .zero, size: size)); v.wantsLayer = true
        p.contentView = v
        panel = p
    }

    // AX top-left point -> bottom-left panel origin so the cursor TIP sits there.
    // AX coordinates flip around the PRIMARY (menu-bar) screen's maxY — that's the
    // screen at the global origin, NOT necessarily NSScreen.screens.first.
    func origin(forTipAtAX axPt: CGPoint) -> NSPoint {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        let primaryMaxY = primary?.frame.maxY ?? 0
        return NSPoint(x: axPt.x, y: primaryMaxY - axPt.y - size.height)
    }

    func run() { makeOverlay(); next() }

    func next() {
        if i >= steps.count { print("DONE"); DispatchQueue.main.asyncAfter(deadline: .now()+1.2) { NSApp.terminate(nil) }; return }
        let id = steps[i]; i += 1
        guard let el = find(axApp, id), let fr = frameOf(el) else {
            print("step \(i): NOT FOUND \(id)"); next(); return
        }
        let tip = CGPoint(x: fr.midX, y: fr.midY)
        if !panel.isVisible { panel.setFrameOrigin(origin(forTipAtAX: tip)); panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.9; c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: origin(forTipAtAX: tip), size: size), display: true)
        }, completionHandler: { [self] in
            (panel.contentView as? CursorView)?.pulse()
            let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
            print("step \(i): press \(id) @\(Int(fr.midX)),\(Int(fr.midY)) => \(r == .success ? "OK" : "err \(r.rawValue)")")
            DispatchQueue.main.asyncAfter(deadline: .now()+0.9) { self.next() }
        })
    }
}

let steps = Array(CommandLine.arguments.dropFirst())
guard !steps.isEmpty else { FileHandle.standardError.write("usage: agentcursor <ax-id>...\n".data(using: .utf8)!); exit(2) }
guard AXIsProcessTrusted() else { print("NOT TRUSTED — grant the host terminal Accessibility (System Settings ▸ Privacy ▸ Accessibility)"); exit(3) }
guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleIdentifier ?? "").contains("hypercapslock.debug") }) else { print("HyperCapslock-Dev not running"); exit(4) }

NSApplication.shared.setActivationPolicy(.accessory)
let driver = Driver(pid: app.processIdentifier, steps: steps)
DispatchQueue.main.async { driver.run() }
NSApplication.shared.run()
