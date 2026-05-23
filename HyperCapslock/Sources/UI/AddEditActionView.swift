import SwiftUI

/// Editor for a custom action: a name + an action-config form, in a native
/// grouped Form so labels/controls align like System Settings. Only kinds with
/// meaningful parameters are offered (directional/independent are built-in presets).
struct AddEditActionView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    let mode: ActionSheetMode
    /// Called with the freshly created action when adding (not on edit). Lets a
    /// caller (e.g. the mapping editor) auto-select the new action.
    var onCreated: ((Action) -> Void)? = nil

    @State private var name = ""
    @State private var draft = ActionConfigDraft()

    private var editing: Bool { if case .edit = mode { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(loc.t("actions.name"), text: $name, prompt: Text(loc.t("actions.name_placeholder")))
                    Picker(loc.t("actions.type"), selection: $draft.kind) {
                        Text(loc.t("group.jump")).tag("jump")
                        Text(loc.t("group.input_source")).tag("input_source")
                        Text(loc.t("group.command")).tag("command")
                        Text(loc.t("group.key_combo")).tag("key_combo")
                    }
                    detail
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()
            HStack {
                Spacer()
                Button(loc.t("update.cancel")) { dismiss() }
                Button(loc.t("mappings.save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || draft.build() == nil)
            }
            .padding(12)
        }
        .frame(width: 480, height: 300)
        .navigationTitle(editing ? loc.t("actions.edit_title") : loc.t("actions.add_title"))
        .onAppear(perform: prefill)
    }

    @ViewBuilder private var detail: some View {
        switch draft.kind {
        case "jump":
            Picker(loc.t("group.directional"), selection: $draft.jumpDir) {
                Text(loc.t("action.up")).tag(JumpDirection.up); Text(loc.t("action.down")).tag(JumpDirection.down)
            }
            LabeledContent(loc.t("actions.count")) {
                TextField("", value: $draft.jumpCount, format: .number).frame(width: 70).multilineTextAlignment(.trailing)
            }
        case "input_source":
            TextField(loc.t("group.input_source"), text: $draft.inputSourceID, prompt: Text("com.apple.keylayout.ABC"))
                .font(.system(.body, design: .monospaced))
        case "command":
            TextField(loc.t("group.command"), text: $draft.command, prompt: Text("open -a Calculator"))
        case "key_combo":
            HStack {
                Text(loc.t("group.key_combo"))
                Spacer()
                KeyCaptureField(jsKeyCode: $draft.targetKey, enabled: true, placeholder: loc.t("mappings.press_key"))
                    .frame(width: 140, height: 28)
            }
            LabeledContent(loc.t("mappings.action")) {
                HStack(spacing: 6) {
                    modToggle("⌘", $draft.tCmd); modToggle("⌃", $draft.tCtrl); modToggle("⌥", $draft.tAlt); modToggle("⇧", $draft.tShift)
                }
            }
        default: EmptyView()
        }
    }

    private func modToggle(_ symbol: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: { Text(symbol).frame(width: 26) }
            .buttonStyle(.bordered).tint(binding.wrappedValue ? .blue : .secondary)
    }

    private func prefill() {
        guard case .edit(let action) = mode else { return }
        name = action.name
        draft.load(action.config)
    }

    private func save() {
        guard let config = draft.build() else { return }
        do {
            switch mode {
            case .add:
                let created = try app.addCustomAction(name: name, config: config)
                onCreated?(created)
            case .edit(let action): try app.updateCustomAction(Action(id: action.id, name: name, config: config, isBuiltin: false))
            }
            app.showToast(loc.t("toast.action_saved"))
            dismiss()
        } catch {
            let msg = (error as? ConfigError)?.errorDescription ?? error.localizedDescription
            app.showToast(msg, isError: true)
        }
    }
}

/// Mutable draft of an ActionConfig used by the action editor.
struct ActionConfigDraft {
    var kind = "command"
    var directional: DirectionalActionKind = .left
    var jumpDir: JumpDirection = .up
    var jumpCount = 10
    var independent: IndependentActionKind = .backspace
    var inputSourceID = ""
    var command = ""
    var targetKey: UInt16?
    var tCtrl = false, tAlt = false, tCmd = false, tShift = false

    mutating func load(_ config: ActionConfig) {
        switch config {
        case .directional(let a): kind = "directional"; directional = a
        case .jump(let d, let c): kind = "jump"; jumpDir = d; jumpCount = c
        case .independent(let a): kind = "independent"; independent = a
        case .inputSource(let id): kind = "input_source"; inputSourceID = id
        case .command(let c): kind = "command"; command = c
        case .keyCombo(let k, let ctrl, let alt, let cmd, let shift):
            kind = "key_combo"; targetKey = k; tCtrl = ctrl; tAlt = alt; tCmd = cmd; tShift = shift
        }
    }

    func build() -> ActionConfig? {
        switch kind {
        case "directional": return .directional(directional)
        case "jump": return .jump(direction: jumpDir, count: min(99, max(1, jumpCount)))
        case "independent": return .independent(independent)
        case "input_source":
            let id = inputSourceID.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : .inputSource(inputSourceID: id)
        case "command":
            let c = command.trimmingCharacters(in: .whitespaces)
            return c.isEmpty ? nil : .command(c)
        case "key_combo":
            guard let k = targetKey else { return nil }
            return .keyCombo(targetKey: k, withCtrl: tCtrl, withAlt: tAlt, withCmd: tCmd, withTargetShift: tShift)
        default: return nil
        }
    }
}
