import SwiftUI
import AppKit

// The "keyboard map" Mappings style: a full Apple Magic Keyboard where every key
// that carries a `Caps + key` mapping is highlighted in its action's category
// color. Click a mapped key to edit it; click an unmapped key to add a mapping
// for `Caps + that key`. A Base / +Shift layer toggle switches between the
// `Caps+key` and `Caps+Shift+key` layers; triggers that have no physical key
// (single/double-tap Caps, double-tap modifier) are listed below, reusing the
// exact same row as the grouped style.

// MARK: - Category color

/// Color used to highlight a mapped key, grouped by the action's nature. Matches
/// the palette from the design mockup (docs/design/mappings-mockups.html).
func actionCategoryColor(_ config: ActionConfig) -> Color {
    switch config {
    case .directional, .jump:
        return Color(red: 0.23, green: 0.61, blue: 1.00)      // navigation — blue
    case .independent(let a):
        switch a {
        case .toggleCapsLock, .noop, .switchInputSource:
            return Color(red: 0.54, green: 0.58, blue: 0.65)  // system — muted
        default:
            return Color(red: 0.96, green: 0.65, blue: 0.14)  // editing — amber
        }
    case .inputSource: return Color(red: 0.69, green: 0.49, blue: 1.00)  // purple
    case .keyCombo:     return Color(red: 0.96, green: 0.45, blue: 0.71)  // pink
    case .command:      return Color(red: 0.20, green: 0.83, blue: 0.60)  // green
    case .openApp:      return Color(red: 0.13, green: 0.83, blue: 0.93)  // cyan
    case .modifierKey:  return Color(red: 0.98, green: 0.44, blue: 0.52)  // rose
    }
}

// MARK: - Keycap glyph (what a mapped key shows on its cap)

/// What a mapped keycap draws in its center so the action reads at a glance.
/// Text glyphs reuse the HUD's symbol tables (`hudParts`, `modifierHudLabel`)
/// so a key looks the same on the keyboard as it does in the HUD when pressed.
enum KeycapGlyph: Equatable {
    /// A short symbol or label drawn as text (`←`, `⌥→`, `↑10`, `⌘⇧4`, `>_` …).
    case text(String)
    /// The app's own icon; `fallback` is drawn when the app isn't installed.
    case appIcon(bundleID: String, fallback: String)
    /// The input source's own icon; `fallback` is drawn when it has none.
    case inputSource(id: String, fallback: String)
}

/// Picks the keycap glyph for an action. Pure (no UI / registry lookups) so it
/// is unit-testable; the caller passes the localized Home/End labels and the
/// installed input source's display name (nil when it is not installed).
func keycapGlyph(for config: ActionConfig, homeLabel: String, endLabel: String,
                 inputSourceName: String?) -> KeycapGlyph {
    switch config {
    case .directional(.home): return .text(homeLabel)
    case .directional(.end):  return .text(endLabel)
    case .directional, .independent:
        return .text(hudParts(config).0)   // ← ↓ ↑ → ⌥← ⌥→ · ⌫ ↵ “” ⇪ ⊘
    case .jump(let dir, let count):
        return .text("\(dir == .up ? "↑" : "↓")\(count)")
    case .inputSource(let id):
        let fallback = inputSourceName.flatMap { $0.first.map(String.init) } ?? "⚠\u{FE0E}"
        return .inputSource(id: id, fallback: fallback)
    case .command:
        return .text(">_")
    case .keyCombo(let key, let ctrl, let alt, let cmd, let shift):
        return .text(compactComboString(key, ctrl: ctrl, alt: alt, cmd: cmd, shift: shift))
    case .openApp(let bid, let name):
        return .appIcon(bundleID: bid, fallback: name.first.map(String.init) ?? "App")
    case .modifierKey(let m):
        return .text(modifierHudLabel(m))   // ⌥R, ⌘L, fn …
    }
}

/// "⌘⇧4"-style combo in Apple's modifier order (⌃⌥⇧⌘), with the key itself as a
/// glyph where one exists, so it fits on a single keycap.
func compactComboString(_ key: UInt16, ctrl: Bool, alt: Bool, cmd: Bool, shift: Bool) -> String {
    let keyGlyphs: [UInt16: String] = [
        8: "⌫", 9: "⇥", 13: "↩", 27: "⎋", 32: "␣", 46: "⌦",
        33: "⇞", 34: "⇟", 35: "↘", 36: "↖",
    ]
    var s = ""
    if ctrl { s += "⌃" }; if alt { s += "⌥" }; if shift { s += "⇧" }; if cmd { s += "⌘" }
    return s + (keyGlyphs[key] ?? keyCodeDisplay(key))
}

/// App icons for keycaps, looked up once per bundle id — the keyboard re-renders
/// on every hover, and `NSWorkspace` lookups are not free.
@MainActor
private enum KeycapIconCache {
    static var apps: [String: NSImage?] = [:]
    static func app(_ bundleID: String) -> NSImage? {
        if let hit = apps[bundleID] { return hit }
        let icon = AppChooser.icon(bundleID)
        apps[bundleID] = icon
        return icon
    }
}

// MARK: - Style view

struct MappingsKeyboardStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    let onEdit: (ActionMappingEntry) -> Void
    let onAddTrigger: (Trigger) -> Void
    let onDelete: (ActionMappingEntry) -> Void
    /// triggerID → all-time press count; empty when inline counts are disabled.
    var usageTotals: [String: Int] = [:]
    @EnvironmentObject var loc: LocalizationManager

    @State private var layerShift = false

    /// Mappings for the active layer, indexed by their JS keycode.
    private var mappedByKeycode: [UInt16: ActionMappingEntry] {
        var m: [UInt16: ActionMappingEntry] = [:]
        for e in entries {
            if case .hyperPlusKey(let key, let withShift) = e.trigger, withShift == layerShift {
                m[key] = e
            }
        }
        return m
    }

    /// Triggers with no physical key — listed below the keyboard.
    private var specialEntries: [ActionMappingEntry] {
        entries.filter { if case .hyperPlusKey = $0.trigger { return false }; return true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Picker("", selection: $layerShift) {
                        Text(loc.t("mappings.group.caps_key")).tag(false)
                        Text(loc.t("mappings.group.caps_shift_key")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Text(loc.t("mappings.kb.hint"))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }

                MagicKeyboardView(layerShift: layerShift,
                                  mapped: mappedByKeycode,
                                  availableInputSources: availableInputSources,
                                  onEdit: onEdit, onAddTrigger: onAddTrigger)

                if !specialEntries.isEmpty { otherTriggers }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Triggers without a physical key. Reuses the grouped style's `MappingRow`
    /// inside an inset-grouped card so it reads identically to the grouped view.
    private var otherTriggers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("mappings.kb.other"))
                .font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(specialEntries.enumerated()), id: \.element.trigger) { idx, e in
                    if idx > 0 { Divider().padding(.leading, 14) }
                    MappingRow(entry: e, availableInputSources: availableInputSources,
                               keycapStyle: .raised,
                               usageCount: usageTotals[triggerUniqueID(e.trigger)],
                               onEdit: { onEdit(e) }, onDelete: { onDelete(e) })
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
}

// MARK: - The keyboard

private struct KbWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 720
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The currently hovered mapped key.
private struct HoverInfo: Equatable {
    let js: UInt16
    let entry: ActionMappingEntry
}

/// One physical key. `js` is the JS keycode it maps to (nil ⇒ not mappable, e.g.
/// a modifier). `role` drives appearance + interactivity. `units` is the key's
/// width in grid columns.
///
/// Deliberately NOT `Identifiable` with a `UUID`: the layout is rebuilt every
/// render, so a per-instance UUID would change each time and make `ForEach` treat
/// every key as new — tearing down and recreating all 64 keys (and their hover
/// tracking areas) on each hover, which spuriously re-fires `onHover` and loops
/// into a beachball. Keys are identified by their stable grid position instead.
private struct KKey {
    let label: String
    var js: UInt16? = nil
    var units: CGFloat = 1
    var role: Role = .normal
    enum Role { case normal, hyper, modifier }
}

private struct MagicKeyboardView: View {
    let layerShift: Bool
    let mapped: [UInt16: ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    let onEdit: (ActionMappingEntry) -> Void
    let onAddTrigger: (Trigger) -> Void
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.colorScheme) private var scheme

    @State private var width: CGFloat = 720
    @State private var hovered: HoverInfo?

    private let gap: CGFloat = 6
    private let bezelPad: CGFloat = 14
    private let rowUnits: CGFloat = 15   // EVERY row is exactly 15 columns wide

    /// Width of one grid column. Because every row sums to 15 columns and keys are
    /// laid out edge-to-edge on this grid (the visual gap is an inset *inside*
    /// each key, not extra spacing between them), all rows are exactly 15·colW
    /// wide — so every row's left and right edges line up, like a real keyboard.
    private var colW: CGFloat { min(max((width - bezelPad * 2) / rowUnits, 22), 54) }
    private var rowH: CGFloat { colW * 0.9 }
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in keyCell(key) }
                }
            }
            // Bottom row: the modifier/space keys plus the inverted-T arrow cluster.
            HStack(spacing: 0) {
                ForEach(Array(bottomRow.enumerated()), id: \.offset) { _, key in keyCell(key) }
                arrowCluster
            }
        }
        .padding(bezelPad)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dark ? Color(red: 0.06, green: 0.08, blue: 0.11) : Color(red: 0.80, green: 0.81, blue: 0.84))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.10)))
        )
        // Custom hover tooltip — instant + styled. Positioned from the known grid
        // geometry, so there are no anchor preferences / nested GeometryReaders
        // and therefore no layout feedback loop (which beach-balled the app).
        .overlay { tooltipOverlay }
        .fixedSize(horizontal: true, vertical: true)
        // center the keyboard when the pane is wider. minWidth 0 keeps this frame at
        // the pane's width even when the fixed-size keyboard is wider, so the width
        // measured below can shrink and the keyboard shrinks with it (without it the
        // keyboard never got narrower than 720 and pushed the sidebar to the left).
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(GeometryReader { g in Color.clear.preference(key: KbWidthKey.self, value: g.size.width) })
        .onPreferenceChange(KbWidthKey.self) { width = $0 }
    }

    @ViewBuilder private var tooltipOverlay: some View {
        if let h = hovered, let rect = keyRects[h.js] {
            keyTooltip(h.entry)
                .fixedSize()
                .position(tooltipPosition(rect))
                .allowsHitTesting(false)
        }
    }

    /// Analytic rect of each mappable key in the bezel's coordinate space (origin
    /// at the bezel top-left, i.e. including the bezel padding). Lets the hover
    /// tooltip position itself with zero preference/anchor machinery.
    private var keyRects: [UInt16: CGRect] {
        var out: [UInt16: CGRect] = [:]
        func place(_ keys: [KKey], row: Int) {
            var off: CGFloat = 0
            for key in keys {
                if key.role == .normal, let js = key.js {
                    out[js] = CGRect(x: bezelPad + off * colW, y: bezelPad + CGFloat(row) * rowH,
                                     width: key.units * colW, height: rowH)
                }
                off += key.units
            }
        }
        for (i, row) in rows.enumerated() { place(row, row: i) }
        // Bottom row: modifier/space keys, then the inverted-T arrow cluster.
        let r = rows.count
        place(bottomRow, row: r)
        let bottomUnits = bottomRow.reduce(0) { $0 + $1.units }
        let y = bezelPad + CGFloat(r) * rowH
        out[37] = CGRect(x: bezelPad + bottomUnits * colW, y: y, width: colW, height: rowH)              // ←
        let colX = bezelPad + (bottomUnits + 1) * colW
        out[38] = CGRect(x: colX, y: y, width: colW, height: rowH / 2)                                   // ↑
        out[40] = CGRect(x: colX, y: y + rowH / 2, width: colW, height: rowH / 2)                        // ↓
        out[39] = CGRect(x: bezelPad + (bottomUnits + 2) * colW, y: y, width: colW, height: rowH)        // →
        return out
    }

    // MARK: rows

    private var rows: [[KKey]] {
        [
            // Function row
            [KKey(label: "esc", js: 27, units: 1.5),
             k("F1", 112), k("F2", 113), k("F3", 114), k("F4", 115), k("F5", 116), k("F6", 117),
             k("F7", 118), k("F8", 119), k("F9", 120), k("F10", 121), k("F11", 122), k("F12", 123),
             KKey(label: "⏻", units: 1.5, role: .modifier)],
            // Number row
            [k("`", 192), k("1", 49), k("2", 50), k("3", 51), k("4", 52), k("5", 53), k("6", 54),
             k("7", 55), k("8", 56), k("9", 57), k("0", 48), k("-", 189), k("=", 187),
             KKey(label: "⌫", js: 8, units: 2)],
            // Tab row
            [KKey(label: "⇥", js: 9, units: 1.5),
             k("Q", 81), k("W", 87), k("E", 69), k("R", 82), k("T", 84), k("Y", 89), k("U", 85),
             k("I", 73), k("O", 79), k("P", 80), k("[", 219), k("]", 221),
             KKey(label: "\\", js: 220, units: 1.5)],
            // Caps row
            [KKey(label: "caps", units: 1.75, role: .hyper),
             k("A", 65), k("S", 83), k("D", 68), k("F", 70), k("G", 71), k("H", 72), k("J", 74),
             k("K", 75), k("L", 76), k(";", 186), k("'", 222),
             KKey(label: "return", js: 13, units: 2.25)],
            // Shift row
            [KKey(label: "⇧", units: 2.25, role: .modifier),
             k("Z", 90), k("X", 88), k("C", 67), k("V", 86), k("B", 66), k("N", 78), k("M", 77),
             k(",", 188), k(".", 190), k("/", 191),
             KKey(label: "⇧", units: 2.75, role: .modifier)],
        ]
    }

    /// The bottom row up to the arrow cluster (which is rendered specially).
    private var bottomRow: [KKey] {
        [KKey(label: "fn", units: 1, role: .modifier),
         KKey(label: "⌃", units: 1, role: .modifier),
         KKey(label: "⌥", units: 1, role: .modifier),
         KKey(label: "⌘", units: 1.25, role: .modifier),
         KKey(label: "", js: 32, units: 5.5),            // space (mappable)
         KKey(label: "⌘", units: 1.25, role: .modifier),
         KKey(label: "⌥", units: 1, role: .modifier)]
    }

    private func k(_ label: String, _ js: UInt16) -> KKey { KKey(label: label, js: js) }

    // MARK: cells

    /// A full-height key cell occupying `units` grid columns.
    private func keyCell(_ key: KKey) -> some View {
        let info = mapInfo(key)
        return cap(for: key, info: info)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(gap / 2)
            .frame(width: key.units * colW, height: rowH)
            .contentShape(Rectangle())
            .onTapGesture { tap(key, info) }
            .onHover { updateHover(key, info, $0) }
    }

    private struct MapInfo { var entry: ActionMappingEntry?; var cfg: ActionConfig? }

    private func mapInfo(_ key: KKey) -> MapInfo {
        guard key.role == .normal, let js = key.js, let entry = mapped[js] else { return MapInfo() }
        // Tint by the action the key is *represented* by — for a noop-default key
        // that's its first real per-app action — so the keycap color matches the
        // hover tooltip / list / stats pill (see `representativeActionRef`).
        let ref = representativeActionRef(entry)
        return MapInfo(entry: entry, cfg: ActionsRegistry.shared.resolve(actionId: ref.actionId, inline: ref.inline))
    }

    private func tap(_ key: KKey, _ info: MapInfo) {
        if let entry = info.entry { onEdit(entry) }
        else if key.role == .normal, let js = key.js {
            onAddTrigger(.hyperPlusKey(key: js, withShift: layerShift))
        }
    }

    /// Set/clear the hovered key. Clearing only when *this* key is the current
    /// one makes key→key moves reliable regardless of enter/exit event order.
    private func updateHover(_ key: KKey, _ info: MapInfo, _ hovering: Bool) {
        guard key.role == .normal, let js = key.js, let entry = info.entry else { return }
        if hovering { hovered = HoverInfo(js: js, entry: entry) }
        else if hovered?.js == js { hovered = nil }
    }


    // The inverted-T arrow cluster: ← (full height) · ↑/↓ stacked · → (full height).
    private var arrowCluster: some View {
        HStack(spacing: 0) {
            keyCell(k("←", 37))
            VStack(spacing: 0) {
                arrowCap(k("↑", 38))
                arrowCap(k("↓", 40))
            }
            .frame(width: colW, height: rowH)
            keyCell(k("→", 39))
        }
    }

    private func arrowCap(_ key: KKey) -> some View {
        let info = mapInfo(key)
        return cap(for: key, info: info, compact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(gap / 2)
            .contentShape(Rectangle())
            .onTapGesture { tap(key, info) }
            .onHover { updateHover(key, info, $0) }
    }

    // MARK: hover tooltip

    /// Custom tooltip card shown over a hovered mapped key: trigger → action.
    /// The action sits in its own category-tinted pill so it reads as a distinct
    /// unit and doesn't visually merge with the connector arrow.
    private func keyTooltip(_ entry: ActionMappingEntry) -> some View {
        let d = mappingActionDisplay(entry, loc, availableInputSources: availableInputSources)
        return HStack(spacing: 9) {
            TriggerChips(trigger: entry.trigger, style: .raised)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            ActionPill(display: d, accent: actionAccent(entry, invalid: d.invalid))
            if !entry.bindings.isEmpty {
                HStack(spacing: 2) { Image(systemName: "macwindow"); Text("\(entry.bindings.count)") }
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 11, y: 5)
        .fixedSize()
    }

    /// Center the tooltip above the key, flipping below when the key is near the
    /// top, and keep it horizontally inside the keyboard.
    private func tooltipPosition(_ rect: CGRect) -> CGPoint {
        let estH: CGFloat = 44, halfW: CGFloat = 130
        let bezelWidth = rowUnits * colW + bezelPad * 2
        let y = rect.minY > estH + 14 ? rect.minY - estH / 2 - 8 : rect.maxY + estH / 2 + 8
        let lo = halfW + 4, hi = max(lo, bezelWidth - halfW - 4)
        return CGPoint(x: min(max(rect.midX, lo), hi), y: y)
    }

    // MARK: cap visual

    @ViewBuilder
    private func cap(for key: KKey, info: MapInfo, compact: Bool = false) -> some View {
        let hyper = key.role == .hyper
        let tint: Color? = hyper ? Color(red: 0.05, green: 0.52, blue: 1.0)
                                 : info.entry.map { _ in info.cfg.map(actionCategoryColor) ?? .orange }
        let labelText = hyper ? "caps" : key.label
        let radius = max(5, colW * 0.16)
        // A mapped key shows what it does; its own legend moves small into the corner.
        let glyph: KeycapGlyph? = info.entry == nil ? nil : glyphFor(info)

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(capFill(tint: tint, hyper: hyper))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(capStroke(tint: tint, hyper: hyper), lineWidth: 1))
                .shadow(color: hyper ? Color(red: 0.05, green: 0.52, blue: 1.0).opacity(0.45)
                                     : .black.opacity(dark ? 0.30 : 0.10),
                        radius: hyper ? 7 : 1, y: hyper ? 0 : 1)

            if let glyph {
                glyphView(glyph, color: capText(tint: tint, hyper: false), compact: compact)
                    .offset(y: compact ? 0 : colW * 0.04)
                // The key's own legend, small in the top-left corner. Half-height
                // arrow keys have no room for it — their position identifies them.
                if !compact && !labelText.isEmpty {
                    Text(labelText)
                        .font(.system(size: min(10, max(7, colW * 0.2)), weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(capText(tint: tint, hyper: false).opacity(0.6))
                        .padding(.leading, max(3, colW * 0.09)).padding(.top, max(1.5, colW * 0.04))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                // Tiny dot: this key also has per-app rules (the glyph is its default).
                if let entry = info.entry, !entry.bindings.isEmpty {
                    Circle().fill(capText(tint: tint, hyper: false).opacity(0.55))
                        .frame(width: compact ? 3 : 4, height: compact ? 3 : 4)
                        .padding(.trailing, compact ? 3 : 5).padding(.top, compact ? 2.5 : 4.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            } else {
                VStack(spacing: 1) {
                    Text(labelText)
                        .font(.system(size: min(13, colW * 0.34), weight: .semibold,
                                      design: labelText.count <= 2 ? .default : .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(capText(tint: tint, hyper: hyper))
                    if hyper {
                        Text("HYPER").font(.system(size: max(6, colW * 0.17), weight: .heavy))
                            .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                    }
                }
                .padding(.horizontal, 3)
            }

            if info.entry != nil, let tint {
                VStack { Spacer()
                    RoundedRectangle(cornerRadius: 2).fill(tint)
                        .frame(height: 2.5).padding(.horizontal, 5).padding(.bottom, 3)
                }
            }
        }
        .opacity(key.role == .modifier ? 0.72 : 1)
    }

    // MARK: keycap glyph

    /// The glyph for a mapped key's represented action (same action that sets the
    /// tint — see `mapInfo`); a warning sign when that action no longer resolves.
    private func glyphFor(_ info: MapInfo) -> KeycapGlyph {
        guard let cfg = info.cfg else { return .text("⚠\u{FE0E}") }
        var sourceName: String? = nil
        if case .inputSource(let id) = cfg { sourceName = availableInputSources[id]?.name }
        return keycapGlyph(for: cfg,
                           homeLabel: loc.t("mappings.kb.glyph.home"),
                           endLabel: loc.t("mappings.kb.glyph.end"),
                           inputSourceName: sourceName)
    }

    @ViewBuilder
    private func glyphView(_ glyph: KeycapGlyph, color: Color, compact: Bool) -> some View {
        switch glyph {
        case .text(let s):
            glyphText(s, color: color, compact: compact)
        case .appIcon(let bid, let fallback):
            if let icon = KeycapIconCache.app(bid) {
                glyphImage(icon, color: color, compact: compact)
            } else {
                glyphText(fallback, color: color, compact: compact)
            }
        case .inputSource(let id, let fallback):
            if let icon = availableInputSources[id]?.icon {
                glyphImage(icon, color: color, compact: compact)
            } else {
                glyphText(fallback, color: color, compact: compact)
            }
        }
    }

    /// Text glyph, sized by length so `←` reads big while `⌃⌥⇧⌘K` still fits;
    /// anything longer shrinks (down to 45%) rather than wrapping.
    private func glyphText(_ s: String, color: Color, compact: Bool) -> some View {
        let size: CGFloat
        if compact { size = min(10, colW * 0.25) }
        else if s.count <= 1 { size = min(17, colW * 0.42) }
        else if s.count == 2 { size = min(14, colW * 0.34) }
        else { size = min(12, colW * 0.28) }
        return Text(s)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.45).allowsTightening(true)
            .foregroundStyle(color)
            .padding(.horizontal, max(2, colW * 0.07))
    }

    /// Icon glyph (app icon / input source icon). Template images (most input
    /// source icons) take the cap's text color so they read in light and dark.
    @ViewBuilder
    private func glyphImage(_ image: NSImage, color: Color, compact: Bool) -> some View {
        let side = compact ? max(8, (rowH / 2 - gap) * 0.9) : max(12, (rowH - gap) * 0.58)
        if image.isTemplate {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
                .scaledToFit().frame(width: side, height: side).foregroundStyle(color)
        } else {
            Image(nsImage: image).resizable().interpolation(.high)
                .scaledToFit().frame(width: side, height: side)
        }
    }

    // MARK: cap styling

    private func capFill(tint: Color?, hyper: Bool) -> LinearGradient {
        if hyper {
            return LinearGradient(colors: [Color(red: 0.12, green: 0.31, blue: 0.53), Color(red: 0.08, green: 0.19, blue: 0.31)],
                                  startPoint: .top, endPoint: .bottom)
        }
        if let tint {
            let top = blend(tint, dark ? 0.30 : 0.26)
            let bot = blend(tint, dark ? 0.16 : 0.12)
            return LinearGradient(colors: [top, bot], startPoint: .top, endPoint: .bottom)
        }
        return dark
            ? LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.24), Color(red: 0.105, green: 0.13, blue: 0.17)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white, Color(red: 0.92, green: 0.93, blue: 0.94)], startPoint: .top, endPoint: .bottom)
    }

    private func blend(_ tint: Color, _ amount: Double) -> Color {
        let base = dark ? Color(red: 0.14, green: 0.17, blue: 0.22) : Color(red: 0.95, green: 0.96, blue: 0.97)
        return base.overlayBlend(tint, amount)
    }

    private func capStroke(tint: Color?, hyper: Bool) -> Color {
        if hyper { return Color(red: 0.05, green: 0.52, blue: 1.0).opacity(0.55) }
        if let tint { return tint.opacity(dark ? 0.45 : 0.40) }
        return dark ? Color.white.opacity(0.08) : Color.black.opacity(0.12)
    }

    private func capText(tint: Color?, hyper: Bool) -> Color {
        if hyper { return .white }
        if tint != nil { return dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14) }
        return dark ? Color(red: 0.67, green: 0.71, blue: 0.77) : Color(red: 0.25, green: 0.26, blue: 0.29)
    }
}

private extension Color {
    /// Cheap manual blend toward `other` by `amount` (0…1) in sRGB. Avoids
    /// `Color.mix` (macOS 15+) so it works on macOS 14.
    func overlayBlend(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x * (1 - amount) + y * amount }
        return Color(red: Double(mix(a.redComponent, b.redComponent)),
                     green: Double(mix(a.greenComponent, b.greenComponent)),
                     blue: Double(mix(a.blueComponent, b.blueComponent)))
    }
}
