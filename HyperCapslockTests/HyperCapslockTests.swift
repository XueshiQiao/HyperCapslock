import XCTest
import Yams
@testable import HyperCapslock

@MainActor
final class HyperCapslockTests: XCTestCase {

    /// jsToMac and macToJs must be exact inverses, or a saved binding silently
    /// never fires (the invariant the Rust comment warns about).
    func testKeycodeTablesAreInverses() throws {
        for js in UInt16(0)...255 {
            if let mac = KeyCodes.jsToMac(js) {
                XCTAssertEqual(KeyCodes.macToJs(mac), js, "round-trip failed for JS keycode \(js)")
            }
        }
    }

    // MARK: Mapping (de)serialization

    func testMappingIdRoundTrip() throws {
        let entry = ActionMappingEntry(trigger: .hyperPlusKey(key: 72, withShift: false), actionId: "builtin.move_left")
        let yaml = try YAMLEncoder().encode([entry])
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        XCTAssertEqual(decoded, [entry])
        XCTAssertEqual(decoded.first?.actionId, "builtin.move_left")
        XCTAssertNil(decoded.first?.inlineAction)
    }

    func testMappingInlineRoundTrip() throws {
        let entry = ActionMappingEntry(trigger: .doubleTapHyper,
                                       inlineAction: .keyCombo(targetKey: 32, withCtrl: true, withAlt: true, withCmd: false, withTargetShift: false))
        let yaml = try YAMLEncoder().encode([entry])
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        XCTAssertEqual(decoded, [entry])
    }

    /// Legacy 2.0 bare-list (inline action, no action_id) must still decode.
    func testLegacyBareListDecodes() throws {
        let legacy = "- trigger:\n    kind: hyper_plus_key\n    key: 72\n    with_shift: false\n  action:\n    kind: directional\n    action: left\n"
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].trigger, .hyperPlusKey(key: 72, withShift: false))
        XCTAssertNil(decoded[0].actionId)
        XCTAssertEqual(decoded[0].inlineAction, .directional(.left))
    }

    func testCustomActionRoundTrip() throws {
        let action = Action(id: "ABC-123", name: "Open Calc", config: .command("open -a Calculator"), isBuiltin: false)
        let yaml = try YAMLEncoder().encode([action])
        let decoded = try YAMLDecoder().decode([Action].self, from: yaml)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "ABC-123")
        XCTAssertEqual(decoded[0].name, "Open Calc")
        XCTAssertEqual(decoded[0].config, .command("open -a Calculator"))
        XCTAssertFalse(decoded[0].isBuiltin)
    }

    // MARK: Built-in catalog (permanent-contract IDs)

    func testBuiltinIDsResolveToExpectedConfigs() throws {
        XCTAssertEqual(BuiltinActions.byID("builtin.move_left")?.config, .directional(.left))
        XCTAssertEqual(BuiltinActions.byID("builtin.jump_up_10")?.config, .jump(direction: .up, count: 10))
        XCTAssertEqual(BuiltinActions.byID("builtin.insert_quotes")?.config, .independent(.insertQuotes))
        XCTAssertTrue(BuiltinActions.isBuiltinID("builtin.move_left"))
        XCTAssertFalse(BuiltinActions.isBuiltinID("ABC-123"))
    }

    func testBuiltinMatchingMigratesInline() throws {
        // A legacy inline action that equals a built-in should match (so edit migrates to its id).
        XCTAssertEqual(BuiltinActions.matching(.directional(.right))?.id, "builtin.move_right")
        XCTAssertNil(BuiltinActions.matching(.command("whatever")))
    }

    // MARK: Resolution (id wins if resolvable, else inline, else nil)

    func testResolutionRules() throws {
        let reg = ActionsRegistry.shared
        reg.setCustom([Action(id: "cust-1", name: "X", config: .command("echo hi"), isBuiltin: false)])

        // id → built-in config
        XCTAssertEqual(reg.resolve(ActionMappingEntry(trigger: .doubleTapHyper, actionId: "builtin.move_up")),
                       .directional(.up))
        // id → custom config
        XCTAssertEqual(reg.resolve(ActionMappingEntry(trigger: .doubleTapHyper, actionId: "cust-1")),
                       .command("echo hi"))
        // dangling id but inline present → falls back to inline
        XCTAssertEqual(reg.resolve(ActionMappingEntry(trigger: .doubleTapHyper, actionId: "builtin.nope",
                                                      inlineAction: .independent(.backspace))),
                       .independent(.backspace))
        // neither → nil (invalid)
        XCTAssertNil(reg.resolve(ActionMappingEntry(trigger: .doubleTapHyper, actionId: "builtin.nope")))
        reg.setCustom([])
    }

    // MARK: Defaults bind to built-in ids

    func testDefaultMappingsUseBuiltinIDs() throws {
        let defaults = ConfigStore.defaultMappings()
        let h = defaults.first { $0.trigger == .hyperPlusKey(key: 72, withShift: false) }
        XCTAssertEqual(h?.actionId, "builtin.move_left")
        // ABC input-source default stays inline (machine-specific, not a built-in).
        let abc = defaults.first { $0.trigger == .hyperPlusKey(key: 188, withShift: false) }
        XCTAssertNil(abc?.actionId)
        if case .inputSource = abc?.inlineAction {} else { XCTFail("ABC default should be inline input_source") }
    }

    // MARK: Per-app scoped mappings (bindings)

    func testBindingsRoundTrip() throws {
        let entry = ActionMappingEntry(
            trigger: .hyperPlusKey(key: 72, withShift: false),
            actionId: "builtin.move_left",
            bindings: [
                MappingBinding(when: [.frontmostApp(include: ["com.apple.Safari", "com.google.Chrome"], exclude: [])],
                        actionId: "builtin.move_right"),
                MappingBinding(when: [.frontmostApp(include: [], exclude: ["com.apple.Terminal"])],
                        inlineAction: .command("echo hi")),
            ])
        let yaml = try YAMLEncoder().encode([entry])
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        XCTAssertEqual(decoded, [entry])
    }

    /// A mapping with no per-app rules must not emit a `bindings` key, so
    /// existing configs stay byte-identical to today's output.
    func testNoBindingsKeyWhenEmpty() throws {
        let entry = ActionMappingEntry(trigger: .hyperPlusKey(key: 72, withShift: false), actionId: "builtin.move_left")
        let yaml = try YAMLEncoder().encode([entry])
        XCTAssertFalse(yaml.contains("bindings"), "empty bindings should be omitted from YAML")
    }

    /// An unrecognized condition type decodes to `.unknown` (never throws) and
    /// is never satisfied (fail-closed).
    func testUnknownConditionFailsClosed() throws {
        let yaml = """
        - trigger: { kind: hyper_plus_key, key: 72, with_shift: false }
          action_id: builtin.move_left
          bindings:
            - when:
                - type: input_source
                  is: com.apple.keylayout.US
              action_id: builtin.move_right
        """
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        let cond = decoded.first?.bindings.first?.when.first
        XCTAssertEqual(cond, .unknown)
        XCTAssertFalse(cond?.isSatisfied(RuntimeContext(frontmostBundleID: "com.apple.Safari")) ?? true)
    }

    func testConditionMatchingIncludeExcludeCaseInsensitive() {
        let include = Condition.frontmostApp(include: ["com.apple.Safari"], exclude: [])
        XCTAssertTrue(include.isSatisfied(RuntimeContext(frontmostBundleID: "COM.APPLE.SAFARI")))
        XCTAssertFalse(include.isSatisfied(RuntimeContext(frontmostBundleID: "com.apple.Terminal")))
        XCTAssertFalse(include.isSatisfied(RuntimeContext(frontmostBundleID: nil)))

        let exclude = Condition.frontmostApp(include: [], exclude: ["com.apple.Terminal"])
        XCTAssertTrue(exclude.isSatisfied(RuntimeContext(frontmostBundleID: "com.apple.Safari")))
        XCTAssertFalse(exclude.isSatisfied(RuntimeContext(frontmostBundleID: "com.apple.Terminal")))

        let degenerate = Condition.frontmostApp(include: [], exclude: [])
        XCTAssertFalse(degenerate.isSatisfied(RuntimeContext(frontmostBundleID: "com.apple.Safari")))
    }

    func testBindingMatchesIsAndOverConditions() {
        let b = MappingBinding(when: [
            .frontmostApp(include: ["com.apple.Safari"], exclude: []),
            .frontmostApp(include: [], exclude: ["com.apple.Safari"]),  // contradicts the first
        ], actionId: "builtin.move_right")
        XCTAssertFalse(b.matches(RuntimeContext(frontmostBundleID: "com.apple.Safari")))
        XCTAssertFalse(MappingBinding(when: [], actionId: "x").matches(RuntimeContext(frontmostBundleID: "com.apple.Safari")))
    }

    func testEffectiveActionOrderFallbackAndNoOp() {
        let entry = ActionMappingEntry(
            trigger: .hyperPlusKey(key: 74, withShift: false),
            actionId: "builtin.move_down",
            bindings: [
                MappingBinding(when: [.frontmostApp(include: ["com.apple.Safari"], exclude: [])], actionId: "builtin.move_right"),
                MappingBinding(when: [.frontmostApp(include: ["com.googlecode.iterm2"], exclude: [])], actionId: "builtin.move_left"),
            ])
        // Safari → first matching binding wins.
        XCTAssertEqual(ActionExecutor.effectiveAction(entry, RuntimeContext(frontmostBundleID: "com.apple.Safari")), .directional(.right))
        // iTerm2 → second binding.
        XCTAssertEqual(ActionExecutor.effectiveAction(entry, RuntimeContext(frontmostBundleID: "com.googlecode.iterm2")), .directional(.left))
        // Finder (no binding matches) → default.
        XCTAssertEqual(ActionExecutor.effectiveAction(entry, RuntimeContext(frontmostBundleID: "com.apple.finder")), .directional(.down))

        // No default + no matching binding → nil (caller swallows as no-op).
        let scopedOnly = ActionMappingEntry(
            trigger: .hyperPlusKey(key: 74, withShift: false),
            bindings: [MappingBinding(when: [.frontmostApp(include: ["com.apple.Safari"], exclude: [])], actionId: "builtin.move_right")])
        XCTAssertNil(ActionExecutor.effectiveAction(scopedOnly, RuntimeContext(frontmostBundleID: "com.apple.finder")))
        XCTAssertEqual(ActionExecutor.effectiveAction(scopedOnly, RuntimeContext(frontmostBundleID: "com.apple.Safari")), .directional(.right))
    }
}
