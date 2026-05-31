import SwiftUI
import AppKit

// The Mappings page can render in several visual styles (see `MappingsViewStyle`).
// This file holds the per-style sub-views plus the shared row/trigger components
// they reuse, so adding a new style is just: a new enum case + a new sub-view.
// `MappingsPage` (in MappingsCard.swift) owns the toolbar/sheet/state and simply
// dispatches to the style selected in `AppConfig.mappingsViewStyle`.

// MARK: - Keycaps

/// Which keycap look the trigger chips use. `.flat` is the original minimal chip
/// (`Kbd`); `.raised` is the 3D physical keycap from the design mockup.
enum KeycapStyle { case flat, raised }

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
    var style: KeycapStyle = .flat

    var body: some View {
        HStack(spacing: 5) {
            switch trigger {
            case .singleTapHyper:
                cap("Caps"); times; cap("1")
            case .doubleTapHyper:
                cap("Caps"); times; cap("2")
            case .doubleTapModifier(let m):
                cap(modifierGlyph(m)); times; cap("2")
            case .hyperPlusKey(let key, let withShift):
                cap("Caps"); plus
                if withShift { cap("Shift"); plus }
                cap(keyCodeDisplay(key))
            }
        }
    }

    @ViewBuilder private func cap(_ t: String) -> some View {
        switch style {
        case .flat: Kbd(t)
        case .raised: Keycap(t)
        }
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

// MARK: - Shared mapping row

/// One mapping row: trigger chips on the left, the resolved action on the right,
/// the per-app-rules badge, and hover edit/delete. Designed to live inside a
/// `Form` (used by both the list and grouped styles).
struct MappingRow: View {
    let entry: ActionMappingEntry
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    var keycapStyle: KeycapStyle = .flat
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        let d = mappingActionDisplay(entry, loc, availableInputSources: availableInputSources)
        let bindingsInvalid = entry.bindings.contains { ActionsRegistry.shared.resolve($0) == nil }
        return LabeledContent {
            HStack(spacing: 8) {
                if let icon = d.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: d.symbol).foregroundStyle(d.invalid ? .orange : .secondary)
                }
                Text(d.text).foregroundStyle(d.invalid ? .orange : .secondary).lineLimit(1).truncationMode(.middle)
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
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
        } label: {
            TriggerChips(trigger: entry.trigger, style: keycapStyle)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

// MARK: - Style: List (original flat list)

struct MappingsListStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    let onEdit: (ActionMappingEntry) -> Void
    let onDelete: (ActionMappingEntry) -> Void
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Form {
            if entries.isEmpty {
                Section { Text(loc.t("mappings.empty")).foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(entries, id: \.trigger) { entry in
                        MappingRow(entry: entry, availableInputSources: availableInputSources,
                                   onEdit: { onEdit(entry) }, onDelete: { onDelete(entry) })
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Style: Grouped by trigger (implemented in a later step)

struct MappingsGroupedStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
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
                                           keycapStyle: .raised,
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
