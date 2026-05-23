import SwiftUI

private let modifierOrder: [ModifierKey] = [
    .leftCommand, .rightCommand, .leftControl, .rightControl,
    .leftOption, .rightOption, .leftShift, .rightShift, .fn,
]

struct AddEditMappingView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    let mode: MappingSheetMode

    @State private var triggerSel = "plain"
    @State private var key: UInt16?
    @State private var actionKind = "directional"
    @State private var directional: DirectionalActionKind = .left
    @State private var jumpDir: JumpDirection = .up
    @State private var jumpCount = 10
    @State private var independent: IndependentActionKind = .backspace
    @State private var inputSourceID = ""
    @State private var command = ""
    @State private var targetKey: UInt16?
    @State private var tCtrl = false
    @State private var tAlt = false
    @State private var tCmd = false
    @State private var tShift = false

    private var editing: Bool { if case .edit = mode { return true }; return false }
    private var triggerNeedsKey: Bool { triggerSel == "plain" || triggerSel == "with_shift" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing ? loc.t("mappings.edit_title") : loc.t("mappings.add_title"))
                .font(.headline)

            // Trigger row
            HStack(spacing: 8) {
                Picker("", selection: $triggerSel) {
                    Text(loc.t("mappings.caps")).tag("plain")
                    Text(loc.t("mappings.caps_shift")).tag("with_shift")
                    Text(loc.t("trigger.single_tap_hyper")).tag("single_tap")
                    Text(loc.t("trigger.double_tap_hyper")).tag("double_tap")
                    ForEach(modifierOrder, id: \.self) { m in
                        Text(modifierTriggerLabel(m)).tag("dtm:\(m.rawValue)")
                    }
                }
                .labelsHidden()
                .disabled(editing)

                Text("+").foregroundColor(triggerNeedsKey ? .secondary : Color.secondary.opacity(0.4))

                KeyCaptureField(jsKeyCode: $key, enabled: triggerNeedsKey && !editing, placeholder: loc.t("mappings.press_key"))
                    .frame(height: 34)
            }

            Image(systemName: "chevron.down").foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            // Action row
            HStack(alignment: .top, spacing: 8) {
                Picker("", selection: $actionKind) {
                    Text(loc.t("group.directional")).tag("directional")
                    Text(loc.t("group.jump")).tag("jump")
                    Text(loc.t("group.independent")).tag("independent")
                    Text(loc.t("group.input_source")).tag("input_source")
                    Text(loc.t("group.command")).tag("command")
                    Text(loc.t("group.key_combo")).tag("key_combo")
                }
                .labelsHidden()
                .frame(width: 150)

                actionDetail
            }

            HStack {
                Spacer()
                Button(loc.t("update.cancel")) { dismiss() }
                Button(loc.t("mappings.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: prefill)
    }

    @ViewBuilder
    private var actionDetail: some View {
        switch actionKind {
        case "directional":
            Picker("", selection: $directional) {
                ForEach(DirectionalActionKind.allCases, id: \.self) { d in
                    Text(loc.t("action.\(d.rawValue)")).tag(d)
                }
            }.labelsHidden()
        case "jump":
            HStack(spacing: 8) {
                Picker("", selection: $jumpDir) {
                    Text(loc.t("action.up")).tag(JumpDirection.up)
                    Text(loc.t("action.down")).tag(JumpDirection.down)
                }.labelsHidden().frame(width: 90)
                TextField("", value: $jumpCount, format: .number).frame(width: 60)
            }
        case "independent":
            Picker("", selection: $independent) {
                ForEach(IndependentActionKind.allCases, id: \.self) { a in
                    Text(loc.t("action.\(a.rawValue)")).tag(a)
                }
            }.labelsHidden()
        case "input_source":
            TextField("e.g. com.apple.keylayout.ABC", text: $inputSourceID)
                .font(.system(.body, design: .monospaced))
        case "command":
            TextField("e.g. open -a Calculator", text: $command)
        case "key_combo":
            VStack(alignment: .leading, spacing: 8) {
                KeyCaptureField(jsKeyCode: $targetKey, enabled: true, placeholder: loc.t("mappings.press_key"))
                    .frame(height: 34)
                HStack(spacing: 8) {
                    modToggle("⌘", $tCmd); modToggle("⌃", $tCtrl); modToggle("⌥", $tAlt); modToggle("⇧", $tShift)
                }
            }
        default:
            EmptyView()
        }
    }

    private func modToggle(_ symbol: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: {
            Text(symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(binding.wrappedValue ? .blue : .secondary)
    }

    private func modifierTriggerLabel(_ m: ModifierKey) -> String {
        let base = "\(loc.t("trigger.double_tap_prefix")) \(modifierGlyph(m))"
        return m == .fn ? "\(base) (\(loc.t("trigger.experimental")))" : base
    }

    // MARK: - Build / validate / save

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

    private var draftAction: ActionConfig? {
        switch actionKind {
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
            guard let targetKey else { return nil }
            return .keyCombo(targetKey: targetKey, withCtrl: tCtrl, withAlt: tAlt, withCmd: tCmd, withTargetShift: tShift)
        default: return nil
        }
    }

    private var isValid: Bool { draftTrigger != nil && draftAction != nil }

    private func save() {
        guard let trigger = draftTrigger, let action = draftAction else { return }
        do {
            try app.upsertMapping(trigger: trigger, action: action)
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
        case .hyperPlusKey(let k, let withShift):
            triggerSel = withShift ? "with_shift" : "plain"
            key = k
        }
        switch entry.action {
        case .directional(let a): actionKind = "directional"; directional = a
        case .jump(let dir, let count): actionKind = "jump"; jumpDir = dir; jumpCount = count
        case .independent(let a): actionKind = "independent"; independent = a
        case .inputSource(let id): actionKind = "input_source"; inputSourceID = id
        case .command(let c): actionKind = "command"; command = c
        case .keyCombo(let tk, let ctrl, let alt, let cmd, let shift):
            actionKind = "key_combo"; targetKey = tk; tCtrl = ctrl; tAlt = alt; tCmd = cmd; tShift = shift
        }
    }
}
