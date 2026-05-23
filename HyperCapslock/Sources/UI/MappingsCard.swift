import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MappingSheetMode: Identifiable {
    case add
    case edit(ActionMappingEntry)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let e): return "edit-\(triggerUniqueID(e.trigger))"
        }
    }
}

private func triggerSortKey(_ t: Trigger) -> String {
    switch t {
    case .singleTapHyper: return "0:single"
    case .doubleTapHyper: return "0:double"
    case .doubleTapModifier(let m): return "0:modifier:\(m.rawValue)"
    case .hyperPlusKey(let key, let withShift): return "1:\(String(format: "%04d", key)):\(withShift ? "1" : "0")"
    }
}

struct ActionDisplay { let text: String; let symbol: String; let invalid: Bool }

@MainActor
func mappingActionDisplay(_ entry: ActionMappingEntry, _ loc: LocalizationManager) -> ActionDisplay {
    if let id = entry.actionId {
        if let action = ActionsRegistry.shared.action(byID: id) {
            let name = action.nameKey.map { loc.t($0) } ?? action.name
            return ActionDisplay(text: name, symbol: actionSymbol(action.config), invalid: false)
        }
        if let inline = entry.inlineAction {
            return ActionDisplay(text: actionPresentation(inline, loc).value, symbol: actionSymbol(inline), invalid: false)
        }
        return ActionDisplay(text: loc.t("mappings.invalid"), symbol: "exclamationmark.triangle.fill", invalid: true)
    }
    if let inline = entry.inlineAction {
        return ActionDisplay(text: actionPresentation(inline, loc).value, symbol: actionSymbol(inline), invalid: false)
    }
    return ActionDisplay(text: loc.t("mappings.invalid"), symbol: "exclamationmark.triangle.fill", invalid: true)
}

func actionSymbol(_ config: ActionConfig) -> String {
    switch config {
    case .directional(let a):
        switch a {
        case .left: return "arrow.left"; case .right: return "arrow.right"
        case .up: return "arrow.up"; case .down: return "arrow.down"
        case .wordForward: return "arrow.right.to.line"; case .wordBack: return "arrow.left.to.line"
        case .home: return "arrow.up.left"; case .end: return "arrow.down.right"
        }
    case .jump(let dir, _): return dir == .up ? "chevron.up.2" : "chevron.down.2"
    case .independent(let a):
        switch a {
        case .backspace: return "delete.left"; case .nextLine: return "return"
        case .insertQuotes: return "quote.opening"; case .toggleCapsLock: return "capslock"
        case .switchInputSource: return "globe"
        }
    case .inputSource: return "globe"
    case .command: return "terminal"
    case .keyCombo: return "command"
    }
}

struct ActionPresentation { let category: String; let value: String; let symbol: String }

@MainActor
func actionPresentation(_ action: ActionConfig, _ loc: LocalizationManager) -> ActionPresentation {
    switch action {
    case .directional(let a):
        return ActionPresentation(category: loc.t("group.directional"), value: loc.t("action.\(a.rawValue)"), symbol: actionSymbol(action))
    case .jump(let direction, let count):
        return ActionPresentation(category: loc.t("group.jump"), value: "\(loc.t("action.\(direction.rawValue)")) ×\(count)", symbol: actionSymbol(action))
    case .independent(let a):
        return ActionPresentation(category: loc.t("group.independent"), value: loc.t("action.\(a.rawValue)"), symbol: actionSymbol(action))
    case .inputSource(let id):
        return ActionPresentation(category: loc.t("group.input_source"), value: id, symbol: actionSymbol(action))
    case .command(let cmd):
        return ActionPresentation(category: loc.t("group.command"), value: cmd, symbol: actionSymbol(action))
    case .keyCombo(let key, let ctrl, let alt, let cmd, let shift):
        var parts: [String] = []
        if ctrl { parts.append("Ctrl") }; if alt { parts.append("Alt") }
        if cmd { parts.append("Cmd") }; if shift { parts.append("Shift") }
        parts.append(keyCodeDisplay(key))
        return ActionPresentation(category: loc.t("group.key_combo"), value: parts.joined(separator: "+"), symbol: actionSymbol(action))
    }
}

struct MappingsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager
    @State private var sheet: MappingSheetMode?

    private var sorted: [ActionMappingEntry] {
        config.mappings.sorted { triggerSortKey($0.trigger) < triggerSortKey($1.trigger) }
    }

    var body: some View {
        Form {
            if config.mappings.isEmpty {
                Section { Text(loc.t("mappings.empty")).foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(sorted, id: \.trigger) { entry in mappingRow(entry) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.mappings"))
        .toolbar {
            ToolbarItemGroup {
                Button { importConfig() } label: { Image(systemName: "square.and.arrow.down") }.help(loc.t("config.import"))
                Button { exportConfig() } label: { Image(systemName: "square.and.arrow.up") }.help(loc.t("config.export"))
                Button { sheet = .add } label: { Image(systemName: "plus") }.help(loc.t("mappings.add"))
            }
        }
        .sheet(item: $sheet) { mode in
            AddEditMappingView(mode: mode).environmentObject(app).environmentObject(config).environmentObject(loc)
        }
    }

    private func mappingRow(_ entry: ActionMappingEntry) -> some View {
        let d = mappingActionDisplay(entry, loc)
        return LabeledContent {
            HStack(spacing: 8) {
                Image(systemName: d.symbol).foregroundStyle(d.invalid ? .orange : .secondary)
                Text(d.text).foregroundStyle(d.invalid ? .orange : .secondary).lineLimit(1).truncationMode(.middle)
                Button { sheet = .edit(entry) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                Button {
                    app.removeMapping(entry.trigger); app.showToast(loc.t("toast.mapping_removed"))
                } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
        } label: {
            triggerChips(entry.trigger)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { sheet = .edit(entry) }
    }

    @ViewBuilder
    private func triggerChips(_ trigger: Trigger) -> some View {
        HStack(spacing: 5) {
            switch trigger {
            case .singleTapHyper: Kbd("Caps"); Text("×").foregroundColor(.secondary).font(.caption); Kbd("1")
            case .doubleTapHyper: Kbd("Caps"); Text("×").foregroundColor(.secondary).font(.caption); Kbd("2")
            case .doubleTapModifier(let m): Kbd(modifierGlyph(m)); Text("×").foregroundColor(.secondary).font(.caption); Kbd("2")
            case .hyperPlusKey(let key, let withShift):
                Kbd("Caps"); Text("+").foregroundColor(.secondary).font(.caption)
                if withShift { Kbd("Shift"); Text("+").foregroundColor(.secondary).font(.caption) }
                Kbd(keyCodeDisplay(key))
            }
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hyper-capslock-config.yml"
        if let yaml = UTType(filenameExtension: "yml") { panel.allowedContentTypes = [yaml] }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do { try config.export(to: url.path, overwrite: true); app.showToast(loc.t("toast.config_exported")) }
            catch { app.showToast(loc.t("toast.config_export_failed"), isError: true) }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if let y1 = UTType(filenameExtension: "yml"), let y2 = UTType(filenameExtension: "yaml") {
            panel.allowedContentTypes = [y1, y2]
        }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let alert = NSAlert()
            alert.messageText = loc.t("config.import_title")
            alert.informativeText = loc.t("config.import_prompt")
            alert.addButton(withTitle: loc.t("config.import_confirm"))
            alert.addButton(withTitle: loc.t("update.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                let count = try config.importDocument(from: url.path)
                app.showToast(loc.t("toast.config_imported", ["count": String(count)]))
            } catch {
                let msg = (error as? ConfigError)?.errorDescription ?? error.localizedDescription
                app.showToast(loc.t("toast.config_import_failed", ["error": msg]), isError: true)
            }
        }
    }
}
