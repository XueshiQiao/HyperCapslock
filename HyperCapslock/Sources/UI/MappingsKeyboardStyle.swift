import SwiftUI
import AppKit

// The "keyboard map" Mappings style: a full Apple Magic Keyboard where every key
// that carries a `Caps + key` mapping is highlighted in its action's category
// color. Click a mapped key to edit it; click an unmapped key to add a mapping
// for `Caps + that key`. A Base / +Shift layer toggle switches between the
// `Caps+key` and `Caps+Shift+key` layers; triggers that have no physical key
// (single/double-tap Caps, double-tap modifier) live in a strip below.

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

// MARK: - Style view

struct MappingsKeyboardStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    let onEdit: (ActionMappingEntry) -> Void
    let onAddTrigger: (Trigger) -> Void
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

    /// Triggers with no physical key — shown as chips under the keyboard.
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

                if !specialEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.t("mappings.kb.other"))
                            .font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                        FlowChips(entries: specialEntries, availableInputSources: availableInputSources, onEdit: onEdit)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Special-trigger chips

private struct FlowChips: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    let onEdit: (ActionMappingEntry) -> Void
    @EnvironmentObject var loc: LocalizationManager

    private let cols = [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 10, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            ForEach(entries, id: \.trigger) { e in
                let d = mappingActionDisplay(e, loc, availableInputSources: availableInputSources)
                Button { onEdit(e) } label: {
                    HStack(spacing: 8) {
                        TriggerChips(trigger: e.trigger, style: .raised)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        if let icon = d.icon {
                            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                        } else {
                            Image(systemName: d.symbol).foregroundStyle(d.invalid ? .orange : .secondary)
                        }
                        Text(d.text).foregroundStyle(d.invalid ? .orange : .primary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - The keyboard

private struct KbWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 640
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// One physical key. `js` is the JS keycode it maps to (nil ⇒ not mappable, e.g.
/// a modifier). `role` drives appearance + interactivity.
private struct KKey: Identifiable {
    let id = UUID()
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

    @State private var width: CGFloat = 640
    private let gap: CGFloat = 5
    private let rowUnits: CGFloat = 15   // every row sums to 15 units wide

    /// Size a unit so the widest row fits the measured width. The widest rows
    /// have 14 keys ⇒ 13 inter-key gaps, and the keyboard has 13pt inner padding
    /// on each side. Key widths are then a clean `units * unit` (gaps come purely
    /// from the HStack spacing), so rows fit instead of overflowing.
    private var unit: CGFloat {
        let u = (width - 26 - 13 * gap) / rowUnits
        return min(max(u, 18), 46)
    }
    private var keyH: CGFloat { unit * 0.94 }
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) { ForEach(row) { keyView($0) } }
            }
            bottomRow
        }
        .frame(maxWidth: .infinity)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dark ? Color(red: 0.06, green: 0.08, blue: 0.11) : Color(red: 0.82, green: 0.83, blue: 0.85))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.10)))
        )
        .background(GeometryReader { g in Color.clear.preference(key: KbWidthKey.self, value: g.size.width) })
        .onPreferenceChange(KbWidthKey.self) { width = $0 }
    }

    // MARK: rows

    private var rows: [[KKey]] {
        [
            // Function row
            [KKey(label: "esc", js: 27, units: 1.5),
             fk("F1", 112), fk("F2", 113), fk("F3", 114), fk("F4", 115), fk("F5", 116), fk("F6", 117),
             fk("F7", 118), fk("F8", 119), fk("F9", 120), fk("F10", 121), fk("F11", 122), fk("F12", 123),
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

    private func k(_ label: String, _ js: UInt16) -> KKey { KKey(label: label, js: js) }
    private func fk(_ label: String, _ js: UInt16) -> KKey { KKey(label: label, js: js, units: 1) }

    // Bottom row needs the inverted-T arrow cluster, so it's built by hand.
    private var bottomRow: some View {
        HStack(spacing: gap) {
            keyView(KKey(label: "fn", units: 1, role: .modifier))
            keyView(KKey(label: "⌃", units: 1, role: .modifier))
            keyView(KKey(label: "⌥", units: 1, role: .modifier))
            keyView(KKey(label: "⌘", units: 1.25, role: .modifier))
            keyView(KKey(label: "", js: 32, units: 5.5))             // space (mappable)
            keyView(KKey(label: "⌘", units: 1.25, role: .modifier))
            keyView(KKey(label: "⌥", units: 1, role: .modifier))
            arrowCluster
        }
    }

    private var arrowCluster: some View {
        let half = (keyH - gap) / 2
        return HStack(spacing: gap) {
            keyView(KKey(label: "←", js: 37))
            VStack(spacing: gap) {
                keyCap(KKey(label: "↑", js: 38), height: half)
                keyCap(KKey(label: "↓", js: 40), height: half)
            }
            .frame(width: unit)
            keyView(KKey(label: "→", js: 39))
        }
    }

    // MARK: key view

    private func keyView(_ key: KKey) -> some View {
        keyCap(key, height: keyH)
    }

    @ViewBuilder
    private func keyCap(_ key: KKey, height: CGFloat) -> some View {
        let entry = key.role == .normal ? key.js.flatMap { mapped[$0] } : nil
        let cfg = entry.flatMap { ActionsRegistry.shared.resolve($0) }
        let tint: Color? = key.role == .hyper ? Color(red: 0.05, green: 0.52, blue: 1.0)
                                              : entry.map { _ in cfg.map(actionCategoryColor) ?? .orange }
        let labelText = key.role == .hyper ? "caps" : key.label

        ZStack {
            RoundedRectangle(cornerRadius: max(5, unit * 0.16), style: .continuous)
                .fill(capFill(tint: tint, hyper: key.role == .hyper))
                .overlay(
                    RoundedRectangle(cornerRadius: max(5, unit * 0.16), style: .continuous)
                        .strokeBorder(capStroke(tint: tint, hyper: key.role == .hyper), lineWidth: 1))
                .shadow(color: (key.role == .hyper ? Color(red: 0.05, green: 0.52, blue: 1.0).opacity(0.45)
                                                   : .black.opacity(dark ? 0.32 : 0.12)),
                        radius: key.role == .hyper ? 7 : 1.2, y: key.role == .hyper ? 0 : 1)

            VStack(spacing: 1) {
                Text(labelText)
                    .font(.system(size: min(13, unit * 0.36), weight: .semibold, design: labelText.count <= 2 ? .default : .rounded))
                    .foregroundStyle(capText(tint: tint, hyper: key.role == .hyper))
                if key.role == .hyper {
                    Text("HYPER").font(.system(size: max(6, unit * 0.18), weight: .heavy))
                        .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                }
            }
            .padding(.horizontal, 3)

            // bottom accent bar for mapped keys
            if entry != nil, let tint {
                VStack { Spacer()
                    RoundedRectangle(cornerRadius: 2).fill(tint)
                        .frame(height: 2.5).padding(.horizontal, 5).padding(.bottom, 3)
                }
            }
        }
        .frame(width: key.units * unit, height: height)
        .opacity(key.role == .modifier ? 0.72 : 1)
        .contentShape(Rectangle())
        .help(entry.map { mappingActionDisplay($0, loc, availableInputSources: availableInputSources).text } ?? "")
        .onTapGesture {
            if let entry { onEdit(entry) }
            else if key.role == .normal, let js = key.js {
                onAddTrigger(.hyperPlusKey(key: js, withShift: layerShift))
            }
        }
    }

    // MARK: cap styling

    private func capFill(tint: Color?, hyper: Bool) -> LinearGradient {
        if hyper {
            return LinearGradient(colors: [Color(red: 0.12, green: 0.31, blue: 0.53), Color(red: 0.08, green: 0.19, blue: 0.31)],
                                  startPoint: .top, endPoint: .bottom)
        }
        if let tint {
            // mapped: tinted cap
            let top = blend(tint, dark ? 0.30 : 0.26)
            let bot = blend(tint, dark ? 0.16 : 0.12)
            return LinearGradient(colors: [top, bot], startPoint: .top, endPoint: .bottom)
        }
        // plain cap
        return dark
            ? LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.24), Color(red: 0.105, green: 0.13, blue: 0.17)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white, Color(red: 0.92, green: 0.93, blue: 0.94)], startPoint: .top, endPoint: .bottom)
    }

    /// Blend a tint over the plain-cap base so mapped keys read as colored keys
    /// rather than flat swatches.
    private func blend(_ tint: Color, _ amount: Double) -> Color {
        let base = dark ? Color(red: 0.14, green: 0.17, blue: 0.22) : Color(red: 0.95, green: 0.96, blue: 0.97)
        return base.opacity(1).overlayBlend(tint, amount)
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
