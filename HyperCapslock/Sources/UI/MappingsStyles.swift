import SwiftUI
import AppKit

// The Mappings page can render in several visual styles (see `MappingsViewStyle`).
// This file holds the per-style sub-views plus the shared row/trigger components
// they reuse, so adding a new style is just: a new enum case + a new sub-view.
// `MappingsPage` (in MappingsCard.swift) owns the toolbar/sheet/state and simply
// dispatches to the style selected in `AppConfig.mappingsViewStyle`.

// MARK: - Keycaps

/// Which keycap look the trigger chips use. `.raised` is the neutral 3D physical
/// keycap (used by the keyboard view); `.glass` is the colorful frosted keycap the
/// grouped list uses.
enum KeycapStyle { case raised, glass }

/// Renders one keycap chip. `modifier` marks the Caps / Shift keycap so it can read
/// as a distinct (cooler) color from the actual key.
@ViewBuilder func keycapView(_ text: String, _ style: KeycapStyle, modifier: Bool = false) -> some View {
    switch style {
    case .raised: Keycap(text)
    case .glass:  GlassCap(text, modifier: modifier)
    }
}

/// Frosted-glass keycap for the grouped list's trigger chips.
///
/// - The *key* gets the colorful blue→violet frosted look (a real
///   `.ultraThinMaterial` blur).
/// - A *modifier* (Caps / Shift) gets a cooler slate tint with NO material — so it
///   reads as a clearly different color AND a row composites at most one backdrop
///   blur instead of two (lighter to draw while scrolling / dragging the window).
///
/// No drop shadow: one chip per key plus a pill per row made the cumulative
/// offscreen shadow passes a measurable cost; the light border carries the edge.
struct GlassCap: View {
    let text: String
    let modifier: Bool
    init(_ text: String, modifier: Bool = false) { self.text = text; self.modifier = modifier }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(textColor(dark))
            .padding(.horizontal, 9).frame(minWidth: 29, minHeight: 27)
            .background(fill(dark))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.4 : 0.85), .white.opacity(0.1)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func textColor(_ dark: Bool) -> Color {
        if modifier { return dark ? Color(red: 0.90, green: 0.93, blue: 1.0) : Color(red: 0.20, green: 0.30, blue: 0.60) }
        return dark ? Color(red: 0.93, green: 0.95, blue: 1.0) : Color(red: 0.24, green: 0.26, blue: 0.46)
    }

    @ViewBuilder private func fill(_ dark: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if modifier {
            // Bright periwinkle (no backdrop blur) — still distinct from the frosted
            // key, but lively rather than gray.
            shape.fill(LinearGradient(
                colors: dark ? [Color(red: 0.36, green: 0.43, blue: 0.64), Color(red: 0.27, green: 0.33, blue: 0.52)]
                             : [Color(red: 0.82, green: 0.89, blue: 1.0), Color(red: 0.66, green: 0.77, blue: 1.0)],
                startPoint: .top, endPoint: .bottom))
        } else {
            // Colorful frosted glass (the look kept from the chosen style).
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(LinearGradient(
                    colors: [Color(red: 0.42, green: 0.58, blue: 1.0).opacity(dark ? 0.42 : 0.30),
                             Color(red: 0.66, green: 0.46, blue: 1.0).opacity(dark ? 0.32 : 0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }
}

/// A raised, physical-looking keycap — ported from the design mockup
/// (`docs/design/mappings-mockups.html`). Adapts to light/dark so it reads as a
/// real key in either appearance (light-gray cap in light mode, graphite in dark).
struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(dark ? Color(red: 0.89, green: 0.91, blue: 0.95)
                                  : Color(red: 0.13, green: 0.13, blue: 0.15))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 25)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(
                        colors: dark ? [Color(red: 0.20, green: 0.24, blue: 0.30), Color(red: 0.115, green: 0.145, blue: 0.19)]
                                     : [Color.white, Color(red: 0.90, green: 0.91, blue: 0.93)],
                        startPoint: .top, endPoint: .bottom)))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: dark ? [Color.white.opacity(0.16), Color.black.opacity(0.55)]
                                     : [Color.white, Color.black.opacity(0.20)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.35 : 0.16), radius: 1.2, y: 1)
    }
}

// MARK: - Shared trigger chips

/// The trigger rendered as keycap chips (`Caps + H`, `Caps ×2`, `⌘ ×2`, …).
/// Shared by every style so a trigger reads the same everywhere.
struct TriggerChips: View {
    let trigger: Trigger
    var style: KeycapStyle = .raised

    var body: some View {
        HStack(spacing: 5) {
            switch trigger {
            case .singleTapHyper:
                cap("Caps", modifier: true); times; cap("1")
            case .doubleTapHyper:
                cap("Caps", modifier: true); times; cap("2")
            case .doubleTapModifier(let m):
                cap(modifierGlyph(m), modifier: true); times; cap("2")
            case .hyperPlusKey(let key, let withShift):
                cap("Caps", modifier: true); plus
                if withShift { cap("Shift", modifier: true); plus }
                cap(keyCodeDisplay(key))
            }
        }
    }

    @ViewBuilder private func cap(_ t: String, modifier: Bool = false) -> some View {
        keycapView(t, style, modifier: modifier)
    }
    private var plus: some View { Text("+").foregroundColor(.secondary).font(.caption) }
    private var times: some View { Text("×").foregroundColor(.secondary).font(.caption) }
}

// MARK: - Trigger categories (for the grouped style)

/// Buckets a trigger into one of the grouped-style sections. Declaration order
/// is section order.
enum TriggerCategory: CaseIterable {
    case capsKey, capsShiftKey, singleTap, doubleTap, doubleTapModifier

    var nameKey: String {
        switch self {
        case .capsKey:           return "mappings.group.caps_key"
        case .capsShiftKey:      return "mappings.group.caps_shift_key"
        case .singleTap:         return "mappings.group.single_tap"
        case .doubleTap:         return "mappings.group.double_tap"
        case .doubleTapModifier: return "mappings.group.double_tap_modifier"
        }
    }
}

func triggerCategory(_ t: Trigger) -> TriggerCategory {
    switch t {
    case .hyperPlusKey(_, let withShift): return withShift ? .capsShiftKey : .capsKey
    case .singleTapHyper:                 return .singleTap
    case .doubleTapHyper:                 return .doubleTap
    case .doubleTapModifier:              return .doubleTapModifier
    }
}

// MARK: - Action pill

/// The action half of a row / tooltip: the action icon in its category color +
/// label, inside a faint category-tinted capsule so it reads as one distinct
/// unit. Shared by the grouped rows, the keyboard's Other Triggers, and the
/// keyboard hover tooltip.
struct ActionPill: View {
    let display: ActionDisplay
    let accent: Color

    var body: some View {
        let tint = display.invalid ? Color.orange : accent
        return HStack(spacing: 6) {
            if let icon = display.icon {
                Image(nsImage: icon).resizable().frame(width: 15, height: 15)
            } else {
                Image(systemName: display.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            Text(display.text).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
            Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
    }
}

/// Category accent color for a mapping's resolved action; orange when the action
/// is unresolved/invalid.
func actionAccent(_ entry: ActionMappingEntry, invalid: Bool) -> Color {
    invalid ? .orange : (ActionsRegistry.shared.resolve(entry).map(actionCategoryColor) ?? .secondary)
}

// MARK: - Shared mapping row

/// One mapping row: trigger chips on the left, the resolved action on the right,
/// the per-app-rules badge, and hover edit/delete. Designed to live inside a
/// `Form` (used by both the list and grouped styles).
struct MappingRow: View {
    let entry: ActionMappingEntry
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    var keycapStyle: KeycapStyle = .raised
    /// All-time press count, shown as a subtle inline badge when non-nil and > 0
    /// (gated by the `stats_show_inline` setting at the call site).
    var usageCount: Int? = nil
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        let d = mappingActionDisplay(entry, loc, availableInputSources: availableInputSources)
        let bindingsInvalid = entry.bindings.contains { ActionsRegistry.shared.resolve($0) == nil }
        // Explicit HStack (not LabeledContent) so the trigger sits left and the
        // action sits right in EVERY context — LabeledContent only spreads that
        // way inside a Form; elsewhere (e.g. the keyboard style's Other Triggers)
        // it would center.
        return HStack(spacing: 8) {
            TriggerChips(trigger: entry.trigger, style: keycapStyle)
            Spacer(minLength: 12)
            ActionPill(display: d, accent: actionAccent(entry, invalid: d.invalid))
            if let n = usageCount, n > 0 {
                UsageCountBadge(count: n)
                    .help(loc.t("stats.inline_help"))
                    .accessibilityIdentifier("mapping.usage.\(triggerUniqueID(entry.trigger))")
            }
            if !entry.bindings.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: bindingsInvalid ? "exclamationmark.triangle.fill" : "macwindow")
                    Text("\(entry.bindings.count)")
                }
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill((bindingsInvalid ? Color.orange : Color.accentColor).opacity(0.15)))
                .foregroundStyle(bindingsInvalid ? Color.orange : Color.accentColor)
                .help(bindingsInvalid ? loc.t("mappings.invalid") : loc.t("mappings.app_rules"))
            }
            Button(action: onEdit) { Image(systemName: "pencil") }.buttonStyle(.borderless)
                .accessibilityIdentifier("mapping.edit.\(triggerUniqueID(entry.trigger))")
            Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
                .accessibilityIdentifier("mapping.delete.\(triggerUniqueID(entry.trigger))")
        }
        // Fill the row width so the Spacer actually spreads trigger-left /
        // action-right — needed outside a Form (Form rows already get full width).
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

// MARK: - Style: Grouped by trigger

struct MappingsGroupedStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    var keycapStyle: KeycapStyle = .glass
    /// triggerID → all-time press count; empty when inline counts are disabled.
    var usageTotals: [String: Int] = [:]
    let onEdit: (ActionMappingEntry) -> Void
    let onDelete: (ActionMappingEntry) -> Void
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Form {
            if entries.isEmpty {
                Section { Text(loc.t("mappings.empty")).foregroundStyle(.secondary) }
            } else {
                // `entries` arrives pre-sorted by triggerSortKey; filtering per
                // category preserves that order. Empty categories are skipped.
                ForEach(TriggerCategory.allCases, id: \.self) { category in
                    let items = entries.filter { triggerCategory($0.trigger) == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.trigger) { entry in
                                MappingRow(entry: entry, availableInputSources: availableInputSources,
                                           keycapStyle: keycapStyle,
                                           usageCount: usageTotals[triggerUniqueID(entry.trigger)],
                                           onEdit: { onEdit(entry) }, onDelete: { onDelete(entry) })
                            }
                        } header: {
                            HStack(spacing: 7) {
                                Text(loc.t(category.nameKey))
                                Text("\(items.count)").foregroundStyle(.tertiary).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Style: Keyboard map

// `MappingsKeyboardStyleView` lives in MappingsKeyboardStyle.swift.
