import Foundation
import Yams

/// Errors surfaced to the UI from config operations.
enum ConfigError: LocalizedError {
    case fileExists           // export target exists and overwrite not requested
    case emptyImport
    case invalidEntry(String)
    case actionInUse(String)  // delete blocked: action referenced by mappings
    case io(String)

    var errorDescription: String? {
        switch self {
        case .fileExists: return "FILE_EXISTS"
        case .emptyImport: return "Imported file contains no mappings"
        case .invalidEntry(let m): return m
        case .actionInUse(let m): return m
        case .io(let m): return m
        }
    }
}

/// Owns the action mappings, the custom-action library, and app config.
///
/// Config file (`action_mappings.yml`) is a structured document:
/// `{ actions: [custom…], mappings: [...] }`. A legacy bare-list (2.0) is read
/// as mappings-with-inline-actions. Unknown top-level keys are **preserved**
/// across save (lossless round-trip) and never stripped, so a newer version's
/// config survives being opened by an older build. Built-in actions live in
/// code (`BuiltinActions`) and are never persisted.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published private(set) var mappings: [ActionMappingEntry] = []
    @Published private(set) var customActions: [Action] = []
    @Published private(set) var appConfig = AppConfig()

    /// Unknown top-level keys from the loaded document, re-emitted on save.
    private var preservedTopLevel: [(Node, Node)] = []

    // MARK: Default keycodes (JavaScript keyCode values)
    private enum JS {
        static let h: UInt16 = 72, j: UInt16 = 74, k: UInt16 = 75, l: UInt16 = 76
        static let p: UInt16 = 80, y: UInt16 = 89, a: UInt16 = 65, e: UInt16 = 69
        static let u: UInt16 = 85, d: UInt16 = 68, i: UInt16 = 73, n: UInt16 = 78
        static let o: UInt16 = 79
        static let abc: UInt16 = 188      // ',' → ABC layout
        static let wechat: UInt16 = 190   // '.' → WeChat pinyin
    }
    private static let abcInputSourceID = "com.apple.keylayout.ABC"
    private static let wechatInputSourceID = "com.tencent.inputmethod.wetype.pinyin"

    // MARK: - Paths

    private var appDataDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let bundleID = Bundle.main.bundleIdentifier ?? "me.xueshi.hypercapslock"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }
    private var mappingsURL: URL { appDataDir.appendingPathComponent("action_mappings.yml") }
    private var appConfigURL: URL { appDataDir.appendingPathComponent("app_config.yml") }

    // MARK: - Load

    func load() {
        loadDocument()
        loadAppConfig()
    }

    private func loadDocument() {
        var loadedMappings: [ActionMappingEntry] = []
        var loadedActions: [Action] = []
        var seededDefaults = false

        if let content = try? String(contentsOf: mappingsURL, encoding: .utf8),
           let node = (try? Yams.compose(yaml: content)) ?? nil {
            do {
                try parseDocument(node, into: &loadedMappings, actions: &loadedActions)
            } catch {
                FileLog.shared.error("action_mappings.yml parse error: \(error)")
            }
        }

        if loadedMappings.isEmpty && loadedActions.isEmpty {
            loadedMappings = Self.defaultMappings()
            seededDefaults = true
        }
        Self.normalize(&loadedMappings)

        mappings = loadedMappings
        customActions = loadedActions
        MappingsRegistry.shared.set(loadedMappings)
        ActionsRegistry.shared.setCustom(loadedActions)
        if seededDefaults { saveToDisk() }
    }

    /// Parse either the new structured doc (mapping with `actions:`/`mappings:`)
    /// or the legacy bare-list (sequence of mapping entries). Captures unknown
    /// top-level keys for lossless re-emit. Unrecognized entries are logged.
    private func parseDocument(_ node: Node, into mappings: inout [ActionMappingEntry], actions: inout [Action]) throws {
        switch node {
        case .sequence:
            // Legacy 2.0 format: a bare mappings list with inline actions.
            let yaml = try Yams.serialize(node: node)
            mappings = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
            FileLog.shared.info("Loaded legacy bare-list config (\(mappings.count) mappings, no custom actions).")
        case .mapping(let map):
            for (key, value) in map {
                guard let k = key.string else { continue }
                switch k {
                case "mappings":
                    let yaml = try Yams.serialize(node: value)
                    mappings = (try? YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)) ?? []
                case "actions":
                    let yaml = try Yams.serialize(node: value)
                    actions = (try? YAMLDecoder().decode([Action].self, from: yaml)) ?? []
                default:
                    // Unknown top-level key (e.g. a future version's section):
                    // preserve it verbatim and never strip it.
                    preservedTopLevel.append((key, value))
                    FileLog.shared.info("Preserving unrecognized top-level config key: \(k)")
                }
            }
            FileLog.shared.info("Loaded structured config: \(mappings.count) mappings, \(actions.count) custom actions, \(preservedTopLevel.count) preserved key(s).")
        default:
            throw ConfigError.io("Unexpected top-level YAML node")
        }
    }

    private func loadAppConfig() {
        guard let content = try? String(contentsOf: appConfigURL, encoding: .utf8) else { return }
        do {
            appConfig = try YAMLDecoder().decode(AppConfig.self, from: content)
        } catch {
            FileLog.shared.error("app_config.yml parse error: \(error)")
        }
    }

    // MARK: - Mapping mutations

    /// Upsert a mapping. Prefer binding by `actionId` (clears any inline action —
    /// this is the gradual inline→id migration). Pass `inlineAction` only for
    /// legacy/ad-hoc bindings without a library action.
    func upsert(trigger: Trigger, actionId: String?, inlineAction: ActionConfig?) throws {
        if actionId == nil, let inline = inlineAction {
            try Self.validate(inline)
        }
        if let id = actionId, ActionsRegistry.shared.action(byID: id) == nil {
            throw ConfigError.invalidEntry("Unknown action id: \(id)")
        }
        var m = mappings
        let entry = ActionMappingEntry(trigger: trigger,
                                       actionId: actionId,
                                       inlineAction: actionId == nil ? inlineAction : nil)
        if let idx = m.firstIndex(where: { $0.trigger == trigger }) {
            m[idx] = entry
        } else {
            m.append(entry)
        }
        Self.normalize(&m)
        commitMappings(m)
    }

    func remove(trigger: Trigger) {
        var m = mappings
        m.removeAll { $0.trigger == trigger }
        commitMappings(m)
    }

    private func commitMappings(_ m: [ActionMappingEntry]) {
        mappings = m
        MappingsRegistry.shared.set(m)
        saveToDisk()
    }

    // MARK: - Custom action mutations

    func addCustomAction(name: String, config: ActionConfig) throws -> Action {
        try Self.validate(config)
        let action = Action(id: UUID().uuidString, name: name.isEmpty ? "Untitled" : name,
                            config: config, isBuiltin: false)
        var a = customActions
        a.append(action)
        commitActions(a)
        return action
    }

    func updateCustomAction(_ action: Action) throws {
        guard !action.isBuiltin else { throw ConfigError.invalidEntry("Built-in actions can't be edited") }
        try Self.validate(action.config)
        var a = customActions
        guard let idx = a.firstIndex(where: { $0.id == action.id }) else {
            throw ConfigError.invalidEntry("Action not found")
        }
        a[idx] = action
        commitActions(a)
    }

    /// Trigger labels of mappings that reference `actionId` (delete-protection).
    func mappingsReferencing(actionId: String) -> [Trigger] {
        mappings.filter { $0.actionId == actionId }.map(\.trigger)
    }

    func removeCustomAction(id: String) throws {
        let refs = mappingsReferencing(actionId: id)
        if !refs.isEmpty {
            let labels = refs.map(Self.triggerLabel).joined(separator: ", ")
            throw ConfigError.actionInUse(labels)
        }
        var a = customActions
        a.removeAll { $0.id == id }
        commitActions(a)
    }

    private func commitActions(_ a: [Action]) {
        customActions = a
        ActionsRegistry.shared.setCustom(a)
        saveToDisk()
    }

    // MARK: - App config setters (persist, revert on failure)

    func setHideDockIcon(_ hide: Bool) throws { try mutateConfig { $0.hideDockIcon = hide } }
    func setShowHud(_ show: Bool) throws { try mutateConfig { $0.showHud = show } }
    func setHudDuration(_ ms: Int) throws { try mutateConfig { $0.hudDurationMs = min(max(ms, 300), 6000) } }
    func setThemeMode(_ mode: ThemeMode) throws { try mutateConfig { $0.themeMode = mode } }

    private func mutateConfig(_ change: (inout AppConfig) -> Void) throws {
        let prev = appConfig
        change(&appConfig)
        do { try persistAppConfig() } catch { appConfig = prev; throw error }
    }

    // MARK: - Import / Export (whole document — self-contained & portable)

    func export(to path: String, overwrite: Bool) throws {
        if !overwrite && FileManager.default.fileExists(atPath: path) {
            throw ConfigError.fileExists
        }
        let content = try renderDocument()
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do { try content.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw ConfigError.io("Failed to write file: \(error.localizedDescription)") }
    }

    @discardableResult
    func importDocument(from path: String) throws -> Int {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let node = (try? Yams.compose(yaml: content)) ?? nil else {
            throw ConfigError.io("Failed to read or parse file")
        }
        var importedMappings: [ActionMappingEntry] = []
        var importedActions: [Action] = []
        do { try parseDocument(node, into: &importedMappings, actions: &importedActions) }
        catch { throw ConfigError.io("Invalid config: \(error.localizedDescription)") }

        if importedMappings.isEmpty { throw ConfigError.emptyImport }
        for entry in importedMappings where entry.actionId == nil {
            if let inline = entry.inlineAction { try Self.validate(inline, importing: true) }
        }
        Self.normalize(&importedMappings)

        mappings = importedMappings
        customActions = importedActions
        MappingsRegistry.shared.set(importedMappings)
        ActionsRegistry.shared.setCustom(importedActions)
        saveToDisk()
        return importedMappings.count
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let content = try renderDocument()
            try FileManager.default.createDirectory(at: appDataDir, withIntermediateDirectories: true)
            try content.write(to: mappingsURL, atomically: true, encoding: .utf8)
        } catch {
            FileLog.shared.error("Failed to write action_mappings.yml: \(error)")
        }
    }

    /// Serialize the structured document, preserving unknown top-level keys.
    private func renderDocument() throws -> String {
        let actionsNode = try (Yams.compose(yaml: try YAMLEncoder().encode(customActions)) ?? Node.sequence([]))
        let mappingsNode = try (Yams.compose(yaml: try YAMLEncoder().encode(mappings)) ?? Node.sequence([]))
        var pairs: [(Node, Node)] = preservedTopLevel
        pairs.append((Node("actions"), actionsNode))
        pairs.append((Node("mappings"), mappingsNode))
        let doc = Node.mapping(Node.Mapping(pairs))
        return try Yams.serialize(node: doc)
    }

    private func persistAppConfig() throws {
        do {
            let content = try YAMLEncoder().encode(appConfig)
            try FileManager.default.createDirectory(at: appDataDir, withIntermediateDirectories: true)
            try content.write(to: appConfigURL, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigError.io("Failed to write app config: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation

    static func validate(_ action: ActionConfig, importing: Bool = false) throws {
        switch action {
        case .command(let c) where c.trimmingCharacters(in: .whitespaces).isEmpty:
            throw ConfigError.invalidEntry(importing ? "Imported entry has empty command" : "command cannot be empty")
        case .inputSource(let id) where id.trimmingCharacters(in: .whitespaces).isEmpty:
            throw ConfigError.invalidEntry(importing ? "Imported entry has empty input_source_id" : "input_source_id cannot be empty")
        case .jump(_, let count) where count < 1:
            throw ConfigError.invalidEntry(importing ? "Imported entry has invalid jump count (< 1)" : "jump count must be >= 1")
        default:
            break
        }
    }

    // MARK: - Normalize (dedup by trigger; last value wins, first position kept)

    static func normalize(_ m: inout [ActionMappingEntry]) {
        var deduped: [ActionMappingEntry] = []
        for entry in m {
            if let idx = deduped.firstIndex(where: { $0.trigger == entry.trigger }) {
                deduped[idx] = entry
            } else {
                deduped.append(entry)
            }
        }
        m = deduped
    }

    // MARK: - Defaults (bind to built-in action ids; ABC/WeChat stay inline)

    static func defaultMappings() -> [ActionMappingEntry] {
        func ref(_ key: UInt16, _ actionId: String) -> ActionMappingEntry {
            ActionMappingEntry(trigger: .hyperPlusKey(key: key, withShift: false), actionId: actionId)
        }
        func inline(_ key: UInt16, _ config: ActionConfig) -> ActionMappingEntry {
            ActionMappingEntry(trigger: .hyperPlusKey(key: key, withShift: false), inlineAction: config)
        }
        return [
            ref(JS.h, "builtin.move_left"),
            ref(JS.j, "builtin.move_down"),
            ref(JS.k, "builtin.move_up"),
            ref(JS.l, "builtin.move_right"),
            ref(JS.p, "builtin.word_forward"),
            ref(JS.y, "builtin.word_back"),
            ref(JS.a, "builtin.line_start"),
            ref(JS.e, "builtin.line_end"),
            ref(JS.u, "builtin.jump_up_10"),
            ref(JS.d, "builtin.jump_down_10"),
            ref(JS.i, "builtin.backspace"),
            ref(JS.n, "builtin.insert_quotes"),
            ref(JS.o, "builtin.new_line"),
            inline(JS.abc, .inputSource(inputSourceID: abcInputSourceID)),
            inline(JS.wechat, .inputSource(inputSourceID: wechatInputSourceID)),
        ]
    }

    // MARK: - Helpers

    static func triggerLabel(_ t: Trigger) -> String {
        switch t {
        case .singleTapHyper: return "Caps×1"
        case .doubleTapHyper: return "Caps×2"
        case .doubleTapModifier(let m): return "\(modifierGlyph(m))×2"
        case .hyperPlusKey(let key, let withShift):
            return withShift ? "Caps+Shift+\(keyCodeDisplay(key))" : "Caps+\(keyCodeDisplay(key))"
        }
    }
}
