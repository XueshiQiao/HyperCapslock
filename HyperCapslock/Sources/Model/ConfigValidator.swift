import Foundation
import AppKit
import Yams

/// Structured validation diagnostic emitted by `ConfigValidator`.
struct ValidationIssue: Codable, Equatable {
  enum Severity: String, Codable, Equatable {
    case error
    case warning
  }

  let severity: Severity
  let file: String
  let path: String
  let message: String
  var line: Int?
  var column: Int?

  init(
    severity: Severity,
    file: String,
    path: String,
    message: String,
    line: Int? = nil,
    column: Int? = nil
  ) {
    self.severity = severity
    self.file = file
    self.path = path
    self.message = message
    self.line = line
    self.column = column
  }

  init(severity: Severity, file: String, path: String, message: String, mark: Mark?) {
    self.init(
      severity: severity,
      file: file,
      path: path,
      message: message,
      line: mark?.line,
      column: mark?.column
    )
  }
}

/// Aggregated validation result across one or more YAML config files.
struct ValidationReport: Codable, Equatable {
  var issues: [ValidationIssue]

  init(issues: [ValidationIssue] = []) {
    self.issues = issues
  }

  var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
  var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }

  var isValid: Bool { errors.isEmpty }

  func isValid(strict: Bool) -> Bool {
    strict ? issues.isEmpty : errors.isEmpty
  }

  /// CLI exit code: `0` ok, `1` errors, `2` warnings under `--strict`.
  func exitCode(strict: Bool) -> Int32 {
    if !errors.isEmpty { return 1 }
    if strict && !warnings.isEmpty { return 2 }
    return 0
  }
}

/// Injectable host lookups so unit tests stay deterministic while production CLI / IPC
/// checks installed Carbon TIS input sources and macOS application bundle IDs.
struct ValidationEnvironment {
  var isInputSourceInstalled: ((String) -> Bool)?
  var isAppBundleInstalled: ((String) -> Bool)?

  static var live: ValidationEnvironment {
    ValidationEnvironment(
      isInputSourceInstalled: { id in
        InputSourceController.isSelectableSourceInstalled(id)
      },
      isAppBundleInstalled: { bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
      }
    )
  }

  static let offline = ValidationEnvironment(
    isInputSourceInstalled: nil,
    isAppBundleInstalled: nil
  )
}

/// Strict pre-flight YAML validator using Yams AST + model constraints.
///
/// Unlike `ConfigStore.load()` / `AppConfig.init(from:)` — which intentionally tolerate
/// or skip unknown/out-of-range entries at runtime so a bad edit never wipes a user's
/// config — `ConfigValidator` strictly flags every schema violation, reserved keycode,
/// orphaned `action_id`, out-of-range preference, or typo'd key before applying changes.
enum ConfigValidator {

  // MARK: - Public Entry Points

  static func validateDataDirectory(
    _ dataDirectory: URL,
    environment: ValidationEnvironment = .live
  ) -> ValidationReport {
    var allIssues: [ValidationIssue] = []
    let mappingsURL = dataDirectory.appendingPathComponent("action_mappings.yml")
    let appConfigURL = dataDirectory.appendingPathComponent("app_config.yml")

    if FileManager.default.fileExists(atPath: mappingsURL.path) {
      allIssues.append(contentsOf: validateMappingsFile(at: mappingsURL, environment: environment).issues)
    }
    if FileManager.default.fileExists(atPath: appConfigURL.path) {
      allIssues.append(contentsOf: validateAppConfigFile(at: appConfigURL, environment: environment).issues)
    }
    return ValidationReport(issues: allIssues)
  }

  static func validateMappingsFile(
    at url: URL,
    environment: ValidationEnvironment = .live
  ) -> ValidationReport {
    let label = url.path
    guard FileManager.default.fileExists(atPath: url.path) else {
      return ValidationReport(issues: [
        ValidationIssue(severity: .error, file: label, path: "$", message: "File not found: \(url.path)")
      ])
    }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return ValidationReport(issues: [
        ValidationIssue(severity: .error, file: label, path: "$", message: "Unable to read file: \(error.localizedDescription)")
      ])
    }
    guard let yaml = String(data: data, encoding: .utf8) else {
      return ValidationReport(issues: [
        ValidationIssue(severity: .error, file: label, path: "$", message: "File is not valid UTF-8 text")
      ])
    }
    return validateMappingsYAML(yaml, file: label, environment: environment)
  }

  static func validateAppConfigFile(
    at url: URL,
    environment: ValidationEnvironment = .live
  ) -> ValidationReport {
    let label = url.path
    guard FileManager.default.fileExists(atPath: url.path) else {
      return ValidationReport(issues: [
        ValidationIssue(severity: .error, file: label, path: "$", message: "File not found: \(url.path)")
      ])
    }
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return ValidationReport(issues: [
        ValidationIssue(severity: .error, file: label, path: "$", message: "Unable to read file: \(error.localizedDescription)")
      ])
    }
    guard let yaml = String(data: data, encoding: .utf8) else {
      return ValidationReport(issues: [
        ValidationIssue(severity: .error, file: label, path: "$", message: "File is not valid UTF-8 text")
      ])
    }
    return validateAppConfigYAML(yaml, file: label, environment: environment)
  }

  // MARK: - `action_mappings.yml` Validation

  static func validateMappingsYAML(
    _ yaml: String,
    file: String = "action_mappings.yml",
    environment: ValidationEnvironment = .live
  ) -> ValidationReport {
    if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return ValidationReport(issues: [
        ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "YAML file is empty; expected a mapping '{ actions, mappings }' or legacy sequence"
        )
      ])
    }

    let root: Node
    do {
      guard let composed = try Yams.compose(yaml: yaml) else {
        return ValidationReport(issues: [
          ValidationIssue(
            severity: .error,
            file: file,
            path: "$",
            message: "YAML document contains no root node; expected '{ actions, mappings }'"
          )
        ])
      }
      root = composed
    } catch {
      return ValidationReport(issues: [syntaxErrorIssue(error, file: file)])
    }

    var issues: [ValidationIssue] = []
    var declaredCustomIDs = Set<String>()
    var declaredCustomIDsLower: [String: String] = [:]

    switch root {
    case .sequence(let seq):
      validateMappingsSequence(
        seq,
        pathPrefix: "$",
        file: file,
        declaredCustomIDs: declaredCustomIDs,
        declaredCustomIDsLower: declaredCustomIDsLower,
        environment: environment,
        issues: &issues
      )

    case .mapping(let map):
      if map.isEmpty {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "Root YAML mapping is empty; expected 'mappings' (and optional 'actions')",
          mark: root.mark
        ))
        return ValidationReport(issues: issues)
      }

      let knownRootKeys: Set<String> = ["actions", "mappings"]
      var hasActionsOrMappings = false
      var actionsNode: Node?
      var mappingsNode: Node?

      for (kNode, vNode) in map {
        guard let key = scalarKeyString(kNode) else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "$",
            message: "Top-level YAML key must be a string",
            mark: kNode.mark
          ))
          continue
        }
        if !knownRootKeys.contains(key) {
          issues.append(ValidationIssue(
            severity: .warning,
            file: file,
            path: key,
            message: "Unknown top-level key '\(key)' in action_mappings.yml (check for typos)",
            mark: kNode.mark
          ))
        } else {
          hasActionsOrMappings = true
          if key == "actions" { actionsNode = vNode }
          if key == "mappings" { mappingsNode = vNode }
        }
      }

      if !hasActionsOrMappings {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "Root mapping must contain 'mappings' (or 'actions')",
          mark: root.mark
        ))
      }

      // Validate `actions` FIRST so `declaredCustomIDs` is populated for `mappings`.
      if let actionsNode {
        if case .sequence(let seq) = actionsNode {
          validateActionsSequence(
            seq,
            file: file,
            declaredCustomIDs: &declaredCustomIDs,
            declaredCustomIDsLower: &declaredCustomIDsLower,
            environment: environment,
            issues: &issues
          )
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "actions",
            message: "'actions' must be a YAML sequence (array)",
            mark: actionsNode.mark
          ))
        }
      }

      if let mappingsNode {
        if case .sequence(let seq) = mappingsNode {
          validateMappingsSequence(
            seq,
            pathPrefix: "mappings",
            file: file,
            declaredCustomIDs: declaredCustomIDs,
            declaredCustomIDsLower: declaredCustomIDsLower,
            environment: environment,
            issues: &issues
          )
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "mappings",
            message: "'mappings' must be a YAML sequence (array)",
            mark: mappingsNode.mark
          ))
        }
      }

    default:
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "$",
        message: "Root YAML value in action_mappings.yml must be a mapping '{ actions, mappings }' or a legacy sequence",
        mark: root.mark
      ))
    }

    return ValidationReport(issues: issues)
  }

  private static func validateActionsSequence(
    _ seq: Node.Sequence,
    file: String,
    declaredCustomIDs: inout Set<String>,
    declaredCustomIDsLower: inout [String: String],
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) {
    let knownKeys: Set<String> = ["id", "name", "action"]
    for (idx, elem) in seq.enumerated() {
      let itemPath = "actions[\(idx)]"
      guard case .mapping(let map) = elem else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: itemPath,
          message: "Custom action entry must be a YAML mapping '{ id, name, action }'",
          mark: elem.mark
        ))
        continue
      }

      let dict = extractMappingFields(map, path: itemPath, knownKeys: knownKeys, file: file, issues: &issues)

      // 1. id (required valid UUID, non-duplicate)
      if let idNode = dict["id"] {
        if let idStr = strictString(idNode) {
          let trimmed = idStr.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(itemPath).id",
              message: "Custom action 'id' cannot be empty",
              mark: idNode.mark
            ))
          } else {
            if BuiltinActions.isBuiltinID(idStr) || idStr.hasPrefix("builtin.") {
              issues.append(ValidationIssue(
                severity: .error,
                file: file,
                path: "\(itemPath).id",
                message: "Custom action 'id' ('\(idStr)') cannot use 'builtin.*' namespace; use a UUID",
                mark: idNode.mark
              ))
            } else if UUID(uuidString: idStr) == nil {
              issues.append(ValidationIssue(
                severity: .error,
                file: file,
                path: "\(itemPath).id",
                message: "Custom action 'id' must be a valid UUID string (got '\(idStr)')",
                mark: idNode.mark
              ))
            }

            let lower = idStr.lowercased()
            if declaredCustomIDs.contains(idStr) || declaredCustomIDsLower[lower] != nil {
              issues.append(ValidationIssue(
                severity: .error,
                file: file,
                path: "\(itemPath).id",
                message: "Duplicate custom action id '\(idStr)'",
                mark: idNode.mark
              ))
            } else {
              declaredCustomIDs.insert(idStr)
              declaredCustomIDsLower[lower] = idStr
            }
          }
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(itemPath).id",
            message: "Custom action 'id' must be a string UUID",
            mark: idNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(itemPath).id",
          message: "Custom action is missing required field 'id' (UUID)",
          mark: elem.mark
        ))
      }

      // 2. name (required non-empty string)
      if let nameNode = dict["name"] {
        if let nameStr = strictString(nameNode) {
          if nameStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(itemPath).name",
              message: "Custom action 'name' cannot be empty",
              mark: nameNode.mark
            ))
          }
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(itemPath).name",
            message: "Custom action 'name' must be a non-empty string",
            mark: nameNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(itemPath).name",
          message: "Custom action is missing required field 'name'",
          mark: elem.mark
        ))
      }

      // 3. action (required ActionConfig)
      if let actionNode = dict["action"] {
        validateActionConfig(actionNode, path: "\(itemPath).action", file: file, environment: environment, issues: &issues)
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(itemPath).action",
          message: "Custom action is missing required field 'action'",
          mark: elem.mark
        ))
      }
    }
  }

  private static func validateMappingsSequence(
    _ seq: Node.Sequence,
    pathPrefix: String,
    file: String,
    declaredCustomIDs: Set<String>,
    declaredCustomIDsLower: [String: String],
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) {
    let knownKeys: Set<String> = ["trigger", "key", "with_shift", "action_id", "action", "bindings"]
    var seenTriggers: [String: Int] = [:]

    for (idx, elem) in seq.enumerated() {
      let itemPath = pathPrefix == "$" ? "$[\(idx)]" : "\(pathPrefix)[\(idx)]"
      guard case .mapping(let map) = elem else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: itemPath,
          message: "Mapping entry must be a YAML mapping",
          mark: elem.mark
        ))
        continue
      }

      let dict = extractMappingFields(map, path: itemPath, knownKeys: knownKeys, file: file, issues: &issues)

      // 1. Trigger (nested `trigger:` or legacy top-level `key:` + `with_shift:`)
      if let triggerNode = dict["trigger"] {
        if let parsedTrigger = validateTrigger(triggerNode, path: "\(itemPath).trigger", file: file, issues: &issues) {
          let tid = triggerUniqueID(parsedTrigger)
          if let prevIdx = seenTriggers[tid] {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(itemPath).trigger",
              message: "Duplicate trigger '\(ConfigStore.triggerLabel(parsedTrigger))' (collides with entry [\(prevIdx)])",
              mark: triggerNode.mark
            ))
          } else {
            seenTriggers[tid] = idx
          }
        }
      } else if let legacyKeyNode = dict["key"] {
        if let parsedTrigger = validateLegacyTrigger(
          keyNode: legacyKeyNode,
          withShiftNode: dict["with_shift"],
          path: itemPath,
          file: file,
          issues: &issues
        ) {
          let tid = triggerUniqueID(parsedTrigger)
          if let prevIdx = seenTriggers[tid] {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(itemPath).key",
              message: "Duplicate trigger '\(ConfigStore.triggerLabel(parsedTrigger))' (collides with entry [\(prevIdx)])",
              mark: legacyKeyNode.mark
            ))
          } else {
            seenTriggers[tid] = idx
          }
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(itemPath).trigger",
          message: "Mapping entry is missing required field 'trigger'",
          mark: elem.mark
        ))
      }

      // 2. Action reference (`action_id` and/or `action`)
      validateActionTarget(
        actionIdNode: dict["action_id"],
        inlineActionNode: dict["action"],
        parentMark: elem.mark,
        path: itemPath,
        file: file,
        declaredCustomIDs: declaredCustomIDs,
        declaredCustomIDsLower: declaredCustomIDsLower,
        environment: environment,
        issues: &issues
      )

      // 3. Optional `bindings`
      if let bindingsNode = dict["bindings"] {
        validateBindings(
          bindingsNode,
          path: "\(itemPath).bindings",
          file: file,
          declaredCustomIDs: declaredCustomIDs,
          declaredCustomIDsLower: declaredCustomIDsLower,
          environment: environment,
          issues: &issues
        )
      }
    }
  }

  // MARK: - Trigger Validation

  private static func validateTrigger(
    _ node: Node,
    path: String,
    file: String,
    issues: inout [ValidationIssue]
  ) -> Trigger? {
    guard case .mapping(let map) = node else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "'trigger' must be a YAML mapping with a 'kind' field",
        mark: node.mark
      ))
      return nil
    }

    var rawFields: [String: Node] = [:]
    for (kNode, vNode) in map {
      if let k = scalarKeyString(kNode) { rawFields[k] = vNode }
    }

    guard let kindNode = rawFields["kind"] else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).kind",
        message: "'trigger' is missing required field 'kind'",
        mark: node.mark
      ))
      return nil
    }
    guard let kind = strictString(kindNode) else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).kind",
        message: "'trigger.kind' must be a string",
        mark: kindNode.mark
      ))
      return nil
    }

    switch kind {
    case "hyper_plus_key":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "key", "with_shift"], file: file, issues: &issues)
      var shift = false
      var shiftValid = true
      if let shiftNode = rawFields["with_shift"] {
        if let b = strictBool(shiftNode) {
          shift = b
        } else {
          shiftValid = false
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).with_shift",
            message: "'with_shift' must be a boolean (true or false)",
            mark: shiftNode.mark
          ))
        }
      }
      guard let keyNode = rawFields["key"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).key",
          message: "'hyper_plus_key' trigger is missing required integer field 'key' (JS keyCode)",
          mark: node.mark
        ))
        return nil
      }
      guard let keyCode = validateJSKeyCode(keyNode, path: "\(path).key", fieldLabel: "key", file: file, issues: &issues) else {
        return nil
      }
      return shiftValid ? .hyperPlusKey(key: keyCode, withShift: shift) : nil

    case "single_tap_hyper":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind"], file: file, issues: &issues)
      return .singleTapHyper

    case "double_tap_hyper":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind"], file: file, issues: &issues)
      return .doubleTapHyper

    case "double_tap_modifier":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "modifier"], file: file, issues: &issues)
      guard let modNode = rawFields["modifier"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).modifier",
          message: "'double_tap_modifier' trigger is missing required field 'modifier'",
          mark: node.mark
        ))
        return nil
      }
      guard let modRaw = strictString(modNode), let mod = ModifierKey(rawValue: modRaw) else {
        let validList = ModifierKey.allCases.map(\.rawValue).joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).modifier",
          message: "Invalid modifier '\(modNode.scalar?.string ?? "")'; expected one of: \(validList)",
          mark: modNode.mark
        ))
        return nil
      }
      return .doubleTapModifier(mod)

    default:
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).kind",
        message: "Unknown trigger kind '\(kind)'; expected one of: hyper_plus_key, single_tap_hyper, double_tap_hyper, double_tap_modifier",
        mark: kindNode.mark
      ))
      return nil
    }
  }

  private static func validateLegacyTrigger(
    keyNode: Node,
    withShiftNode: Node?,
    path: String,
    file: String,
    issues: inout [ValidationIssue]
  ) -> Trigger? {
    var shift = false
    var shiftValid = true
    if let shiftNode = withShiftNode {
      if let b = strictBool(shiftNode) {
        shift = b
      } else {
        shiftValid = false
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).with_shift",
          message: "'with_shift' must be a boolean (true or false)",
          mark: shiftNode.mark
        ))
      }
    }
    guard let keyCode = validateJSKeyCode(keyNode, path: "\(path).key", fieldLabel: "key", file: file, issues: &issues) else {
      return nil
    }
    return shiftValid ? .hyperPlusKey(key: keyCode, withShift: shift) : nil
  }

  private static func validateJSKeyCode(
    _ node: Node,
    path: String,
    fieldLabel: String,
    file: String,
    issues: inout [ValidationIssue]
  ) -> UInt16? {
    guard let rawInt = strictInt(node), rawInt >= 0, rawInt <= Int(UInt16.max) else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "'\(fieldLabel)' must be an integer JS keyCode",
        mark: node.mark
      ))
      return nil
    }
    let keyCode = UInt16(rawInt)
    if keyCode == 129 {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "JS keyCode 129 (F18) is reserved for HyperCapslock's internal CapsLock→F18 remap and cannot be used",
        mark: node.mark
      ))
      return nil
    }
    guard KeyCodes.jsToMac(keyCode) != nil else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "Unsupported or unmapped JS keyCode \(keyCode) (run 'cli list-keys' for valid keyCodes)",
        mark: node.mark
      ))
      return nil
    }
    return keyCode
  }

  // MARK: - Action Target & ActionConfig Validation

  private static func validateActionTarget(
    actionIdNode: Node?,
    inlineActionNode: Node?,
    parentMark: Mark?,
    path: String,
    file: String,
    declaredCustomIDs: Set<String>,
    declaredCustomIDsLower: [String: String],
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) {
    if actionIdNode == nil && inlineActionNode == nil {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "Entry must specify either 'action_id' or inline 'action'",
        mark: parentMark
      ))
      return
    }

    if let idNode = actionIdNode {
      if let idStr = strictString(idNode) {
        let trimmed = idStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).action_id",
            message: "'action_id' cannot be empty",
            mark: idNode.mark
          ))
        } else if idStr == "builtin.switch_input_source" {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).action_id",
            message: "'builtin.switch_input_source' has been retired; use inline 'action: { kind: input_source, input_source_id: <id> }' instead",
            mark: idNode.mark
          ))
        } else if !BuiltinActions.isBuiltinID(idStr) && !declaredCustomIDs.contains(idStr) {
          if let exactCase = declaredCustomIDsLower[idStr.lowercased()] {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(path).action_id",
              message: "Unresolved action_id '\(idStr)' (case mismatch with custom action '\(exactCase)')",
              mark: idNode.mark
            ))
          } else {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(path).action_id",
              message: "Unresolved/orphaned action_id '\(idStr)' (not in BuiltinActions or custom 'actions[]')",
              mark: idNode.mark
            ))
          }
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action_id",
          message: "'action_id' must be a string",
          mark: idNode.mark
        ))
      }
    }

    if let actionNode = inlineActionNode {
      validateActionConfig(actionNode, path: "\(path).action", file: file, environment: environment, issues: &issues)
    }
  }

  private static func validateActionConfig(
    _ node: Node,
    path: String,
    file: String,
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) {
    guard case .mapping(let map) = node else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "'action' must be a YAML mapping with a 'kind' field",
        mark: node.mark
      ))
      return
    }

    var rawFields: [String: Node] = [:]
    for (kNode, vNode) in map {
      if let k = scalarKeyString(kNode) { rawFields[k] = vNode }
    }

    guard let kindNode = rawFields["kind"] else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).kind",
        message: "'action' is missing required field 'kind'",
        mark: node.mark
      ))
      return
    }
    guard let kind = strictString(kindNode) else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).kind",
        message: "'action.kind' must be a string",
        mark: kindNode.mark
      ))
      return
    }

    switch kind {
    case "directional":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "action"], file: file, issues: &issues)
      guard let actNode = rawFields["action"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action",
          message: "'directional' action is missing required field 'action'",
          mark: node.mark
        ))
        return
      }
      guard let raw = strictString(actNode), DirectionalActionKind(rawValue: raw) != nil else {
        let valid = DirectionalActionKind.allCases.map(\.rawValue).joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action",
          message: "Invalid directional action '\(actNode.scalar?.string ?? "")'; expected one of: \(valid)",
          mark: actNode.mark
        ))
        return
      }

    case "jump":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "direction", "count"], file: file, issues: &issues)
      if let dirNode = rawFields["direction"] {
        if let raw = strictString(dirNode), JumpDirection(rawValue: raw) != nil {
          // valid
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).direction",
            message: "Invalid jump direction '\(dirNode.scalar?.string ?? "")'; expected 'up' or 'down'",
            mark: dirNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).direction",
          message: "'jump' action is missing required field 'direction'",
          mark: node.mark
        ))
      }

      if let countNode = rawFields["count"] {
        if let c = strictInt(countNode) {
          if c < 1 {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(path).count",
              message: "'jump.count' must be >= 1 (got \(c))",
              mark: countNode.mark
            ))
          }
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).count",
            message: "'jump.count' must be an integer >= 1",
            mark: countNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).count",
          message: "'jump' action is missing required integer field 'count'",
          mark: node.mark
        ))
      }

    case "independent":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "action"], file: file, issues: &issues)
      guard let actNode = rawFields["action"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action",
          message: "'independent' action is missing required field 'action'",
          mark: node.mark
        ))
        return
      }
      guard let raw = strictString(actNode) else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action",
          message: "'independent.action' must be a string",
          mark: actNode.mark
        ))
        return
      }
      if raw == IndependentActionKind.switchInputSource.rawValue {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action",
          message: "Independent action 'switch_input_source' is retired; use 'kind: input_source' with 'input_source_id' instead",
          mark: actNode.mark
        ))
        return
      }
      guard IndependentActionKind(rawValue: raw) != nil else {
        let activeValid = IndependentActionKind.allCases
          .filter { $0 != .switchInputSource }
          .map(\.rawValue)
          .joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).action",
          message: "Invalid independent action '\(raw)'; expected one of: \(activeValid)",
          mark: actNode.mark
        ))
        return
      }

    case "input_source":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "input_source_id"], file: file, issues: &issues)
      guard let idNode = rawFields["input_source_id"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).input_source_id",
          message: "'input_source' action is missing required field 'input_source_id'",
          mark: node.mark
        ))
        return
      }
      guard let srcID = strictString(idNode) else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).input_source_id",
          message: "'input_source_id' must be a non-empty string",
          mark: idNode.mark
        ))
        return
      }
      let trimmed = srcID.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).input_source_id",
          message: "'input_source_id' cannot be empty",
          mark: idNode.mark
        ))
      } else if let check = environment.isInputSourceInstalled, !check(trimmed) {
        issues.append(ValidationIssue(
          severity: .warning,
          file: file,
          path: "\(path).input_source_id",
          message: "Input source '\(trimmed)' is not currently installed or enabled in macOS (run 'cli list-input-sources')",
          mark: idNode.mark
        ))
      }

    case "command":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "command"], file: file, issues: &issues)
      guard let cmdNode = rawFields["command"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).command",
          message: "'command' action is missing required field 'command'",
          mark: node.mark
        ))
        return
      }
      guard let cmd = strictString(cmdNode) else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).command",
          message: "'command' must be a non-empty string",
          mark: cmdNode.mark
        ))
        return
      }
      if cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).command",
          message: "'command' cannot be empty",
          mark: cmdNode.mark
        ))
      }

    case "key_combo":
      _ = extractMappingFields(
        map,
        path: path,
        knownKeys: ["kind", "target_key", "with_ctrl", "with_alt", "with_cmd", "with_target_shift"],
        file: file,
        issues: &issues
      )
      if let tkNode = rawFields["target_key"] {
        _ = validateJSKeyCode(tkNode, path: "\(path).target_key", fieldLabel: "target_key", file: file, issues: &issues)
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).target_key",
          message: "'key_combo' action is missing required integer field 'target_key'",
          mark: node.mark
        ))
      }
      for boolKey in ["with_ctrl", "with_alt", "with_cmd", "with_target_shift"] {
        if let bNode = rawFields[boolKey], strictBool(bNode) == nil {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).\(boolKey)",
            message: "'\(boolKey)' must be a boolean (true or false)",
            mark: bNode.mark
          ))
        }
      }

    case "open_app":
      _ = extractMappingFields(
        map,
        path: path,
        knownKeys: ["kind", "bundle_id", "app_name", "hide_if_frontmost"],
        file: file,
        issues: &issues
      )
      if let bidNode = rawFields["bundle_id"] {
        if let bid = strictString(bidNode) {
          let trimmed = bid.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(path).bundle_id",
              message: "'bundle_id' cannot be empty",
              mark: bidNode.mark
            ))
          } else if let check = environment.isAppBundleInstalled, !check(trimmed) {
            issues.append(ValidationIssue(
              severity: .warning,
              file: file,
              path: "\(path).bundle_id",
              message: "Application with bundle_id '\(trimmed)' was not found on this Mac",
              mark: bidNode.mark
            ))
          }
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(path).bundle_id",
            message: "'bundle_id' must be a non-empty string",
            mark: bidNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).bundle_id",
          message: "'open_app' action is missing required field 'bundle_id'",
          mark: node.mark
        ))
      }
      if let nameNode = rawFields["app_name"], strictString(nameNode) == nil {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).app_name",
          message: "'app_name' must be a string",
          mark: nameNode.mark
        ))
      }
      if let hideNode = rawFields["hide_if_frontmost"], strictBool(hideNode) == nil {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).hide_if_frontmost",
          message: "'hide_if_frontmost' must be a boolean (true or false)",
          mark: hideNode.mark
        ))
      }

    case "hold_modifier":
      _ = extractMappingFields(map, path: path, knownKeys: ["kind", "modifier"], file: file, issues: &issues)
      guard let modNode = rawFields["modifier"] else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).modifier",
          message: "'hold_modifier' action is missing required field 'modifier'",
          mark: node.mark
        ))
        return
      }
      guard let raw = strictString(modNode), let mod = ModifierKey(rawValue: raw) else {
        let supported = ModifierKey.allCases.filter { $0 != .fn }.map(\.rawValue).joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).modifier",
          message: "Invalid hold_modifier '\(modNode.scalar?.string ?? "")'; expected one of: \(supported)",
          mark: modNode.mark
        ))
        return
      }
      if mod == .fn {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(path).modifier",
          message: "'hold_modifier' does not support 'fn' (synthesizing Fn hold is unsupported on macOS)",
          mark: modNode.mark
        ))
      }

    default:
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).kind",
        message: "Unknown action kind '\(kind)'; expected one of: directional, jump, independent, input_source, command, key_combo, open_app, hold_modifier",
        mark: kindNode.mark
      ))
    }
  }

  // MARK: - Bindings Validation

  private static func validateBindings(
    _ node: Node,
    path: String,
    file: String,
    declaredCustomIDs: Set<String>,
    declaredCustomIDsLower: [String: String],
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) {
    guard case .sequence(let seq) = node else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "'bindings' must be a YAML sequence (array)",
        mark: node.mark
      ))
      return
    }

    let knownBindingKeys: Set<String> = ["when", "action_id", "action"]
    for (idx, elem) in seq.enumerated() {
      let bPath = "\(path)[\(idx)]"
      guard case .mapping(let map) = elem else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: bPath,
          message: "Binding entry must be a YAML mapping '{ when, action_id | action }'",
          mark: elem.mark
        ))
        continue
      }

      let dict = extractMappingFields(map, path: bPath, knownKeys: knownBindingKeys, file: file, issues: &issues)

      if let whenNode = dict["when"] {
        if case .sequence(let whenSeq) = whenNode {
          if whenSeq.isEmpty {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(bPath).when",
              message: "'when' cannot be empty; each binding must specify at least one condition",
              mark: whenNode.mark
            ))
          } else {
            for (cIdx, condElem) in whenSeq.enumerated() {
              validateCondition(
                condElem,
                path: "\(bPath).when[\(cIdx)]",
                file: file,
                environment: environment,
                issues: &issues
              )
            }
          }
        } else {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "\(bPath).when",
            message: "'when' must be a non-empty YAML sequence of conditions",
            mark: whenNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "\(bPath).when",
          message: "Binding is missing required field 'when'",
          mark: elem.mark
        ))
      }

      validateActionTarget(
        actionIdNode: dict["action_id"],
        inlineActionNode: dict["action"],
        parentMark: elem.mark,
        path: bPath,
        file: file,
        declaredCustomIDs: declaredCustomIDs,
        declaredCustomIDsLower: declaredCustomIDsLower,
        environment: environment,
        issues: &issues
      )
    }
  }

  private static func validateCondition(
    _ node: Node,
    path: String,
    file: String,
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) {
    guard case .mapping(let map) = node else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "Condition must be a YAML mapping with 'type: frontmost_app'",
        mark: node.mark
      ))
      return
    }

    var rawFields: [String: Node] = [:]
    for (kNode, vNode) in map {
      if let k = scalarKeyString(kNode) { rawFields[k] = vNode }
    }

    guard let typeNode = rawFields["type"], let typeStr = strictString(typeNode) else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).type",
        message: "Condition is missing required string field 'type'",
        mark: node.mark
      ))
      return
    }

    guard typeStr == "frontmost_app" else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: "\(path).type",
        message: "Unknown condition type '\(typeStr)'; expected 'frontmost_app'",
        mark: typeNode.mark
      ))
      return
    }

    _ = extractMappingFields(map, path: path, knownKeys: ["type", "include", "exclude"], file: file, issues: &issues)

    let includeIDs = validateBundleIDList(rawFields["include"], path: "\(path).include", file: file, environment: environment, issues: &issues)
    let excludeIDs = validateBundleIDList(rawFields["exclude"], path: "\(path).exclude", file: file, environment: environment, issues: &issues)

    if includeIDs.isEmpty && excludeIDs.isEmpty {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "'frontmost_app' condition must specify at least one bundle ID in 'include' or 'exclude'",
        mark: node.mark
      ))
    }
  }

  private static func validateBundleIDList(
    _ node: Node?,
    path: String,
    file: String,
    environment: ValidationEnvironment,
    issues: inout [ValidationIssue]
  ) -> [String] {
    guard let node else { return [] }
    guard case .sequence(let seq) = node else {
      issues.append(ValidationIssue(
        severity: .error,
        file: file,
        path: path,
        message: "Expected a YAML sequence of bundle ID strings",
        mark: node.mark
      ))
      return []
    }
    var out: [String] = []
    for (idx, elem) in seq.enumerated() {
      let elemPath = "\(path)[\(idx)]"
      guard let bid = strictString(elem) else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: elemPath,
          message: "Bundle ID must be a non-empty string",
          mark: elem.mark
        ))
        continue
      }
      let trimmed = bid.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: elemPath,
          message: "Bundle ID cannot be empty",
          mark: elem.mark
        ))
        continue
      }
      out.append(trimmed)
      if let check = environment.isAppBundleInstalled, !check(trimmed) {
        issues.append(ValidationIssue(
          severity: .warning,
          file: file,
          path: elemPath,
          message: "Application with bundle_id '\(trimmed)' was not found on this Mac",
          mark: elem.mark
        ))
      }
    }
    return out
  }

  // MARK: - `app_config.yml` Validation

  static func validateAppConfigYAML(
    _ yaml: String,
    file: String = "app_config.yml",
    environment: ValidationEnvironment = .live
  ) -> ValidationReport {
    let _ = environment
    if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return ValidationReport(issues: [
        ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "app_config.yml is empty; expected a YAML mapping"
        )
      ])
    }

    let root: Node
    do {
      guard let composed = try Yams.compose(yaml: yaml) else {
        return ValidationReport(issues: [
          ValidationIssue(
            severity: .error,
            file: file,
            path: "$",
            message: "app_config.yml contains no root YAML mapping"
          )
        ])
      }
      root = composed
    } catch {
      return ValidationReport(issues: [syntaxErrorIssue(error, file: file)])
    }

    guard case .mapping(let map) = root else {
      return ValidationReport(issues: [
        ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "Root YAML value in app_config.yml must be a mapping",
          mark: root.mark
        )
      ])
    }

    var issues: [ValidationIssue] = []
    let knownKeys: Set<String> = [
      "hide_dock_icon",
      "show_hud",
      "hud_duration_ms",
      "double_tap_window_ms",
      "theme_mode",
      "cjkv_fix_strategy",
      "broadcast_caps_hold_for_anydrag",
      "mappings_view_style",
      "stats_show_inline",
      "show_window_on_launch",
      "analytics_enabled",
      "key_remaps",
    ]

    let dict = extractMappingFields(map, path: "$", knownKeys: knownKeys, file: file, issues: &issues)

    // Booleans
    let boolKeys = [
      "hide_dock_icon",
      "show_hud",
      "broadcast_caps_hold_for_anydrag",
      "stats_show_inline",
      "show_window_on_launch",
      "analytics_enabled",
    ]
    for key in boolKeys {
      if let node = dict[key], strictBool(node) == nil {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: key,
          message: "'\(key)' must be a boolean (true or false)",
          mark: node.mark
        ))
      }
    }

    // Ranges
    if let hudNode = dict["hud_duration_ms"] {
      if let val = strictInt(hudNode) {
        if !(300...6000).contains(val) {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "hud_duration_ms",
            message: "'hud_duration_ms' must be between 300 and 6000 (got \(val))",
            mark: hudNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "hud_duration_ms",
          message: "'hud_duration_ms' must be an integer between 300 and 6000",
          mark: hudNode.mark
        ))
      }
    }

    if let dtwNode = dict["double_tap_window_ms"] {
      if let val = strictInt(dtwNode) {
        if !(100...500).contains(val) {
          issues.append(ValidationIssue(
            severity: .error,
            file: file,
            path: "double_tap_window_ms",
            message: "'double_tap_window_ms' must be between 100 and 500 (got \(val))",
            mark: dtwNode.mark
          ))
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "double_tap_window_ms",
          message: "'double_tap_window_ms' must be an integer between 100 and 500",
          mark: dtwNode.mark
        ))
      }
    }

    // Enums
    if let themeNode = dict["theme_mode"] {
      if let s = strictString(themeNode), ThemeMode(rawValue: s) != nil {
        // valid
      } else {
        let valid = ThemeMode.allCases.map(\.rawValue).joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "theme_mode",
          message: "Invalid 'theme_mode' value '\(themeNode.scalar?.string ?? "")'; expected one of: \(valid)",
          mark: themeNode.mark
        ))
      }
    }

    if let cjkvNode = dict["cjkv_fix_strategy"] {
      if let s = strictString(cjkvNode), CJKVFixStrategy(rawValue: s) != nil {
        // valid
      } else {
        let valid = CJKVFixStrategy.allCases.map(\.rawValue).joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "cjkv_fix_strategy",
          message: "Invalid 'cjkv_fix_strategy' value '\(cjkvNode.scalar?.string ?? "")'; expected one of: \(valid)",
          mark: cjkvNode.mark
        ))
      }
    }

    if let styleNode = dict["mappings_view_style"] {
      if let s = strictString(styleNode), MappingsViewStyle(rawValue: s) != nil {
        // valid
      } else {
        let valid = MappingsViewStyle.allCases.map(\.rawValue).joined(separator: ", ")
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "mappings_view_style",
          message: "Invalid 'mappings_view_style' value '\(styleNode.scalar?.string ?? "")'; expected one of: \(valid)",
          mark: styleNode.mark
        ))
      }
    }

    // key_remaps
    if let remapsNode = dict["key_remaps"] {
      if case .sequence(let seq) = remapsNode {
        var seenSources = Set<KeyRemapSource>()
        for (idx, elem) in seq.enumerated() {
          let rPath = "key_remaps[\(idx)]"
          guard case .mapping(let rMap) = elem else {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: rPath,
              message: "Key remap entry must be a YAML mapping '{ source, destination }'",
              mark: elem.mark
            ))
            continue
          }
          let rDict = extractMappingFields(rMap, path: rPath, knownKeys: ["source", "destination"], file: file, issues: &issues)
          if let srcNode = rDict["source"] {
            if let s = strictString(srcNode), let src = KeyRemapSource(rawValue: s) {
              if !seenSources.insert(src).inserted {
                issues.append(ValidationIssue(
                  severity: .error,
                  file: file,
                  path: "\(rPath).source",
                  message: "Duplicate key_remaps source '\(src.rawValue)'",
                  mark: srcNode.mark
                ))
              }
            } else {
              let valid = KeyRemapSource.allCases.map(\.rawValue).joined(separator: ", ")
              issues.append(ValidationIssue(
                severity: .error,
                file: file,
                path: "\(rPath).source",
                message: "Invalid key_remaps source '\(srcNode.scalar?.string ?? "")'; expected one of: \(valid)",
                mark: srcNode.mark
              ))
            }
          } else {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(rPath).source",
              message: "Key remap is missing required field 'source'",
              mark: elem.mark
            ))
          }

          if let dstNode = rDict["destination"] {
            if let d = strictString(dstNode) {
              if d.lowercased() == "f18" {
                issues.append(ValidationIssue(
                  severity: .error,
                  file: file,
                  path: "\(rPath).destination",
                  message: "'f18' is reserved for HyperCapslock's internal CapsLock→F18 remap; choose one of: \(KeyRemapTarget.allCases.map(\.rawValue).joined(separator: ", "))",
                  mark: dstNode.mark
                ))
              } else if KeyRemapTarget(rawValue: d) == nil {
                let valid = KeyRemapTarget.allCases.map(\.rawValue).joined(separator: ", ")
                issues.append(ValidationIssue(
                  severity: .error,
                  file: file,
                  path: "\(rPath).destination",
                  message: "Invalid key_remaps destination '\(d)'; expected one of: \(valid)",
                  mark: dstNode.mark
                ))
              }
            } else {
              issues.append(ValidationIssue(
                severity: .error,
                file: file,
                path: "\(rPath).destination",
                message: "'destination' must be a string function key (f13–f17, f19)",
                mark: dstNode.mark
              ))
            }
          } else {
            issues.append(ValidationIssue(
              severity: .error,
              file: file,
              path: "\(rPath).destination",
              message: "Key remap is missing required field 'destination'",
              mark: elem.mark
            ))
          }
        }
      } else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: "key_remaps",
          message: "'key_remaps' must be a YAML sequence (array)",
          mark: remapsNode.mark
        ))
      }
    }

    return ValidationReport(issues: issues)
  }

  // MARK: - AST Helpers

  private static func extractMappingFields(
    _ map: Node.Mapping,
    path: String,
    knownKeys: Set<String>,
    file: String,
    issues: inout [ValidationIssue]
  ) -> [String: Node] {
    var out: [String: Node] = [:]
    for (kNode, vNode) in map {
      guard let k = scalarKeyString(kNode) else {
        issues.append(ValidationIssue(
          severity: .error,
          file: file,
          path: path,
          message: "Mapping key must be a string",
          mark: kNode.mark
        ))
        continue
      }
      if !knownKeys.contains(k) {
        let keyPath = path == "$" ? k : "\(path).\(k)"
        issues.append(ValidationIssue(
          severity: .warning,
          file: file,
          path: keyPath,
          message: "Unknown key '\(k)' (check for typos; allowed keys: \(knownKeys.sorted().joined(separator: ", ")))",
          mark: kNode.mark
        ))
      }
      out[k] = vNode
    }
    return out
  }

  private static func scalarKeyString(_ node: Node) -> String? {
    guard case .scalar(let s) = node, node.tag != Tag(.null) else { return nil }
    return s.string
  }

  private static func strictBool(_ node: Node) -> Bool? {
    guard case .scalar(let s) = node, node.tag == Tag(.bool) else { return nil }
    return Bool.construct(from: s)
  }

  private static func strictInt(_ node: Node) -> Int? {
    guard case .scalar(let s) = node, node.tag == Tag(.int) else { return nil }
    return Int.construct(from: s)
  }

  private static func strictString(_ node: Node) -> String? {
    guard case .scalar(let s) = node else { return nil }
    let tag = node.tag
    if tag == Tag(.null) { return nil }
    if (tag == Tag(.bool) || tag == Tag(.int) || tag == Tag(.float)) && s.style == .plain {
      return nil
    }
    return s.string
  }

  private static func syntaxErrorIssue(_ error: Error, file: String) -> ValidationIssue {
    if let yamlError = error as? YamlError {
      switch yamlError {
      case let .scanner(ctx, problem, mark, _),
           let .parser(ctx, problem, mark, _),
           let .composer(ctx, problem, mark, _):
        let ctxDesc = ctx.map { " (\($0.text))" } ?? ""
        return ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "YAML syntax error at line \(mark.line), column \(mark.column): \(problem)\(ctxDesc)",
          line: mark.line,
          column: mark.column
        )
      case let .duplicatedKeysInMapping(duplicates, _):
        let firstKey = duplicates.keys.first?.scalar?.string ?? "unknown"
        let mark = duplicates.values.first?.last?.mark
        return ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "Duplicate key '\(firstKey)' in YAML mapping",
          line: mark?.line,
          column: mark?.column
        )
      case let .reader(problem, offset, _, _):
        let loc = offset.map { " at offset \($0)" } ?? ""
        return ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "YAML reader error\(loc): \(problem)"
        )
      default:
        return ValidationIssue(
          severity: .error,
          file: file,
          path: "$",
          message: "YAML error: \(yamlError)"
        )
      }
    }
    return ValidationIssue(
      severity: .error,
      file: file,
      path: "$",
      message: "YAML parse error: \(error.localizedDescription)"
    )
  }
}
