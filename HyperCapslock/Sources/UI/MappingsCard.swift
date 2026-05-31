import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MappingSheetMode: Identifiable {
    case add
    /// Add a new mapping with its trigger pre-filled (used by the keyboard style
    /// when tapping an unmapped key). The trigger stays editable — it's a new
    /// mapping, not an edit.
    case addForTrigger(Trigger)
    case edit(ActionMappingEntry)
    var id: String {
        switch self {
        case .add: return "add"
        case .addForTrigger(let t): return "add-\(triggerUniqueID(t))"
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

struct ActionDisplay { let text: String; let symbol: String; let invalid: Bool; var icon: NSImage? = nil }

@MainActor
func mappingActionDisplay(_ entry: ActionMappingEntry, _ loc: LocalizationManager,
                          availableInputSources: [String: InputSourceFix.AvailableSource]) -> ActionDisplay {
    if let id = entry.actionId {
        if let action = ActionsRegistry.shared.action(byID: id) {
            let name = action.nameKey.map { loc.t($0) } ?? action.name
            return inputSourceAware(action.config, text: name, available: availableInputSources)
        }
        if let inline = entry.inlineAction {
            return inputSourceAware(inline, text: actionPresentation(inline, loc).value, available: availableInputSources)
        }
        return ActionDisplay(text: loc.t("mappings.invalid"), symbol: "exclamationmark.triangle.fill", invalid: true)
    }
    if let inline = entry.inlineAction {
        return inputSourceAware(inline, text: actionPresentation(inline, loc).value, available: availableInputSources)
    }
    return ActionDisplay(text: loc.t("mappings.invalid"), symbol: "exclamationmark.triangle.fill", invalid: true)
}

/// For an `.inputSource` action, show the source's localized name + real icon so
/// the row says which input source it switches to. If that id is no longer an
/// installed source, flag it (⚠️, orange, showing the bare id) via the existing
/// invalid styling. Other action kinds display as given. Taking the map (vs a
/// static lookup) lets the row re-render when availability refreshes.
@MainActor
func inputSourceAware(_ config: ActionConfig, text: String,
                      available: [String: InputSourceFix.AvailableSource]) -> ActionDisplay {
    if case .inputSource(let id) = config {
        if let src = available[id] {
            return ActionDisplay(text: src.name, symbol: actionSymbol(config), invalid: false, icon: src.icon)
        }
        return ActionDisplay(text: id, symbol: "exclamationmark.triangle.fill", invalid: true)
    }
    return ActionDisplay(text: text, symbol: actionSymbol(config), invalid: false)
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
        case .noop: return "nosign"
        }
    case .inputSource: return "globe"
    case .command: return "terminal"
    case .keyCombo: return "keyboard"
    case .openApp: return "arrow.up.forward.app"
    case .modifierKey: return "hand.tap"
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
    case .openApp(let bid, let name):
        return ActionPresentation(category: loc.t("group.open_app"), value: name.isEmpty ? bid : name, symbol: actionSymbol(action))
    case .modifierKey(let m):
        return ActionPresentation(category: loc.t("group.hold_modifier"),
                                  value: modifierHudLabel(m), symbol: actionSymbol(action))
    }
}

struct MappingsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager
    @State private var sheet: MappingSheetMode?
    /// id→source map for input-source rows (name + icon), and to flag a removed
    /// source with ⚠️. Seeded from the cache, refreshed on appear (re-renders rows).
    @State private var availableInputSources: [String: InputSourceFix.AvailableSource] = InputSourceFix.availableSourcesByID()

    private var sorted: [ActionMappingEntry] {
        config.mappings.sorted { triggerSortKey($0.trigger) < triggerSortKey($1.trigger) }
    }

    var body: some View {
        styledContent
            .navigationTitle(loc.t("nav.mappings"))
            // Recompute installed input sources so names/icons are fresh and a removed one shows ⚠️.
            .onAppear { availableInputSources = InputSourceFix.refreshAvailableSourcesByID() }
            .toolbar {
                ToolbarItemGroup {
                    styleSwitcher
                    Button { importConfig() } label: { Image(systemName: "square.and.arrow.down") }.help(loc.t("config.import"))
                    #if DEBUG
                    // Dev-only: one-click import the RELEASE build's config. The Debug
                    // build has its own bundle id (.debug) and therefore its own config
                    // dir, so this mirrors real settings into the dev app. Compiled out
                    // of Release entirely.
                    Button { importReleaseConfig() } label: { Image(systemName: "arrow.down.doc.fill") }
                        .help("Import release config (debug)")
                    #endif
                    Button { exportConfig() } label: { Image(systemName: "square.and.arrow.up") }.help(loc.t("config.export"))
                    Button { sheet = .add } label: { Image(systemName: "plus") }
                        .help(loc.t("mappings.add"))
                        .accessibilityIdentifier("mappings.add")
                }
            }
            .sheet(item: $sheet) { mode in
                AddEditMappingView(mode: mode).environmentObject(app).environmentObject(config).environmentObject(loc)
            }
    }

    /// Dispatch to the sub-view for the persisted style. Each style consumes the
    /// same `sorted` mappings + shared edit/delete actions, so they stay in sync.
    @ViewBuilder private var styledContent: some View {
        switch config.appConfig.mappingsViewStyle {
        case .grouped:
            MappingsGroupedStyleView(entries: sorted, availableInputSources: availableInputSources,
                                     onEdit: { sheet = .edit($0) }, onDelete: deleteEntry)
        case .keyboard:
            MappingsKeyboardStyleView(entries: sorted, availableInputSources: availableInputSources,
                                      onEdit: { sheet = .edit($0) },
                                      onAddTrigger: { sheet = .addForTrigger($0) },
                                      onDelete: deleteEntry)
        }
    }

    /// Segmented style switcher, top-right of the Mappings page. Persisting is a
    /// pure UI preference; if it somehow fails the binding just snaps back.
    private var styleSwitcher: some View {
        Picker("", selection: Binding(
            get: { config.appConfig.mappingsViewStyle },
            set: { try? app.setMappingsViewStyle($0) }
        )) {
            Image(systemName: "list.bullet").tag(MappingsViewStyle.grouped)
            Image(systemName: "keyboard").tag(MappingsViewStyle.keyboard)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(loc.t("mappings.style"))
        // Size to the two segments instead of a fixed width left over from when
        // there were three.
        .fixedSize()
    }

    private func deleteEntry(_ entry: ActionMappingEntry) {
        app.removeMapping(entry.trigger)
        app.showToast(loc.t("toast.mapping_removed"))
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

    #if DEBUG
    /// Dev-only: import the RELEASE build's config (`me.xueshi.hypercapslock`)
    /// in one click. Because the Debug build runs under `…hypercapslock.debug`,
    /// it has a separate Application Support dir; this pulls the real settings in.
    /// macOS may prompt to allow reading another app's data the first time —
    /// approve it. Entirely compiled out of Release builds.
    private func importReleaseConfig() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let releaseConfig = base
            .appendingPathComponent("me.xueshi.hypercapslock", isDirectory: true)
            .appendingPathComponent("action_mappings.yml")
        do {
            let count = try config.importDocument(from: releaseConfig.path)
            app.showToast("Imported \(count) mapping(s) from the release config")
        } catch {
            let msg = (error as? ConfigError)?.errorDescription ?? error.localizedDescription
            app.showToast("Release import failed: \(msg)", isError: true)
        }
    }
    #endif

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
