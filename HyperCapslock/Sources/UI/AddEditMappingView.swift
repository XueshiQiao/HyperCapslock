import SwiftUI
import AppKit

private let modifierOrder: [ModifierKey] = [
    .leftCommand, .rightCommand, .leftControl, .rightControl,
    .leftOption, .rightOption, .leftShift, .rightShift, .fn,
]

private let keepInlineSentinel = "__inline__"
/// Picker sentinel for the parameterized "Switch Input Source" action — selecting
/// it reveals an input-source sub-picker and stores an inline `.inputSource`.
let switchInputSourceSentinel = "__switch_input_source__"

/// Picker sentinels for the parameterized action kinds the user can configure
/// **inline** in the mapping editor — selecting one reveals that kind's fields
/// (an `ActionConfigDetail`) and stores an **inline action** (never a named
/// custom action). Each maps to an `ActionConfigDraft.kind`. Input Source reuses
/// its pre-existing sentinel so saved configs round-trip unchanged.
private let inlineKindSentinels: [(sentinel: String, kind: String, labelKey: String, symbol: String)] = [
    (switchInputSourceSentinel, "input_source", "mappings.switch_input_source", "globe"),
    ("__inline_jump__", "jump", "group.jump", "chevron.up.2"),
    ("__inline_command__", "command", "group.command", "terminal"),
    ("__inline_key_combo__", "key_combo", "group.key_combo", "keyboard"),
    ("__inline_open_app__", "open_app", "group.open_app", "arrow.up.forward.app"),
    ("__inline_hold_modifier__", "hold_modifier", "group.hold_modifier", "hand.tap"),
]

/// The `ActionConfigDraft.kind` an inline sentinel selects, or nil if `sentinel`
/// isn't an inline-action sentinel (a builtin/custom id, create, or keep-inline).
private func inlineKind(for sentinel: String) -> String? {
    inlineKindSentinels.first { $0.sentinel == sentinel }?.kind
}

/// The inline sentinel that edits an existing `config`, or nil if the config
/// isn't one of the inline-editable parameterized kinds (directional/independent
/// resolve to builtins; anything else is preserved verbatim).
private func inlineSentinel(for config: ActionConfig) -> String? {
    var d = ActionConfigDraft()
    d.load(config)
    return inlineKindSentinels.first { $0.kind == d.kind }?.sentinel
}

/// True if `draft` (interpreted as `sentinel`'s kind) builds a valid action.
/// Non-inline sentinels are always "valid" here (they don't use the draft).
private func inlineDraftValid(_ draft: ActionConfigDraft, sentinel: String) -> Bool {
    guard let kind = inlineKind(for: sentinel) else { return true }
    var d = draft
    d.kind = kind
    return d.build() != nil
}

/// An editable per-app rule. `preserved` is non-nil when the rule came from a
/// config shape the editor can't represent (exclude lists, multiple/unknown
/// conditions, or an inline action) — shown read-only and round-tripped verbatim
/// so we never silently drop hand-edited or future config.
private struct BindingDraft: Identifiable {
    let id = UUID()
    var apps: [AppRef] = []
    var actionId: String = "builtin.move_left"
    /// Used when `actionId` is an inline-kind sentinel: the inline action's
    /// parameters, stored as an `inlineAction` (not a named custom action).
    var inlineDraft = ActionConfigDraft()
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
        } else if case let .frontmostApp(include, exclude)? = binding.when.first,
                  binding.when.count == 1, exclude.isEmpty, !include.isEmpty,
                  binding.actionId == nil, let inline = binding.inlineAction,
                  let sentinel = inlineSentinel(for: inline) {
            // An inline parameterized rule (input source / jump / command /
            // key combo / open app) — make it editable via its draft.
            self.apps = include.map { AppRef(bundleID: $0, name: appDisplayName($0)) }
            self.actionId = sentinel
            self.inlineDraft.load(inline)
        } else {
            self.preserved = binding
        }
    }

    init() {}

    func toBinding() -> MappingBinding {
        if let preserved { return preserved }
        let when: [Condition] = [.frontmostApp(include: apps.map { $0.bundleID }, exclude: [])]
        if let kind = inlineKind(for: actionId) {
            var d = inlineDraft
            d.kind = kind
            if let cfg = d.build() { return MappingBinding(when: when, inlineAction: cfg) }
            // Incomplete inline draft. Unreachable via the UI (Save is disabled
            // when any inline rule is invalid), but never emit the sentinel as a
            // real action_id — assert in debug, degrade to a safe default action.
            assertionFailure("toBinding() called with an incomplete inline draft for \(actionId)")
            return MappingBinding(when: when, actionId: "builtin.move_left")
        }
        return MappingBinding(when: when, actionId: actionId)
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
    @State private var dtModifier: ModifierKey = .rightCommand   // chosen in the Key row when triggerSel == "dtm"
    @State private var selectedActionId = "builtin.move_left"
    @State private var inlineDraft = ActionConfigDraft()   // when selectedActionId is an inline-kind sentinel
    @State private var keptInlineConfig: ActionConfig?
    @State private var lastRealActionId = "builtin.move_left"
    @State private var showCreateAction = false
    @State private var createActionSentinel = "__create_action__-" + UUID().uuidString
    @State private var rules: [BindingDraft] = []

    private var editing: Bool { if case .edit = mode { return true }; return false }
    private var triggerNeedsKey: Bool { triggerSel == "plain" || triggerSel == "with_shift" }
    private var triggerNeedsModifier: Bool { triggerSel == "dtm" }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(loc.t("mappings.trigger"), selection: $triggerSel) {
                        Text(loc.t("mappings.caps")).tag("plain")
                        Text(loc.t("mappings.caps_shift")).tag("with_shift")
                        Text(loc.t("trigger.single_tap_hyper")).tag("single_tap")
                        Text(loc.t("trigger.double_tap_hyper")).tag("double_tap")
                        Text(doubleTapModifierLabel).tag("dtm")
                    }
                    .disabled(editing)

                    if triggerNeedsKey {
                        HStack {
                            Text(loc.t("mappings.key"))
                            Spacer()
                            KeyCaptureField(jsKeyCode: $key, enabled: !editing, placeholder: loc.t("mappings.press_key"))
                                .frame(width: 140, height: 28)
                        }
                    } else if triggerNeedsModifier {
                        Picker(loc.t("mappings.key"), selection: $dtModifier) {
                            ForEach(modifierOrder, id: \.self) { m in Text(modifierPickerLabel(m)).tag(m) }
                        }
                        .disabled(editing)
                    }
                }

                Section {
                    Picker(loc.t("mappings.default_action"), selection: $selectedActionId) {
                        if let inline = keptInlineConfig { Label(loc.t("mappings.current_inline"), systemImage: actionSymbol(inline)).tag(keepInlineSentinel) }
                        Section(loc.t("actions.builtin")) {
                            ForEach(BuiltinActions.all, id: \.id) { a in Label(a.nameKey.map { loc.t($0) } ?? a.name, systemImage: actionSymbol(a.config)).tag(a.id) }
                        }
                        Section(loc.t("mappings.inline_section")) {
                            ForEach(inlineKindSentinels, id: \.sentinel) { s in
                                Label(loc.t(s.labelKey), systemImage: s.symbol).tag(s.sentinel)
                            }
                        }
                        if !config.customActions.isEmpty {
                            Section(loc.t("actions.custom")) { ForEach(config.customActions, id: \.id) { a in Label(a.name, systemImage: actionSymbol(a.config)).tag(a.id) } }
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
                            if let kind = inlineKind(for: newValue) { inlineDraft.kind = kind }
                            lastRealActionId = newValue
                        }
                    }
                    if inlineKind(for: selectedActionId) != nil {
                        ActionConfigDetail(draft: $inlineDraft)
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
                                    onDelete: { removeRule(rule.id) })
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
                Button(loc.t("mappings.save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftTrigger == nil
                              || !inlineDraftValid(inlineDraft, sentinel: selectedActionId)
                              || rules.contains { $0.isEditable && !inlineDraftValid($0.inlineDraft, sentinel: $0.actionId) })
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

    /// Delete a rule on the next runloop tick. A rule row may host a `TextField`
    /// (Command / Jump count); deleting synchronously inside the button action
    /// races the field's commit-on-teardown, which writes back through the
    /// `ForEach($rules)` element binding at an index the removal just made stale
    /// → `Array` out-of-range trap. Deferring lets the commit finish first.
    private func removeRule(_ id: UUID) {
        DispatchQueue.main.async { rules.removeAll { $0.id == id } }
    }

    /// Label for the single "Double-tap Modifier" trigger entry — the modifier
    /// itself is chosen in the Key-row picker that appears below when selected.
    private var doubleTapModifierLabel: String { loc.t("trigger.double_tap_modifier") }

    /// Label for a modifier inside the Key-row picker (shown only when the
    /// "Double-tap Modifier" trigger is selected). Spells out the side and the
    /// modifier name alongside the glyph (e.g. "Right Cmd ⌘") so it doesn't read
    /// like a "⌘+R" combo. fn has no side and is flagged experimental.
    private func modifierPickerLabel(_ m: ModifierKey) -> String { modifierFullLabel(m, loc) }

    private var draftTrigger: Trigger? {
        switch triggerSel {
        case "single_tap": return .singleTapHyper
        case "double_tap": return .doubleTapHyper
        case "dtm": return .doubleTapModifier(dtModifier)
        default:
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
            if let kind = inlineKind(for: selectedActionId) {
                var d = inlineDraft
                d.kind = kind
                guard let cfg = d.build() else { return }   // guarded by the disabled Save button
                try app.upsertMapping(trigger: trigger, actionId: nil, inlineAction: cfg, bindings: bindings)
            } else if selectedActionId == keepInlineSentinel, let inline = keptInlineConfig {
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

    private func prefillTrigger(_ trigger: Trigger) {
        switch trigger {
        case .singleTapHyper: triggerSel = "single_tap"
        case .doubleTapHyper: triggerSel = "double_tap"
        case .doubleTapModifier(let m): triggerSel = "dtm"; dtModifier = m
        case .hyperPlusKey(let k, let withShift): triggerSel = withShift ? "with_shift" : "plain"; key = k
        }
    }

    private func prefill() {
        // Adding from the keyboard style: pre-fill only the trigger, leave the
        // action at its default. The trigger remains editable (not an .edit).
        if case .addForTrigger(let trigger) = mode {
            prefillTrigger(trigger)
            lastRealActionId = selectedActionId
            return
        }
        guard case .edit(let entry) = mode else { return }
        prefillTrigger(entry.trigger)
        if let id = entry.actionId {
            selectedActionId = id
        } else if let inline = entry.inlineAction {
            // Prefer the inline editor for parameterized kinds (jump/command/
            // keyCombo/openApp/inputSource) so they stay editable — otherwise an
            // inline jump matching a builtin preset (e.g. jump ×10) would snap to
            // the fixed builtin. directional/independent have no inline sentinel,
            // so they fall through to their builtin selection.
            if let sentinel = inlineSentinel(for: inline) {
                inlineDraft.load(inline)
                selectedActionId = sentinel
            } else if let builtin = BuiltinActions.matching(inline) {
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
                        ForEach(BuiltinActions.all, id: \.id) { a in Label(a.nameKey.map { loc.t($0) } ?? a.name, systemImage: actionSymbol(a.config)).tag(a.id) }
                    }
                    Section(loc.t("mappings.inline_section")) {
                        ForEach(inlineKindSentinels, id: \.sentinel) { s in
                            Label(loc.t(s.labelKey), systemImage: s.symbol).tag(s.sentinel)
                        }
                    }
                    if !config.customActions.isEmpty {
                        Section(loc.t("actions.custom")) { ForEach(config.customActions, id: \.id) { a in Label(a.name, systemImage: actionSymbol(a.config)).tag(a.id) } }
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
                        if let kind = inlineKind(for: newValue) { rule.inlineDraft.kind = kind }
                        lastRealActionId = newValue
                    }
                }
                if inlineKind(for: rule.actionId) != nil {
                    ActionConfigDetail(draft: $rule.inlineDraft)
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
