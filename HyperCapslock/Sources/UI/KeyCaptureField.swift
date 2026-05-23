import SwiftUI
import AppKit

/// A click-to-focus field that captures a single physical key press and reports
/// it as a JavaScript keyCode (the storage format). Replaces the web "Press Key"
/// input. Pure modifier presses don't emit keyDown, so they're naturally ignored.
struct KeyCaptureField: NSViewRepresentable {
    @Binding var jsKeyCode: UInt16?
    var enabled: Bool = true
    var placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CaptureView {
        let v = CaptureView()
        v.onCapture = { mac in
            if let js = KeyCodes.macToJs(mac) { context.coordinator.parent.jsKeyCode = js }
        }
        return v
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        context.coordinator.parent = self
        view.enabled = enabled
        view.placeholder = placeholder
        view.displayText = jsKeyCode.map { keyCodeDisplay($0) } ?? ""
        view.needsDisplay = true
    }

    final class Coordinator {
        var parent: KeyCaptureField
        init(_ parent: KeyCaptureField) { self.parent = parent }
    }

    final class CaptureView: NSView {
        var onCapture: ((UInt16) -> Void)?
        var displayText = ""
        var placeholder = ""
        var enabled = true
        private var capturing = false

        override var acceptsFirstResponder: Bool { enabled }
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 34) }

        override func mouseDown(with event: NSEvent) {
            guard enabled else { return }
            window?.makeFirstResponder(self)
        }

        override func becomeFirstResponder() -> Bool {
            capturing = true; needsDisplay = true; return true
        }
        override func resignFirstResponder() -> Bool {
            capturing = false; needsDisplay = true; return true
        }

        override func keyDown(with event: NSEvent) {
            guard enabled else { return }
            onCapture?(event.keyCode)
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            (enabled ? NSColor.textBackgroundColor : NSColor.windowBackgroundColor).setFill()
            path.fill()
            (capturing ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = capturing ? 2 : 1
            path.stroke()

            let text = displayText.isEmpty ? (capturing ? "…" : placeholder) : displayText
            let color: NSColor = displayText.isEmpty ? .placeholderTextColor : .labelColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: enabled ? color : NSColor.disabledControlTextColor,
            ]
            let str = text as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
