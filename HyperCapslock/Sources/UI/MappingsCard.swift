import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let actionGroupOrder: [String] = ["directional", "jump", "independent", "input_source", "command", "key_combo"]

private func triggerSortKey(_ t: Trigger) -> String {
    switch t {
    case .singleTapHyper: return "0:single"
    case .doubleTapHyper: return "0:double"
    case .doubleTapModifier(let m): return "0:modifier:\(m.rawValue)"
    case .hyperPlusKey(let key, let withShift):
        return "1:\(String(format: "%04d", key)):\(withShift ? "1" : "0")"
    }
}

struct ActionPresentation {
    let category: String
    let value: String
    let symbol: String
}

@MainActor
func actionPresentation(_ action: ActionConfig, _ loc: LocalizationManager) -> ActionPresentation {
    switch action {
    case .directional(let a):
        let symbols: [DirectionalActionKind: String] = [
            .left: "arrow.left", .right: "arrow.right", .up: "arrow.up", .down: "arrow.down",
            .wordForward: "arrow.right.to.line", .wordBack: "arrow.left.to.line",
            .home: "arrow.up.left", .end: "arrow.down.right",
        ]
        return ActionPresentation(category: loc.t("group.directional"), value: loc.t("action.\(a.rawValue)"), symbol: symbols[a] ?? "arrow.right")
    case .jump(let direction, let count):
        return ActionPresentation(category: loc.t("group.jump"),
                                  value: "\(loc.t("action.\(direction.rawValue)")) x\(count)",
                                  symbol: direction == .up ? "chevron.up.2" : "chevron.down.2")
    case .independent(let a):
        let symbols: [IndependentActionKind: String] = [
            .backspace: "delete.left", .nextLine: "return", .insertQuotes: "quote.opening",
            .toggleCapsLock: "capslock", .switchInputSource: "globe",
        ]
        return ActionPresentation(category: loc.t("group.independent"), value: loc.t("action.\(a.rawValue)"), symbol: symbols[a] ?? "circle")
    case .inputSource(let id):
        return ActionPresentation(category: loc.t("group.input_source"), value: id, symbol: "globe")
    case .command(let cmd):
        return ActionPresentation(category: loc.t("group.command"), value: cmd, symbol: "terminal")
    case .keyCombo(let key, let ctrl, let alt, let cmd, let shift):
        var parts: [String] = []
        if ctrl { parts.append("Ctrl") }
        if alt { parts.append("Alt") }
        if cmd { parts.append("Cmd") }
        if shift { parts.append("Shift") }
        parts.append(keyCodeDisplay(key))
        return ActionPresentation(category: loc.t("group.key_combo"), value: parts.joined(separator: "+"), symbol: "command")
    }
}

struct MappingsCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager
    @Binding var sheet: MappingSheetMode?

    private var grouped: [(key: String, entries: [ActionMappingEntry])] {
        let sorted = config.mappings.sorted { triggerSortKey($0.trigger) < triggerSortKey($1.trigger) }
        return actionGroupOrder.compactMap { key in
            let entries = sorted.filter { $0.action.kindTag == key }
            return entries.isEmpty ? nil : (key, entries)
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(loc.t("mappings.title")).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    Spacer()
                    Button { importConfig() } label: { Label(loc.t("config.import"), systemImage: "square.and.arrow.down") }
                        .controlSize(.small)
                    Button { exportConfig() } label: { Label(loc.t("config.export"), systemImage: "square.and.arrow.up") }
                        .controlSize(.small)
                    Button { sheet = .add } label: { Label(loc.t("mappings.add"), systemImage: "plus") }
                        .controlSize(.small).buttonStyle(.borderedProminent)
                }

                if config.mappings.isEmpty {
                    Text(loc.t("mappings.empty")).font(.system(size: 12)).italic()
                        .foregroundColor(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
                }

                ForEach(grouped, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.t("group.\(group.key)").uppercased())
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                        ForEach(group.entries, id: \.trigger) { entry in
                            MappingRow(entry: entry, sheet: $sheet)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hyper-capslock-config.yml"
        if let yaml = UTType(filenameExtension: "yml") { panel.allowedContentTypes = [yaml] }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try config.export(to: url.path, overwrite: true)  // panel already confirmed overwrite
                app.showToast(loc.t("toast.config_exported"))
            } catch {
                app.showToast(loc.t("toast.config_export_failed"), isError: true)
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let yaml = UTType(filenameExtension: "yml"), let yaml2 = UTType(filenameExtension: "yaml") {
            panel.allowedContentTypes = [yaml, yaml2]
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
                let count = try config.importMappings(from: url.path)
                app.showToast(loc.t("toast.config_imported", ["count": String(count)]))
            } catch {
                let msg = (error as? ConfigError)?.errorDescription ?? error.localizedDescription
                app.showToast(loc.t("toast.config_import_failed", ["error": msg]), isError: true)
            }
        }
    }
}

struct MappingRow: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    let entry: ActionMappingEntry
    @Binding var sheet: MappingSheetMode?

    var body: some View {
        let p = actionPresentation(entry.action, loc)
        return HStack(spacing: 10) {
            triggerChips(entry.trigger)
            Spacer(minLength: 8)
            Text("\(p.category):").font(.system(size: 11)).foregroundColor(.secondary)
            Text(p.value).font(.system(size: 11)).foregroundColor(.blue).lineLimit(1).truncationMode(.middle)
            Image(systemName: p.symbol).font(.system(size: 12)).foregroundColor(.blue)
            Button { sheet = .edit(entry) } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundColor(.secondary).help(loc.t("mappings.edit"))
            Button {
                app.removeMapping(entry.trigger)
                app.showToast(loc.t("toast.mapping_removed"))
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundColor(.secondary).help(loc.t("mappings.delete"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { sheet = .edit(entry) }
    }

    @ViewBuilder
    private func triggerChips(_ trigger: Trigger) -> some View {
        HStack(spacing: 5) {
            switch trigger {
            case .singleTapHyper:
                Kbd("Caps"); Text("×").foregroundColor(.secondary).font(.caption); Kbd("1")
            case .doubleTapHyper:
                Kbd("Caps"); Text("×").foregroundColor(.secondary).font(.caption); Kbd("2")
            case .doubleTapModifier(let m):
                Kbd(modifierGlyph(m)); Text("×").foregroundColor(.secondary).font(.caption); Kbd("2")
            case .hyperPlusKey(let key, let withShift):
                Kbd("Caps"); Text("+").foregroundColor(.secondary).font(.caption)
                if withShift { Kbd("Shift"); Text("+").foregroundColor(.secondary).font(.caption) }
                Kbd(keyCodeDisplay(key))
            }
        }
    }
}
