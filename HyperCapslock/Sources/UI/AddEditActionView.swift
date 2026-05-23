import SwiftUI

/// Editor for a custom action: a name + an action-config form. Built-in actions
/// are never edited here (the Actions page hides edit/delete for them).
struct AddEditActionView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    let mode: ActionSheetMode

    @State private var name = ""
    @State private var draft = ActionConfigDraft()

    private var editing: Bool { if case .edit = mode { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing ? loc.t("actions.edit_title") : loc.t("actions.add_title")).font(.headline)

            HStack {
                Text(loc.t("actions.name")).frame(width: 70, alignment: .leading)
                TextField(loc.t("actions.name_placeholder"), text: $name)
            }

            ActionConfigForm(draft: $draft)

            HStack {
                Spacer()
                Button(loc.t("update.cancel")) { dismiss() }
                Button(loc.t("mappings.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || draft.build() == nil)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear(perform: prefill)
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
                _ = try app.addCustomAction(name: name, config: config)
            case .edit(let action):
                try app.updateCustomAction(Action(id: action.id, name: name, config: config, isBuiltin: false))
            }
            app.showToast(loc.t("toast.action_saved"))
            dismiss()
        } catch {
            let msg = (error as? ConfigError)?.errorDescription ?? error.localizedDescription
            app.showToast(msg, isError: true)
        }
    }
}

/// Mutable draft of an ActionConfig, shared by the action and mapping editors.
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

struct ActionConfigForm: View {
    @EnvironmentObject var loc: LocalizationManager
    @Binding var draft: ActionConfigDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(loc.t("actions.type"), selection: $draft.kind) {
                Text(loc.t("group.directional")).tag("directional")
                Text(loc.t("group.jump")).tag("jump")
                Text(loc.t("group.independent")).tag("independent")
                Text(loc.t("group.input_source")).tag("input_source")
                Text(loc.t("group.command")).tag("command")
                Text(loc.t("group.key_combo")).tag("key_combo")
            }
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        switch draft.kind {
        case "directional":
            Picker("", selection: $draft.directional) {
                ForEach(DirectionalActionKind.allCases, id: \.self) { Text(loc.t("action.\($0.rawValue)")).tag($0) }
            }.labelsHidden()
        case "jump":
            HStack {
                Picker("", selection: $draft.jumpDir) {
                    Text(loc.t("action.up")).tag(JumpDirection.up); Text(loc.t("action.down")).tag(JumpDirection.down)
                }.labelsHidden().frame(width: 100)
                TextField("", value: $draft.jumpCount, format: .number).frame(width: 60)
            }
        case "independent":
            Picker("", selection: $draft.independent) {
                ForEach(IndependentActionKind.allCases, id: \.self) { Text(loc.t("action.\($0.rawValue)")).tag($0) }
            }.labelsHidden()
        case "input_source":
            TextField("e.g. com.apple.keylayout.ABC", text: $draft.inputSourceID).font(.system(.body, design: .monospaced))
        case "command":
            TextField("e.g. open -a Calculator", text: $draft.command)
        case "key_combo":
            VStack(alignment: .leading, spacing: 8) {
                KeyCaptureField(jsKeyCode: $draft.targetKey, enabled: true, placeholder: loc.t("mappings.press_key")).frame(height: 34)
                HStack(spacing: 8) {
                    modToggle("⌘", $draft.tCmd); modToggle("⌃", $draft.tCtrl); modToggle("⌥", $draft.tAlt); modToggle("⇧", $draft.tShift)
                }
            }
        default: EmptyView()
        }
    }

    private func modToggle(_ symbol: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: { Text(symbol).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).tint(binding.wrappedValue ? .blue : .secondary)
    }
}
