import SwiftUI

private let modifierOrder: [ModifierKey] = [
    .leftCommand, .rightCommand, .leftControl, .rightControl,
    .leftOption, .rightOption, .leftShift, .rightShift, .fn,
]

private let keepInlineSentinel = "__inline__"

/// Bind a trigger to an Action from the library (native grouped Form). Editing a
/// legacy inline mapping migrates it to an `action_id` on save (unless the user
/// keeps the "current" inline). New custom actions are created on the Actions tab.
struct AddEditMappingView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    let mode: MappingSheetMode

    @State private var triggerSel = "plain"
    @State private var key: UInt16?
    @State private var selectedActionId = "builtin.move_left"
    @State private var keptInlineConfig: ActionConfig?

    private var editing: Bool { if case .edit = mode { return true }; return false }
    private var triggerNeedsKey: Bool { triggerSel == "plain" || triggerSel == "with_shift" }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(loc.t("mappings.trigger"), selection: $triggerSel) {
                        Text(loc.t("mappings.caps")).tag("plain")
                        Text(loc.t("mappings.caps_shift")).tag("with_shift")
                        Text(loc.t("trigger.single_tap_hyper")).tag("single_tap")
                        Text(loc.t("trigger.double_tap_hyper")).tag("double_tap")
                        ForEach(modifierOrder, id: \.self) { m in Text(modifierTriggerLabel(m)).tag("dtm:\(m.rawValue)") }
                    }
                    .disabled(editing)

                    if triggerNeedsKey {
                        // HStack (default .center alignment) instead of LabeledContent:
                        // LabeledContent top-aligns its label when the trailing control
                        // is taller than the label, which left "Key" misaligned.
                        HStack {
                            Text(loc.t("mappings.key"))
                            Spacer()
                            KeyCaptureField(jsKeyCode: $key, enabled: !editing, placeholder: loc.t("mappings.press_key"))
                                .frame(width: 140, height: 28)
                        }
                    }
                }

                Section {
                    Picker(loc.t("mappings.action"), selection: $selectedActionId) {
                        if keptInlineConfig != nil { Text(loc.t("mappings.current_inline")).tag(keepInlineSentinel) }
                        Section(loc.t("actions.builtin")) {
                            ForEach(BuiltinActions.all, id: \.id) { a in Text(a.nameKey.map { loc.t($0) } ?? a.name).tag(a.id) }
                        }
                        if !config.customActions.isEmpty {
                            Section(loc.t("actions.custom")) { ForEach(config.customActions, id: \.id) { a in Text(a.name).tag(a.id) } }
                        }
                    }
                } footer: {
                    Text(loc.t("mappings.action_hint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()
            HStack {
                Spacer()
                Button(loc.t("update.cancel")) { dismiss() }
                Button(loc.t("mappings.save")) { save() }.keyboardShortcut(.defaultAction).disabled(draftTrigger == nil)
            }
            .padding(12)
        }
        .frame(width: 480, height: 250)
        .navigationTitle(editing ? loc.t("mappings.edit_title") : loc.t("mappings.add_title"))
        .onAppear(perform: prefill)
    }

    private func modifierTriggerLabel(_ m: ModifierKey) -> String {
        let base = "\(loc.t("trigger.double_tap_prefix")) \(modifierGlyph(m))"
        return m == .fn ? "\(base) (\(loc.t("trigger.experimental")))" : base
    }

    private var draftTrigger: Trigger? {
        switch triggerSel {
        case "single_tap": return .singleTapHyper
        case "double_tap": return .doubleTapHyper
        default:
            if triggerSel.hasPrefix("dtm:"), let m = ModifierKey(rawValue: String(triggerSel.dropFirst(4))) {
                return .doubleTapModifier(m)
            }
            guard let key else { return nil }
            return .hyperPlusKey(key: key, withShift: triggerSel == "with_shift")
        }
    }

    private func save() {
        guard let trigger = draftTrigger else { return }
        do {
            if selectedActionId == keepInlineSentinel, let inline = keptInlineConfig {
                try app.upsertMapping(trigger: trigger, actionId: nil, inlineAction: inline)
            } else {
                try app.upsertMapping(trigger: trigger, actionId: selectedActionId)
            }
            app.showToast(loc.t("toast.mapping_saved"))
            dismiss()
        } catch {
            let msg = (error as? ConfigError)?.errorDescription ?? error.localizedDescription
            app.showToast(msg, isError: true)
        }
    }

    private func prefill() {
        guard case .edit(let entry) = mode else { return }
        switch entry.trigger {
        case .singleTapHyper: triggerSel = "single_tap"
        case .doubleTapHyper: triggerSel = "double_tap"
        case .doubleTapModifier(let m): triggerSel = "dtm:\(m.rawValue)"
        case .hyperPlusKey(let k, let withShift): triggerSel = withShift ? "with_shift" : "plain"; key = k
        }
        if let id = entry.actionId {
            selectedActionId = id
        } else if let inline = entry.inlineAction {
            if let builtin = BuiltinActions.matching(inline) {
                selectedActionId = builtin.id
            } else {
                keptInlineConfig = inline
                selectedActionId = keepInlineSentinel
            }
        }
    }
}
