import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                        // Input Source actions are now created directly in the mapping
                        // editor ("Switch Input Source"); keep this option only so an
                        // existing custom Input Source action can still be edited.
                        if editing, draft.kind == "input_source" {
                            Text(loc.t("group.input_source")).tag("input_source")
                        }
                        Text(loc.t("group.command")).tag("command")
                        Text(loc.t("group.key_combo")).tag("key_combo")
                        Text(loc.t("group.open_app")).tag("open_app")
                        Text(loc.t("group.hold_modifier")).tag("hold_modifier")
                    }
                    ActionConfigDetail(draft: $draft)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)

            Divider()
            HStack {
                Spacer()
                Button(loc.t("update.cancel")) { dismiss() }
                Button(loc.t("mappings.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || draft.build() == nil)
            }
            .padding(12)
        }
        .frame(width: 480, height: 300)
        .auroraBackground()
        .navigationTitle(editing ? loc.t("actions.edit_title") : loc.t("actions.add_title"))
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
    var appBundleID = ""
    var appName = ""
    var modifier: ModifierKey = .leftOption

    mutating func load(_ config: ActionConfig) {
        switch config {
        case .directional(let a): kind = "directional"; directional = a
        case .jump(let d, let c): kind = "jump"; jumpDir = d; jumpCount = c
        case .independent(let a): kind = "independent"; independent = a
        case .inputSource(let id): kind = "input_source"; inputSourceID = id
        case .command(let c): kind = "command"; command = c
        case .keyCombo(let k, let ctrl, let alt, let cmd, let shift):
            kind = "key_combo"; targetKey = k; tCtrl = ctrl; tAlt = alt; tCmd = cmd; tShift = shift
        case .openApp(let bid, let name):
            kind = "open_app"; appBundleID = bid; appName = name
        case .modifierKey(let m):
            kind = "hold_modifier"; modifier = m
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
            // Trim newlines too: a command that is only blank lines is invalid, and
            // a `/bin/sh -c` script never needs leading/trailing blank lines.
            let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? nil : .command(c)
        case "key_combo":
            guard let k = targetKey else { return nil }
            return .keyCombo(targetKey: k, withCtrl: tCtrl, withAlt: tAlt, withCmd: tCmd, withTargetShift: tShift)
        case "open_app":
            let bid = appBundleID.trimmingCharacters(in: .whitespaces)
            return bid.isEmpty ? nil : .openApp(bundleID: bid, name: appName.isEmpty ? bid : appName)
        case "hold_modifier":
            return .modifierKey(modifier)
        default: return nil
        }
    }
}

/// The modifiers offered by the hold-modifier action, in display order. `.fn` is
/// excluded — synthesizing Fn is unreliable (see `KeyCodes.modifierKeyAndFlag`).
enum HoldModifier {
    static let choices: [ModifierKey] = [
        .leftControl, .rightControl, .leftOption, .rightOption,
        .leftCommand, .rightCommand, .leftShift, .rightShift,
    ]
}

/// The per-kind parameter form for an `ActionConfigDraft`. Rendered both by the
/// custom-action editor (`AddEditActionView`) and inline in the mapping editor
/// when a parameterized action (jump/command/keyCombo/openApp/inputSource) is
/// selected directly — the chosen `kind` is fixed by the caller, this view only
/// renders that kind's fields.
struct ActionConfigDetail: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @Binding var draft: ActionConfigDraft

    var body: some View {
        switch draft.kind {
        case "jump":
            Picker(loc.t("group.directional"), selection: $draft.jumpDir) {
                Text(loc.t("action.up")).tag(JumpDirection.up); Text(loc.t("action.down")).tag(JumpDirection.down)
            }
            LabeledContent(loc.t("actions.count")) {
                TextField("", value: $draft.jumpCount, format: .number).frame(width: 70).multilineTextAlignment(.trailing)
            }
        case "input_source":
            InputSourcePicker(title: loc.t("group.input_source"), sourceID: $draft.inputSourceID)
        case "command":
            // A multi-line script field can't use a TextField here: the grouped
            // Form trailing-aligns TextField text and ignores
            // `.multilineTextAlignment(.leading)`. TextEditor (NSTextView) is always
            // leading-aligned + full-width, and renders typed chars immediately. A
            // command runs as `/bin/sh -c`, so newlines are just shell statements.
            // Bounded height (scrolls past ~7 lines) to fit the fixed editor window.
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("group.command"))
                TextEditor(text: $draft.command)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 60, maxHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
        case "open_app":
            LabeledContent(loc.t("actions.app")) {
                HStack(spacing: 8) {
                    if let icon = appIcon(draft.appBundleID) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(draft.appName.isEmpty ? loc.t("actions.no_app") : draft.appName)
                        .foregroundStyle(draft.appName.isEmpty ? .secondary : .primary)
                    Button(loc.t("actions.choose_app")) { chooseApp() }
                }
            }
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
        case "hold_modifier":
            Picker(loc.t("group.hold_modifier"), selection: $draft.modifier) {
                ForEach(HoldModifier.choices, id: \.self) { m in
                    Text(modifierFullLabel(m, loc)).tag(m)
                }
            }
            Text(loc.t("actions.hold_modifier_hint")).font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    private func modToggle(_ symbol: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: { Text(symbol).frame(width: 26) }
            .buttonStyle(.bordered).tint(binding.wrappedValue ? .blue : .secondary)
    }

    /// Let the user pick any installed .app; store its bundle id (stable if the
    /// app later moves) plus a display name for the UI/HUD.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bid = Bundle(url: url)?.bundleIdentifier, !bid.isEmpty else {
            app.showToast(loc.t("toast.app_no_bundle_id"), isError: true)
            return
        }
        draft.appBundleID = bid
        let display = FileManager.default.displayName(atPath: url.path)
        draft.appName = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }

    private func appIcon(_ bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
