import Foundation
import Yams

/// Errors surfaced to the UI from config operations.
enum ConfigError: LocalizedError {
    case fileExists           // export target exists and overwrite not requested
    case emptyImport
    case invalidEntry(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .fileExists: return "FILE_EXISTS"
        case .emptyImport: return "Imported file contains no mappings"
        case .invalidEntry(let m): return m
        case .io(let m): return m
        }
    }
}

/// Owns the action mappings and app config: load/save (YAML, byte-compatible
/// with the original Rust output), defaults, normalize/dedup, import/export.
/// `@MainActor ObservableObject` for the SwiftUI layer; mirrors every change
/// into `MappingsRegistry` for the event-tap thread to read.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published private(set) var mappings: [ActionMappingEntry] = []
    @Published private(set) var appConfig = AppConfig()

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
        loadMappings()
        loadAppConfig()
    }

    private func loadMappings() {
        var loaded: [ActionMappingEntry] = []
        var changed = false

        if let content = try? String(contentsOf: mappingsURL, encoding: .utf8) {
            do {
                loaded = try YAMLDecoder().decode([ActionMappingEntry].self, from: content)
            } catch {
                FileLog.shared.error("action_mappings.yml parse error: \(error)")
            }
        }

        if loaded.isEmpty {
            loaded = Self.defaultMappings()
            changed = true
        }
        Self.normalize(&loaded)

        mappings = loaded
        MappingsRegistry.shared.set(loaded)
        if changed { saveMappingsToDisk() }
    }

    private func loadAppConfig() {
        guard let content = try? String(contentsOf: appConfigURL, encoding: .utf8) else { return }
        do {
            appConfig = try YAMLDecoder().decode(AppConfig.self, from: content)
        } catch {
            FileLog.shared.error("app_config.yml parse error: \(error)")
        }
    }

    // MARK: - Mutations

    /// Validate, upsert (replace by trigger), normalize, persist, sync registry.
    func upsert(trigger: Trigger, action: ActionConfig) throws {
        try Self.validate(action)
        var m = mappings
        if let idx = m.firstIndex(where: { $0.trigger == trigger }) {
            m[idx] = ActionMappingEntry(trigger: trigger, action: action)
        } else {
            m.append(ActionMappingEntry(trigger: trigger, action: action))
        }
        Self.normalize(&m)
        commit(m)
    }

    func remove(trigger: Trigger) {
        var m = mappings
        m.removeAll { $0.trigger == trigger }
        commit(m)
    }

    private func commit(_ m: [ActionMappingEntry]) {
        mappings = m
        MappingsRegistry.shared.set(m)
        saveMappingsToDisk()
    }

    // MARK: - App config setters (persist, revert on failure)

    func setHideDockIcon(_ hide: Bool) throws {
        let prev = appConfig
        appConfig.hideDockIcon = hide
        do { try persistAppConfig() } catch { appConfig = prev; throw error }
    }

    func setShowHud(_ show: Bool) throws {
        let prev = appConfig
        appConfig.showHud = show
        do { try persistAppConfig() } catch { appConfig = prev; throw error }
    }

    func setHudDuration(_ ms: Int) throws {
        let prev = appConfig
        appConfig.hudDurationMs = min(max(ms, 300), 6000)
        do { try persistAppConfig() } catch { appConfig = prev; throw error }
    }

    // MARK: - Import / Export

    func export(to path: String, overwrite: Bool) throws {
        if !overwrite && FileManager.default.fileExists(atPath: path) {
            throw ConfigError.fileExists
        }
        let content = Self.renderYAML(mappings)
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do { try content.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw ConfigError.io("Failed to write file: \(error.localizedDescription)") }
    }

    @discardableResult
    func importMappings(from path: String) throws -> Int {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ConfigError.io("Failed to read file")
        }
        var imported: [ActionMappingEntry]
        do { imported = try YAMLDecoder().decode([ActionMappingEntry].self, from: content) }
        catch { throw ConfigError.io("Invalid YAML: \(error.localizedDescription)") }

        if imported.isEmpty { throw ConfigError.emptyImport }
        for entry in imported { try Self.validate(entry.action, importing: true) }
        Self.normalize(&imported)
        let count = imported.count
        commit(imported)
        return count
    }

    // MARK: - Persistence helpers

    private func saveMappingsToDisk() {
        let content = Self.renderYAML(mappings)
        try? FileManager.default.createDirectory(at: appDataDir, withIntermediateDirectories: true)
        try? content.write(to: mappingsURL, atomically: true, encoding: .utf8)
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

    private static func validate(_ action: ActionConfig, importing: Bool = false) throws {
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

    // MARK: - Defaults

    static func defaultMappings() -> [ActionMappingEntry] {
        func hpk(_ key: UInt16, _ action: ActionConfig) -> ActionMappingEntry {
            ActionMappingEntry(trigger: .hyperPlusKey(key: key, withShift: false), action: action)
        }
        var defaults: [ActionMappingEntry] = [
            hpk(JS.h, .directional(.left)),
            hpk(JS.j, .directional(.down)),
            hpk(JS.k, .directional(.up)),
            hpk(JS.l, .directional(.right)),
            hpk(JS.p, .directional(.wordForward)),
            hpk(JS.y, .directional(.wordBack)),
            hpk(JS.a, .directional(.home)),
            hpk(JS.e, .directional(.end)),
            hpk(JS.u, .jump(direction: .up, count: 10)),
            hpk(JS.d, .jump(direction: .down, count: 10)),
            hpk(JS.i, .independent(.backspace)),
            hpk(JS.n, .independent(.insertQuotes)),
            hpk(JS.o, .independent(.nextLine)),
        ]
        // macOS-only input-source defaults (ABC / WeChat pinyin).
        defaults.append(hpk(JS.abc, .inputSource(inputSourceID: abcInputSourceID)))
        defaults.append(hpk(JS.wechat, .inputSource(inputSourceID: wechatInputSourceID)))
        return defaults
    }

    // MARK: - YAML rendering (with comments — byte-compatible with Rust output)

    private static func yamlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    static func renderYAML(_ mappings: [ActionMappingEntry]) -> String {
        var lines: [String] = [
            "# HyperCapslock action mappings",
            "# trigger.kind: hyper_plus_key (Caps+Key), single_tap_hyper (Caps tapped once),",
            "#   double_tap_hyper (Caps tapped twice), or double_tap_modifier",
            "#   (a modifier key tapped twice)",
            "# key uses JavaScript keyCode",
        ]

        for entry in mappings {
            switch entry.trigger {
            case .hyperPlusKey(let key, let withShift):
                lines.append("- trigger:")
                lines.append("    kind: hyper_plus_key")
                lines.append("    key: \(key) # \(KeyCodes.name(key))")
                lines.append("    with_shift: \(withShift)")
            case .singleTapHyper:
                lines.append("- trigger:")
                lines.append("    kind: single_tap_hyper")
            case .doubleTapHyper:
                lines.append("- trigger:")
                lines.append("    kind: double_tap_hyper")
            case .doubleTapModifier(let m):
                lines.append("- trigger:")
                lines.append("    kind: double_tap_modifier")
                lines.append("    modifier: \(m.rawValue)")
            }

            lines.append("  action:")
            switch entry.action {
            case .directional(let a):
                lines.append("    kind: directional")
                lines.append("    action: \(a.rawValue)")
            case .jump(let direction, let count):
                lines.append("    kind: jump")
                lines.append("    direction: \(direction.rawValue)")
                lines.append("    count: \(count)")
            case .independent(let a):
                lines.append("    kind: independent")
                lines.append("    action: \(a.rawValue)")
            case .inputSource(let id):
                lines.append("    kind: input_source")
                lines.append("    input_source_id: \(yamlQuote(id))")
            case .command(let cmd):
                lines.append("    kind: command")
                lines.append("    command: \(yamlQuote(cmd))")
            case .keyCombo(let targetKey, let ctrl, let alt, let cmd, let shift):
                lines.append("    kind: key_combo")
                lines.append("    target_key: \(targetKey) # \(KeyCodes.name(targetKey))")
                if ctrl { lines.append("    with_ctrl: true") }
                if alt { lines.append("    with_alt: true") }
                if cmd { lines.append("    with_cmd: true") }
                if shift { lines.append("    with_target_shift: true") }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
