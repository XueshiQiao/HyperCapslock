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

    /// Default mappings must survive a YAML render → decode round-trip unchanged.
    func testDefaultMappingsYAMLRoundTrip() throws {
        var defaults = ConfigStore.defaultMappings()
        ConfigStore.normalize(&defaults)
        let yaml = ConfigStore.renderYAML(defaults)
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        XCTAssertEqual(decoded, defaults)
    }

    /// The rendered YAML must carry the `# KeyName` comment for hyper+key entries.
    func testYAMLRenderContainsKeyNameComment() throws {
        let entries = [ActionMappingEntry(trigger: .hyperPlusKey(key: 87, withShift: false),
                                          action: .directional(.wordForward))]
        let yaml = ConfigStore.renderYAML(entries)
        XCTAssertTrue(yaml.contains("key: 87 # W"))
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        XCTAssertEqual(decoded, entries)
    }

    /// Legacy top-level `key`/`with_shift` must decode as a hyper_plus_key.
    func testLegacyYAMLDecodesAsHyperPlusKey() throws {
        let legacy = "- key: 72\n  with_shift: false\n  action:\n    kind: directional\n    action: left\n"
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].trigger, .hyperPlusKey(key: 72, withShift: false))
    }

    /// KeyCombo with modifiers round-trips through YAML.
    func testKeyComboRoundTrip() throws {
        let entry = ActionMappingEntry(trigger: .doubleTapHyper,
                                       action: .keyCombo(targetKey: 32, withCtrl: true, withAlt: true, withCmd: false, withTargetShift: false))
        let yaml = ConfigStore.renderYAML([entry])
        let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
        XCTAssertEqual(decoded, [entry])
    }

    /// Double-tap-modifier triggers for all nine modifiers round-trip.
    func testDoubleTapModifierRoundTrip() throws {
        for m in ModifierKey.allCases {
            let entry = ActionMappingEntry(trigger: .doubleTapModifier(m), action: .independent(.backspace))
            let yaml = ConfigStore.renderYAML([entry])
            let decoded = try YAMLDecoder().decode([ActionMappingEntry].self, from: yaml)
            XCTAssertEqual(decoded, [entry], "round-trip failed for modifier \(m)")
        }
    }
}
