import SwiftUI
import AppKit

// The Mappings page can render in several visual styles (see `MappingsViewStyle`).
// This file holds the per-style sub-views plus the shared row/trigger components
// they reuse, so adding a new style is just: a new enum case + a new sub-view.
// `MappingsPage` (in MappingsCard.swift) owns the toolbar/sheet/state and simply
// dispatches to the style selected in `AppConfig.mappingsViewStyle`.

// MARK: - Shared trigger chips

/// The trigger rendered as keycap chips (`Caps + H`, `Caps ×2`, `⌘ ×2`, …).
/// Shared by every style so a trigger reads the same everywhere.
struct TriggerChips: View {
    let trigger: Trigger

    var body: some View {
        HStack(spacing: 5) {
            switch trigger {
            case .singleTapHyper:
                Kbd("Caps"); times; Kbd("1")
            case .doubleTapHyper:
                Kbd("Caps"); times; Kbd("2")
            case .doubleTapModifier(let m):
                Kbd(modifierGlyph(m)); times; Kbd("2")
            case .hyperPlusKey(let key, let withShift):
                Kbd("Caps"); plus
                if withShift { Kbd("Shift"); plus }
                Kbd(keyCodeDisplay(key))
            }
        }
    }

    private var plus: some View { Text("+").foregroundColor(.secondary).font(.caption) }
    private var times: some View { Text("×").foregroundColor(.secondary).font(.caption) }
}

// MARK: - Shared mapping row

/// One mapping row: trigger chips on the left, the resolved action on the right,
/// the per-app-rules badge, and hover edit/delete. Designed to live inside a
/// `Form` (used by both the list and grouped styles).
struct MappingRow: View {
    let entry: ActionMappingEntry
    let availableInputSources: [String: InputSourceFix.AvailableSource]
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
            TriggerChips(trigger: entry.trigger)
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

    var body: some View {
        StylePlaceholder(symbol: "square.stack.3d.up.fill", title: "Grouped by trigger")
    }
}

// MARK: - Style: Keyboard map (implemented in a later step)

struct MappingsKeyboardStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    let onEdit: (ActionMappingEntry) -> Void
    let onDelete: (ActionMappingEntry) -> Void

    var body: some View {
        StylePlaceholder(symbol: "keyboard", title: "Keyboard map")
    }
}

/// Temporary centered placeholder for styles not yet implemented.
struct StylePlaceholder: View {
    let symbol: String
    let title: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text("Coming soon").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
