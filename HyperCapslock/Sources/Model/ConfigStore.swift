import Foundation
import Yams
import CryptoKit

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
/// Config file (`action_mappings.yml`) is a structured document
/// `{ actions: [custom…], mappings: [...] }`. A legacy bare-list (2.0) is read
/// as mappings-with-inline-actions. Unknown keys — both top-level and per-entry —
/// are **preserved** across save (lossless) and never stripped, so a newer
/// version's config survives an older build (downgrade-test safety). A parse
/// failure NEVER overwrites the existing file. Built-ins live in code.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published private(set) var mappings: [ActionMappingEntry] = []
    @Published private(set) var customActions: [Action] = []
    @Published private(set) var appConfig = AppConfig()

    /// Lossless preservation: unknown top-level keys + per-entry raw nodes
    /// (keyed by trigger / action id), re-emitted on save.
    private var preservedTopLevel: [(Node, Node)] = []
    private var preservedMappingNodes: [String: Node] = [:]
    private var preservedActionNodes: [String: Node] = [:]
    /// Mapping/action entries this build can't decode (e.g. an action kind added
    /// by a newer version). Skipped in memory but re-emitted verbatim on save so
    /// an older build never drops a newer build's data (downgrade-safety).
    private var unknownMappingNodes: [Node] = []
    private var unknownActionNodes: [Node] = []

    // "bindings" is known so the fresh encode owns it: when a user clears all
    // per-app rules, the merge step must NOT resurrect a stale preserved node.
    private static let mappingKnownKeys: Set<String> = ["trigger", "key", "with_shift", "action_id", "action", "bindings"]
    private static let actionKnownKeys: Set<String> = ["id", "name", "action"]

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

    // Single source of truth: `AppEnvironment.appSupportDirectory` owns the
    // -uitest temp-dir isolation + the bundle-id data dir (shared with UsageStats
    // so the path can't drift). An empty dir makes ConfigStore seed defaults.
    private var appDataDir: URL { AppEnvironment.appSupportDirectory }
    private var mappingsURL: URL { appDataDir.appendingPathComponent("action_mappings.yml") }
    private var appConfigURL: URL { appDataDir.appendingPathComponent("app_config.yml") }

    // MARK: - Load

    func load() {
        loadDocument()
        loadAppConfig()
    }

    private func loadDocument() {
        let fileExists = FileManager.default.fileExists(atPath: mappingsURL.path)
        var loadedMappings: [ActionMappingEntry] = []
        var loadedActions: [Action] = []
        var parseOK = true

        // Read the raw bytes first so we can back them up even if they aren't
        // valid UTF-8 / YAML (any parse-failure case must be backed up).
        var rawData: Data?
        if fileExists {
            do {
                let data = try Data(contentsOf: mappingsURL)
                rawData = data
                guard let content = String(data: data, encoding: .utf8) else {
                    throw ConfigError.io("config file is not valid UTF-8")
                }
                if let node = try Yams.compose(yaml: content) {
                    try parseDocument(node, into: &loadedMappings, actions: &loadedActions)
                } else {
                    // Empty/whitespace file → treat as empty, safe to seed.
                    resetPreserved()
                }
            } catch {
                // CRITICAL: a parse failure must NOT clobber the user's file.
                // Run with no mappings in memory and leave the file untouched.
                parseOK = false
                FileLog.shared.error("action_mappings.yml parse error: \(error) — leaving the file untouched (not overwriting).")
            }
        }

        // Any parse trouble — a hard failure OR entries we had to skip/preserve —
        // means the in-memory view is lossy vs. the file. Snapshot the original
        // bytes before anything can save over it. Named by content hash and
        // skipped if that snapshot already exists, so we don't pile up a backup
        // per launch.
        if let rawData, !parseOK || !unknownMappingNodes.isEmpty || !unknownActionNodes.isEmpty {
            backupConfigByHash(rawData)
        }

        // Seed defaults ONLY when it's safe: file absent, or present-but-empty
        // (parsed cleanly with nothing in it). Never when parsing failed.
        let shouldSeed = parseOK && loadedMappings.isEmpty && loadedActions.isEmpty
            && unknownMappingNodes.isEmpty && unknownActionNodes.isEmpty
        if shouldSeed {
            loadedMappings = Self.defaultMappings()
        }
        Self.normalize(&loadedMappings)

        mappings = loadedMappings
        customActions = loadedActions
        // Register actions BEFORE mappings so the tap thread never resolves a
        // mapping/binding against a stale action registry (matters on import,
        // which runs while the tap is live).
        ActionsRegistry.shared.setCustom(loadedActions)
        MappingsRegistry.shared.set(loadedMappings)

        // Persist only when we seeded into a fresh/empty file — never overwrite
        // an existing file we couldn't parse.
        if shouldSeed && (!fileExists || isFilePresentButEmpty()) {
            saveToDisk()
        }
    }

    private func isFilePresentButEmpty() -> Bool {
        guard let content = try? String(contentsOf: mappingsURL, encoding: .utf8) else { return true }
        return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Snapshot the on-disk config under `backups/`, named by a hash of its
    /// content, when a parse problem made the in-memory view lossy. Idempotent:
    /// if a snapshot for this exact content already exists we skip it, so the
    /// same broken file doesn't spawn a new backup on every launch.
    private func backupConfigByHash(_ data: Data) {
        let hash = SHA256.hash(data: data).prefix(8)
            .map { String(format: "%02x", $0) }.joined()   // 16 hex chars — ample to dedupe by content
        let dir = mappingsURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
        let backupURL = dir.appendingPathComponent("action_mappings-\(hash).yml")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else {
            FileLog.shared.info("Config backup \(backupURL.lastPathComponent) already exists; skipping.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: backupURL, options: .atomic)
            FileLog.shared.warn("Config parse issue — backed up original to backups/\(backupURL.lastPathComponent)")
        } catch {
            FileLog.shared.error("Failed to write config backup: \(error.localizedDescription)")
        }
    }

    private func resetPreserved() {
        preservedTopLevel = []
        preservedMappingNodes = [:]
        preservedActionNodes = [:]
        unknownMappingNodes = []
        unknownActionNodes = []
    }

    /// Parse the new structured doc or the legacy bare-list. Captures unknown
    /// top-level keys and per-entry nodes for lossless re-emit. Throws on a
    /// malformed entry (so the caller leaves the file untouched).
    private func parseDocument(_ node: Node, into mappings: inout [ActionMappingEntry], actions: inout [Action]) throws {
        resetPreserved()
        switch node {
        case .sequence(let seq):
            mappings = try captureMappings(seq)
            FileLog.shared.info("Loaded legacy bare-list config (\(mappings.count) mappings).")
        case .mapping(let map):
            for (key, value) in map {
                guard let k = key.string else { continue }
                switch k {
                case "mappings":
                    guard case .sequence(let seq) = value else { continue }
                    mappings = try captureMappings(seq)
                case "actions":
                    guard case .sequence(let seq) = value else { continue }
                    actions = try captureActions(seq)
                default:
                    preservedTopLevel.append((key, value))
                    FileLog.shared.info("Preserving unrecognized top-level config key: \(k)")
                }
            }
            FileLog.shared.info("Loaded structured config: \(mappings.count) mappings, \(actions.count) custom actions, \(preservedTopLevel.count) preserved key(s).")
        default:
            throw ConfigError.io("Unexpected top-level YAML node")
        }
    }

    private func captureMappings(_ seq: Node.Sequence) throws -> [ActionMappingEntry] {
        var result: [ActionMappingEntry] = []
        for elem in seq {
            do {
                let yaml = try Yams.serialize(node: elem)
                let entry = try YAMLDecoder().decode(ActionMappingEntry.self, from: yaml)
                preservedMappingNodes[triggerUniqueID(entry.trigger)] = elem
                result.append(entry)
            } catch {
                // An entry this build can't represent (e.g. a newer action kind).
                // Skip it in memory but keep the raw node so it round-trips on
                // save — one unknown entry must not drop the whole config.
                unknownMappingNodes.append(elem)
                FileLog.shared.warn("Skipping unparseable mapping entry (preserved verbatim for save): \(error)")
            }
        }
        return result
    }

    private func captureActions(_ seq: Node.Sequence) throws -> [Action] {
        var result: [Action] = []
        for elem in seq {
            do {
                let yaml = try Yams.serialize(node: elem)
                let action = try YAMLDecoder().decode(Action.self, from: yaml)
                preservedActionNodes[action.id] = elem
                result.append(action)
            } catch {
                unknownActionNodes.append(elem)
                FileLog.shared.warn("Skipping unparseable action entry (preserved verbatim for save): \(error)")
            }
        }
        return result
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
    /// the gradual inline→id migration). Pass `inlineAction` only for legacy/
    /// ad-hoc bindings without a library action.
    func upsert(trigger: Trigger, actionId: String?, inlineAction: ActionConfig?, bindings: [MappingBinding] = []) throws {
        if actionId == nil, let inline = inlineAction {
            try Self.validate(inline)
        }
        if let id = actionId, ActionsRegistry.shared.action(byID: id) == nil {
            throw ConfigError.invalidEntry("Unknown action id: \(id)")
        }
        try bindings.forEach { try Self.validate($0) }
        var m = mappings
        let entry = ActionMappingEntry(trigger: trigger,
                                       actionId: actionId,
                                       inlineAction: actionId == nil ? inlineAction : nil,
                                       bindings: bindings)
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

    @discardableResult
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
    /// Checks the default action AND every per-app binding so a custom action
    /// used only by a rule can't be silently deleted.
    func mappingsReferencing(actionId: String) -> [Trigger] {
        mappings.filter { entry in
            entry.actionId == actionId || entry.bindings.contains { $0.actionId == actionId }
        }.map(\.trigger)
    }

    func removeCustomAction(id: String) throws {
        let refs = mappingsReferencing(actionId: id)
        if !refs.isEmpty {
            let labels = refs.map(Self.triggerLabel).joined(separator: ", ")
            throw ConfigError.actionInUse(labels)
        }
        var a = customActions
        a.removeAll { $0.id == id }
        preservedActionNodes[id] = nil
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
    func setCJKVFixStrategy(_ strategy: CJKVFixStrategy) throws { try mutateConfig { $0.cjkvFixStrategy = strategy } }
    func setBroadcastCapsHoldForAnyDrag(_ on: Bool) throws { try mutateConfig { $0.broadcastCapsHoldForAnyDrag = on } }
    func setMappingsViewStyle(_ style: MappingsViewStyle) throws { try mutateConfig { $0.mappingsViewStyle = style } }
    func setStatsShowInline(_ on: Bool) throws { try mutateConfig { $0.statsShowInline = on } }

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

    /// Import a config document. Replaces mappings; **merges** custom actions
    /// (imported actions override existing ones with the same id; existing
    /// actions not in the file are kept).
    @discardableResult
    func importDocument(from path: String) throws -> Int {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ConfigError.io("Failed to read file")
        }
        guard let node = try? Yams.compose(yaml: content) else {
            throw ConfigError.io("Invalid YAML")
        }
        // Parse into temporaries; capture this file's preserved nodes too.
        var importedMappings: [ActionMappingEntry] = []
        var importedActions: [Action] = []
        do { try parseDocument(node, into: &importedMappings, actions: &importedActions) }
        catch { throw ConfigError.io("Invalid config: \(error.localizedDescription)") }

        if importedMappings.isEmpty { throw ConfigError.emptyImport }
        for entry in importedMappings {
            if entry.actionId == nil, let inline = entry.inlineAction { try Self.validate(inline, importing: true) }
            try entry.bindings.forEach { try Self.validate($0, importing: true) }
        }
        Self.normalize(&importedMappings)

        // Merge custom actions by id (imported wins on collision; keep existing).
        var merged = customActions
        for action in importedActions {
            if let idx = merged.firstIndex(where: { $0.id == action.id }) { merged[idx] = action }
            else { merged.append(action) }
        }

        mappings = importedMappings
        customActions = merged
        // Actions before mappings: the tap is live during import, so a binding
        // referencing a newly-imported custom action must find it registered.
        ActionsRegistry.shared.setCustom(merged)
        MappingsRegistry.shared.set(importedMappings)
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

    /// Serialize the structured document, preserving unknown top-level keys and
    /// per-entry unknown keys (merged back by trigger / action id).
    private func renderDocument() throws -> String {
        let actionsNode = try mergedSequence(customActions.map(\.id),
                                             yaml: try YAMLEncoder().encode(customActions),
                                             preserved: preservedActionNodes,
                                             known: Self.actionKnownKeys)
        let mappingsNode = try mergedSequence(mappings.map { triggerUniqueID($0.trigger) },
                                              yaml: try YAMLEncoder().encode(mappings),
                                              preserved: preservedMappingNodes,
                                              known: Self.mappingKnownKeys)
        var pairs: [(Node, Node)] = preservedTopLevel
        // Re-emit entries this build couldn't decode, verbatim, after the known
        // ones — so a downgraded build round-trips a newer build's data instead
        // of silently dropping it.
        pairs.append((Node("actions"), Self.appendingNodes(actionsNode, unknownActionNodes)))
        pairs.append((Node("mappings"), Self.appendingNodes(mappingsNode, unknownMappingNodes)))
        return try Yams.serialize(node: Node.mapping(Node.Mapping(pairs)))
    }

    /// Compose freshly-encoded entries, then merge each entry's preserved
    /// unknown keys (matched by `keys[i]`).
    private func mergedSequence(_ keys: [String], yaml: String, preserved: [String: Node], known: Set<String>) throws -> Node {
        guard let composed = try Yams.compose(yaml: yaml), case .sequence(var seq) = composed else {
            return Node.sequence([])
        }
        for i in seq.indices where i < keys.count {
            if let original = preserved[keys[i]] {
                seq[i] = Self.mergeUnknownKeys(into: seq[i], from: original, known: known)
            }
        }
        return Node.sequence(seq)
    }

    /// Append extra raw nodes (preserved undecodable entries) to a sequence node.
    private static func appendingNodes(_ node: Node, _ extra: [Node]) -> Node {
        guard !extra.isEmpty, case .sequence(var seq) = node else { return node }
        seq.append(contentsOf: extra)
        return .sequence(seq)
    }

    private static func mergeUnknownKeys(into fresh: Node, from original: Node, known: Set<String>) -> Node {
        guard case .mapping(var freshMap) = fresh, case .mapping(let origMap) = original else { return fresh }
        for (k, v) in origMap {
            guard let ks = k.string else { continue }
            if !known.contains(ks) && freshMap[k] == nil { freshMap[k] = v }
        }
        return .mapping(freshMap)
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
        case .openApp(let bid, _) where bid.trimmingCharacters(in: .whitespaces).isEmpty:
            throw ConfigError.invalidEntry(importing ? "Imported entry has empty bundle_id" : "bundle_id cannot be empty")
        default:
            break
        }
    }

    /// A per-app binding must target at least one condition and resolve to an
    /// action (known id, or a valid inline action).
    static func validate(_ binding: MappingBinding, importing: Bool = false) throws {
        if binding.when.isEmpty {
            throw ConfigError.invalidEntry(importing ? "Imported per-app rule has no condition" : "A per-app rule must target at least one app")
        }
        if let id = binding.actionId {
            // On import the referenced action may be a custom action from the
            // same file that isn't registered yet — only resolution-check live.
            if !importing && ActionsRegistry.shared.action(byID: id) == nil {
                throw ConfigError.invalidEntry("Unknown action id in per-app rule: \(id)")
            }
        } else if let inline = binding.inlineAction {
            try validate(inline, importing: importing)
        } else {
            throw ConfigError.invalidEntry(importing ? "Imported per-app rule has no action" : "A per-app rule must have an action")
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
