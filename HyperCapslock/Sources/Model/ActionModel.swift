import Foundation

// Data model for action mappings. The wire format (YAML) is byte-compatible
// with the original Rust/serde implementation so existing users' config files
// load unchanged. serde used internally-tagged enums (`#[serde(tag = "kind",
// rename_all = "snake_case")]`), so the Codable conformances below are written
// by hand to read/write that exact shape.

// MARK: - Leaf enums (simple snake_case string enums)

enum DirectionalActionKind: String, Codable, CaseIterable, Equatable {
    case left, right, up, down
    case wordForward = "word_forward"
    case wordBack = "word_back"
    case home, end
}

enum JumpDirection: String, Codable, CaseIterable, Equatable {
    case up, down
}

enum IndependentActionKind: String, Codable, CaseIterable, Equatable {
    case backspace
    case nextLine = "next_line"
    case insertQuotes = "insert_quotes"
    case toggleCapsLock = "toggle_caps_lock"
    /// RETIRED tombstone. The auto 中/英 "Smart Toggle" was removed because its
    /// switching was too unreliable, so its `builtin.switch_input_source` action
    /// is no longer offered (see BuiltinActions.swift) and the executor treats it
    /// as a no-op (see ActionExecutor.swift). The enum case itself is KEPT only so
    /// any pre-existing config that stored it inline still decodes — deleting the
    /// raw value would abort the whole config parse and silently drop every
    /// mapping. Do not reuse; do not re-expose.
    case switchInputSource = "switch_input_source"
    /// Does nothing (and swallows the key). Useful as a default action so a
    /// trigger only acts via its per-app rules and is inert everywhere else,
    /// or as a rule action to disable a key in specific apps.
    case noop
}

enum ModifierKey: String, Codable, CaseIterable, Equatable {
    case leftShift = "left_shift"
    case rightShift = "right_shift"
    case leftControl = "left_control"
    case rightControl = "right_control"
    case leftOption = "left_option"
    case rightOption = "right_option"
    case leftCommand = "left_command"
    case rightCommand = "right_command"
    case fn
}

// MARK: - ActionConfig (internally tagged by `kind`)

enum ActionConfig: Equatable {
    case directional(DirectionalActionKind)
    case jump(direction: JumpDirection, count: Int)
    case independent(IndependentActionKind)
    case inputSource(inputSourceID: String)
    case command(String)
    case keyCombo(targetKey: UInt16, withCtrl: Bool, withAlt: Bool, withCmd: Bool, withTargetShift: Bool)
    case openApp(bundleID: String, name: String)

    var kindTag: String {
        switch self {
        case .directional: return "directional"
        case .jump: return "jump"
        case .independent: return "independent"
        case .inputSource: return "input_source"
        case .command: return "command"
        case .keyCombo: return "key_combo"
        case .openApp: return "open_app"
        }
    }
}

extension ActionConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, action, direction, count
        case inputSourceID = "input_source_id"
        case command
        case targetKey = "target_key"
        case withCtrl = "with_ctrl"
        case withAlt = "with_alt"
        case withCmd = "with_cmd"
        case withTargetShift = "with_target_shift"
        case bundleID = "bundle_id"
        case appName = "app_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "directional":
            self = .directional(try c.decode(DirectionalActionKind.self, forKey: .action))
        case "jump":
            self = .jump(direction: try c.decode(JumpDirection.self, forKey: .direction),
                         count: try c.decode(Int.self, forKey: .count))
        case "independent":
            self = .independent(try c.decode(IndependentActionKind.self, forKey: .action))
        case "input_source":
            self = .inputSource(inputSourceID: try c.decode(String.self, forKey: .inputSourceID))
        case "command":
            self = .command(try c.decode(String.self, forKey: .command))
        case "key_combo":
            self = .keyCombo(
                targetKey: try c.decode(UInt16.self, forKey: .targetKey),
                withCtrl: try c.decodeIfPresent(Bool.self, forKey: .withCtrl) ?? false,
                withAlt: try c.decodeIfPresent(Bool.self, forKey: .withAlt) ?? false,
                withCmd: try c.decodeIfPresent(Bool.self, forKey: .withCmd) ?? false,
                withTargetShift: try c.decodeIfPresent(Bool.self, forKey: .withTargetShift) ?? false)
        case "open_app":
            self = .openApp(bundleID: try c.decode(String.self, forKey: .bundleID),
                            name: try c.decodeIfPresent(String.self, forKey: .appName) ?? "")
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c,
                debugDescription: "unknown action kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindTag, forKey: .kind)
        switch self {
        case .directional(let a):
            try c.encode(a, forKey: .action)
        case .jump(let dir, let count):
            try c.encode(dir, forKey: .direction)
            try c.encode(count, forKey: .count)
        case .independent(let a):
            try c.encode(a, forKey: .action)
        case .inputSource(let id):
            try c.encode(id, forKey: .inputSourceID)
        case .command(let cmd):
            try c.encode(cmd, forKey: .command)
        case .keyCombo(let key, let ctrl, let alt, let cmd, let shift):
            try c.encode(key, forKey: .targetKey)
            try c.encode(ctrl, forKey: .withCtrl)
            try c.encode(alt, forKey: .withAlt)
            try c.encode(cmd, forKey: .withCmd)
            try c.encode(shift, forKey: .withTargetShift)
        case .openApp(let bid, let name):
            try c.encode(bid, forKey: .bundleID)
            try c.encode(name, forKey: .appName)
        }
    }
}

// MARK: - Trigger (internally tagged by `kind`)

enum Trigger: Equatable, Hashable {
    case hyperPlusKey(key: UInt16, withShift: Bool)
    case singleTapHyper
    case doubleTapHyper
    case doubleTapModifier(ModifierKey)

    var kindTag: String {
        switch self {
        case .hyperPlusKey: return "hyper_plus_key"
        case .singleTapHyper: return "single_tap_hyper"
        case .doubleTapHyper: return "double_tap_hyper"
        case .doubleTapModifier: return "double_tap_modifier"
        }
    }

    var hyperPlusKey: (key: UInt16, withShift: Bool)? {
        if case let .hyperPlusKey(key, withShift) = self { return (key, withShift) }
        return nil
    }
}

extension Trigger: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, key
        case withShift = "with_shift"
        case modifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "hyper_plus_key":
            self = .hyperPlusKey(key: try c.decode(UInt16.self, forKey: .key),
                                 withShift: try c.decodeIfPresent(Bool.self, forKey: .withShift) ?? false)
        case "single_tap_hyper":
            self = .singleTapHyper
        case "double_tap_hyper":
            self = .doubleTapHyper
        case "double_tap_modifier":
            self = .doubleTapModifier(try c.decode(ModifierKey.self, forKey: .modifier))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c,
                debugDescription: "unknown trigger kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindTag, forKey: .kind)
        switch self {
        case .hyperPlusKey(let key, let withShift):
            try c.encode(key, forKey: .key)
            try c.encode(withShift, forKey: .withShift)
        case .singleTapHyper, .doubleTapHyper:
            break
        case .doubleTapModifier(let m):
            try c.encode(m, forKey: .modifier)
        }
    }
}

// MARK: - ActionMappingEntry (with legacy top-level key/with_shift support)

struct ActionMappingEntry: Equatable {
    var trigger: Trigger
    /// Preferred binding: references an Action in the library (built-in or custom).
    var actionId: String?
    /// Legacy / unmigrated: the action stored inline. Used when `actionId` is
    /// nil or unresolvable. Cleared on edit once an `actionId` is assigned.
    var inlineAction: ActionConfig?
    /// Per-app (conditional) overrides, evaluated in order before the default
    /// `actionId`/`inlineAction`. Empty for a plain global mapping. Serialized
    /// under the `bindings` key only when non-empty, so existing configs stay
    /// byte-identical until a per-app rule is added.
    var bindings: [MappingBinding]

    init(trigger: Trigger, actionId: String? = nil, inlineAction: ActionConfig? = nil, bindings: [MappingBinding] = []) {
        self.trigger = trigger
        self.actionId = actionId
        self.inlineAction = inlineAction
        self.bindings = bindings
    }
}

extension ActionMappingEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case trigger, key
        case withShift = "with_shift"
        case actionId = "action_id"
        case action
        case bindings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // New format: a nested `trigger:` object. Legacy format: top-level
        // `key`/`with_shift` (pre-trigger schema) → treat as a hyper_plus_key.
        if let t = try c.decodeIfPresent(Trigger.self, forKey: .trigger) {
            self.trigger = t
        } else if let key = try c.decodeIfPresent(UInt16.self, forKey: .key) {
            self.trigger = .hyperPlusKey(key: key,
                                         withShift: try c.decodeIfPresent(Bool.self, forKey: .withShift) ?? false)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .trigger, in: c,
                debugDescription: "action mapping entry missing both 'trigger' and legacy 'key' fields")
        }
        self.actionId = try c.decodeIfPresent(String.self, forKey: .actionId)
        self.inlineAction = try c.decodeIfPresent(ActionConfig.self, forKey: .action)
        self.bindings = try c.decodeIfPresent([MappingBinding].self, forKey: .bindings) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trigger, forKey: .trigger)
        try c.encodeIfPresent(actionId, forKey: .actionId)
        try c.encodeIfPresent(inlineAction, forKey: .action)
        if !bindings.isEmpty { try c.encode(bindings, forKey: .bindings) }
    }
}
