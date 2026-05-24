import SwiftUI
import AppKit

private let modifierOrder: [ModifierKey] = [
    .leftCommand, .rightCommand, .leftControl, .rightControl,
    .leftOption, .rightOption, .leftShift, .rightShift, .fn,
]

private let keepInlineSentinel = "__inline__"

/// An editable per-app rule. `preserved` is non-nil when the rule came from a
/// config shape the editor can't represent (exclude lists, multiple/unknown
/// conditions, or an inline action) — shown read-only and round-tripped verbatim
/// so we never silently drop hand-edited or future config.
private struct BindingDraft: Identifiable {
    let id = UUID()
    var apps: [AppRef] = []
    var actionId: String = "builtin.move_left"
    var preserved: MappingBinding?

    var isEditable: Bool { preserved == nil }

    /// Build the editor's view of a stored binding, or mark it preserved.
    init(from binding: MappingBinding) {
        if case let .frontmostApp(include, exclude)? = binding.when.first,
           binding.when.count == 1, exclude.isEmpty, !include.isEmpty,
           let actionId = binding.actionId, binding.inlineAction == nil,
           ActionsRegistry.shared.action(byID: actionId) != nil {
            self.apps = include.map { AppRef(bundleID: $0, name: appDisplayName($0)) }
            self.actionId = actionId
        } else {
            self.preserved = binding
        }
    }

    init() {}

    func toBinding() -> MappingBinding {
        if let preserved { return preserved }
        return MappingBinding(when: [.frontmostApp(include: apps.map { $0.bundleID }, exclude: [])],
                              actionId: actionId)
    }
}

/// Best-effort display name for a bundle id (falls back to the id itself).
private func appDisplayName(_ bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        let n = FileManager.default.displayName(atPath: url.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }
    return bundleID
}

/// Bind a trigger to a default Action plus optional per-app overrides. Editing a
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
    @State private var lastRealActionId = "builtin.move_left"
    @State private var showCreateAction = false
    @State private var createActionSentinel = "__create_action__-" + UUID().uuidString
    @State private var rules: [BindingDraft] = []

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
                        HStack {
                            Text(loc.t("mappings.key"))
                            Spacer()
                            KeyCaptureField(jsKeyCode: $key, enabled: !editing, placeholder: loc.t("mappings.press_key"))
                                .frame(width: 140, height: 28)
                        }
                    }
                }

                Section {
                    Picker(loc.t("mappings.default_action"), selection: $selectedActionId) {
                        if keptInlineConfig != nil { Text(loc.t("mappings.current_inline")).tag(keepInlineSentinel) }
                        Section(loc.t("actions.builtin")) {
                            ForEach(BuiltinActions.all, id: \.id) { a in Text(a.nameKey.map { loc.t($0) } ?? a.name).tag(a.id) }
                        }
                        if !config.customActions.isEmpty {
                            Section(loc.t("actions.custom")) { ForEach(config.customActions, id: \.id) { a in Text(a.name).tag(a.id) } }
                        }
                        Section {
                            Label(loc.t("mappings.create_action"), systemImage: "plus").tag(createActionSentinel)
                        }
                    }
                    .onChange(of: selectedActionId) { _, newValue in
                        if newValue == createActionSentinel {
                            selectedActionId = lastRealActionId
                            showCreateAction = true
                        } else {
                            lastRealActionId = newValue
                        }
                    }
                } header: {
                    Text(loc.t("mappings.default_action"))
                } footer: {
                    Text(loc.t("mappings.default_action_hint")).font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach($rules) { $rule in
                        RuleRowView(rule: $rule,
                                    onMoveUp: { move(rule.id, by: -1) },
                                    onMoveDown: { move(rule.id, by: 1) },
                                    onDelete: { rules.removeAll { $0.id == rule.id } })
                    }
                    Button {
                        rules.append(BindingDraft())
                    } label: { Label(loc.t("mappings.add_app_rule"), systemImage: "plus") }
                } header: {
                    Text(loc.t("mappings.app_rules"))
                } footer: {
                    Text(loc.t("mappings.app_rules_hint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button(loc.t("update.cancel")) { dismiss() }
                Button(loc.t("mappings.save")) { save() }.keyboardShortcut(.defaultAction).disabled(draftTrigger == nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
        .navigationTitle(editing ? loc.t("mappings.edit_title") : loc.t("mappings.add_title"))
        .onAppear(perform: prefill)
        .sheet(isPresented: $showCreateAction) {
            AddEditActionView(mode: .add, onCreated: { created in
                selectedActionId = created.id
            })
            .environmentObject(app).environmentObject(config).environmentObject(loc)
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < rules.count else { return }
        rules.swapAt(i, j)
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
        // Editable rules must name at least one app.
        if rules.contains(where: { $0.isEditable && $0.apps.isEmpty }) {
            app.showToast(loc.t("toast.rule_needs_app"), isError: true)
            return
        }
        let bindings = rules.map { $0.toBinding() }
        do {
            if selectedActionId == keepInlineSentinel, let inline = keptInlineConfig {
                try app.upsertMapping(trigger: trigger, actionId: nil, inlineAction: inline, bindings: bindings)
            } else {
                try app.upsertMapping(trigger: trigger, actionId: selectedActionId, bindings: bindings)
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
        lastRealActionId = selectedActionId
        rules = entry.bindings.map(BindingDraft.init(from:))
    }
}

/// One per-app rule: an editable include-list of apps + an action, or a
/// read-only "advanced" row for shapes the editor can't represent.
private struct RuleRowView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager
    @Binding var rule: BindingDraft
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var lastRealActionId = ""
    @State private var showCreateAction = false
    @State private var createActionSentinel = "__create_action__-" + UUID().uuidString

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(loc.t("mappings.applies_in")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red)
            }

            if rule.isEditable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(rule.apps) { app in
                            appChip(app)
                        }
                        Button {
                            if let picked = AppChooser.choose(),
                               !rule.apps.contains(where: { $0.bundleID.lowercased() == picked.bundleID.lowercased() }) {
                                rule.apps.append(picked)
                            }
                        } label: { Label(loc.t("mappings.add_app"), systemImage: "plus") }
                            .buttonStyle(.borderless)
                    }
                }
                Picker(loc.t("mappings.rule_action"), selection: $rule.actionId) {
                    Section(loc.t("actions.builtin")) {
                        ForEach(BuiltinActions.all, id: \.id) { a in Text(a.nameKey.map { loc.t($0) } ?? a.name).tag(a.id) }
                    }
                    if !config.customActions.isEmpty {
                        Section(loc.t("actions.custom")) { ForEach(config.customActions, id: \.id) { a in Text(a.name).tag(a.id) } }
                    }
                    Section {
                        Label(loc.t("mappings.create_action"), systemImage: "plus").tag(createActionSentinel)
                    }
                }
                .onChange(of: rule.actionId) { _, newValue in
                    if newValue == createActionSentinel {
                        rule.actionId = lastRealActionId          // revert; not a real pick
                        showCreateAction = true
                    } else {
                        lastRealActionId = newValue
                    }
                }
            } else {
                Label(loc.t("mappings.advanced_rule"), systemImage: "curlybraces")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear { lastRealActionId = rule.actionId }
        .sheet(isPresented: $showCreateAction) {
            AddEditActionView(mode: .add, onCreated: { created in rule.actionId = created.id })
                .environmentObject(app).environmentObject(config).environmentObject(loc)
        }
    }

    private func appChip(_ app: AppRef) -> some View {
        HStack(spacing: 4) {
            if let icon = AppChooser.icon(app.bundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(app.name).font(.caption)
            Button { rule.apps.removeAll { $0.bundleID == app.bundleID } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}
