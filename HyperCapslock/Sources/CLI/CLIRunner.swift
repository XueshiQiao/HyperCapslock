import Foundation

/// Pre-`NSApplication` command-line interface for AI agents, scripts, and power users.
///
/// Invoked from `main.swift` whenever the first argument is `cli`, `--help`, or `-h`,
/// exiting before `NSApplication.shared` is touched (zero Dock icon, zero menu bar UI).
enum CLIRunner {

  typealias ReloadRequester = (
    _ dataDir: URL,
    _ backedUpMappingsSHA256: String?,
    _ backedUpAppConfigSHA256: String?,
    _ timeout: TimeInterval
  ) -> ReloadIPC.ReloadAck?

  typealias Pinger = (_ dataDir: URL, _ timeout: TimeInterval) -> ReloadIPC.PongResponse?

  static func shouldHandle(arguments: [String]) -> Bool {
    guard arguments.count > 1 else { return false }
    let first = arguments[1]
    return first == "cli" || first == "--help" || first == "-h"
  }

  static func run(arguments: [String]) -> Int32 {
    var outText = ""
    var errText = ""
    let code = execute(
      arguments: arguments,
      writeStdout: { outText.append($0) },
      writeStderr: { errText.append($0) }
    )
    if !outText.isEmpty {
      FileHandle.standardOutput.write(Data(outText.utf8))
    }
    if !errText.isEmpty {
      FileHandle.standardError.write(Data(errText.utf8))
    }
    return code
  }

  // MARK: - Testable Execution Core

  static func execute(
    arguments: [String],
    defaultDataDirectory: URL? = nil,
    skillDirectory: URL? = nil,
    executablePath: String? = nil,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    validationEnvironment: ValidationEnvironment = .live,
    pinger: Pinger = { dir, timeout in ReloadIPC.ping(dataDirectory: dir, timeout: timeout) },
    reloadRequester: ReloadRequester = { dir, mHash, aHash, timeout in
      ReloadIPC.requestReload(
        dataDirectory: dir,
        backedUpMappingsSHA256: mHash,
        backedUpAppConfigSHA256: aHash,
        timeout: timeout
      )
    },
    writeStdout: (String) -> Void,
    writeStderr: (String) -> Void
  ) -> Int32 {
    var tokens = arguments
    if tokens.first == "cli" {
      tokens.removeFirst()
    }

    // Extract global flags `--json` and `--data-dir <dir>` anywhere in `tokens`.
    var jsonMode = false
    var customDataDir: URL?
    var filtered: [String] = []
    var i = 0
    while i < tokens.count {
      let arg = tokens[i]
      if arg == "--json" {
        jsonMode = true
        i += 1
      } else if arg == "--data-dir" {
        guard i + 1 < tokens.count else {
          return emitError("Missing value for --data-dir", json: jsonMode, stdout: writeStdout, stderr: writeStderr)
        }
        let expanded = NSString(string: tokens[i + 1]).expandingTildeInPath
        customDataDir = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        i += 2
      } else if arg.hasPrefix("--data-dir=") {
        let val = String(arg.dropFirst("--data-dir=".count))
        let expanded = NSString(string: val).expandingTildeInPath
        customDataDir = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        i += 1
      } else {
        filtered.append(arg)
        i += 1
      }
    }

    let dataDir = (customDataDir ?? defaultDataDirectory ?? AppEnvironment.appSupportDirectory).standardizedFileURL

    guard let subcommand = filtered.first else {
      writeStdout(usageText() + "\n")
      return 0
    }

    if subcommand == "--help" || subcommand == "-h" || subcommand == "help" {
      writeStdout(usageText() + "\n")
      return 0
    }

    let subArgs = Array(filtered.dropFirst())
    if subArgs.contains("--help") || subArgs.contains("-h") {
      writeStdout(usageText(for: subcommand) + "\n")
      return 0
    }

    switch subcommand {
    case "info":
      return handleInfo(
        dataDir: dataDir,
        skillDir: skillDirectory,
        exePath: executablePath,
        json: jsonMode,
        pinger: pinger,
        stdout: writeStdout
      )

    case "list-keys":
      return handleListKeys(json: jsonMode, stdout: writeStdout)

    case "list-builtins":
      return handleListBuiltins(json: jsonMode, stdout: writeStdout)

    case "list-input-sources":
      return handleListInputSources(json: jsonMode, stdout: writeStdout)

    case "validate":
      return handleValidate(
        args: subArgs,
        dataDir: dataDir,
        env: validationEnvironment,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    case "apply":
      return handleApply(
        args: subArgs,
        dataDir: dataDir,
        env: validationEnvironment,
        reloadRequester: reloadRequester,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    case "reload":
      return handleReload(
        args: subArgs,
        dataDir: dataDir,
        env: validationEnvironment,
        reloadRequester: reloadRequester,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    case "backups":
      return handleBackups(
        args: subArgs,
        dataDir: dataDir,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    case "rollback":
      return handleRollback(
        args: subArgs,
        dataDir: dataDir,
        env: validationEnvironment,
        reloadRequester: reloadRequester,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    case "install-skill":
      return handleInstallSkill(
        args: subArgs,
        skillDir: skillDirectory,
        homeDir: homeDirectory,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    case "prompt":
      return handlePrompt(
        args: subArgs,
        dataDir: dataDir,
        skillDir: skillDirectory,
        exePath: executablePath,
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )

    default:
      return emitError(
        "Unknown subcommand '\(subcommand)'. Run 'HyperCapslock cli --help' for usage.",
        json: jsonMode,
        stdout: writeStdout,
        stderr: writeStderr
      )
    }
  }

  // MARK: - Subcommands

  private struct InfoOutput: Codable {
    struct FileState: Codable {
      let path: String
      let exists: Bool
    }
    struct RunningInstance: Codable {
      let running: Bool
      var pid: Int32?
      var status: String?
      var mappingsCount: Int?
      var customActionsCount: Int?
    }
    let version: String
    let build: String
    let bundleId: String
    let executablePath: String
    let dataDir: String
    let mappingsFile: FileState
    let appConfigFile: FileState
    let backupsDir: String
    let backupCount: Int
    let bundledSkillDir: String
    let skillPathEn: String
    let skillPathZh: String
    let runningInstance: RunningInstance
  }

  private static func handleInfo(
    dataDir: URL,
    skillDir: URL?,
    exePath: String?,
    json: Bool,
    pinger: Pinger,
    stdout: (String) -> Void
  ) -> Int32 {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    let bundleId = Bundle.main.bundleIdentifier ?? "me.xueshi.hypercapslock"
    let resolvedExe = exePath ?? SkillPromptBuilder.resolveExecutablePath()
    let resolvedSkillDir = (skillDir ?? SkillPromptBuilder.resolveBundledSkillDirectory()).standardizedFileURL
    let mappingsURL = dataDir.appendingPathComponent("action_mappings.yml")
    let appConfigURL = dataDir.appendingPathComponent("app_config.yml")
    let backupManager = ConfigBackupManager(dataDirectory: dataDir)
    let backups = backupManager.listBackups()
    let pong = pinger(dataDir, 0.35)

    let running: InfoOutput.RunningInstance = {
      if let pong {
        return .init(
          running: true,
          pid: pong.pid,
          status: pong.status,
          mappingsCount: pong.mappingsCount,
          customActionsCount: pong.customActionsCount
        )
      }
      return .init(running: false)
    }()

    let info = InfoOutput(
      version: version,
      build: build,
      bundleId: bundleId,
      executablePath: resolvedExe,
      dataDir: dataDir.path,
      mappingsFile: .init(path: mappingsURL.path, exists: FileManager.default.fileExists(atPath: mappingsURL.path)),
      appConfigFile: .init(path: appConfigURL.path, exists: FileManager.default.fileExists(atPath: appConfigURL.path)),
      backupsDir: backupManager.backupsDirectory.path,
      backupCount: backups.count,
      bundledSkillDir: resolvedSkillDir.path,
      skillPathEn: resolvedSkillDir.appendingPathComponent("SKILL.md").path,
      skillPathZh: resolvedSkillDir.appendingPathComponent("SKILL.zh.md").path,
      runningInstance: running
    )

    if json {
      stdout(encodeJSON(info) + "\n")
    } else {
      var lines: [String] = [
        "HyperCapslock v\(info.version) (\(info.build)) [\(info.bundleId)]",
        "Executable:      \(info.executablePath)",
        "Data directory:  \(info.dataDir)",
        "Mappings file:   \(info.mappingsFile.path) (\(info.mappingsFile.exists ? "present" : "missing"))",
        "App config file: \(info.appConfigFile.path) (\(info.appConfigFile.exists ? "present" : "missing"))",
        "Backups dir:     \(info.backupsDir) (\(info.backupCount) backup(s))",
        "Skill (EN):      \(info.skillPathEn)",
        "Skill (ZH):      \(info.skillPathZh)",
      ]
      if let pid = info.runningInstance.pid {
        lines.append("Live instance:   running (pid=\(pid), status=\(info.runningInstance.status ?? "unknown"), mappings=\(info.runningInstance.mappingsCount ?? 0), customActions=\(info.runningInstance.customActionsCount ?? 0))")
      } else {
        lines.append("Live instance:   not running for this data directory")
      }
      stdout(lines.joined(separator: "\n") + "\n")
    }
    return 0
  }

  private struct KeyCatalogOutput: Codable {
    struct KeyEntry: Codable {
      let jsKeyCode: UInt16
      let macVirtualKeyCode: UInt16
      let macHex: String
      let name: String
      let category: String
    }
    struct ReservedKey: Codable {
      let jsKeyCode: UInt16
      let macHex: String
      let name: String
      let reason: String
    }
    struct ModifierEntry: Codable {
      let id: String
      let supportsDoubleTapTrigger: Bool
      let supportsHoldModifierAction: Bool
    }
    let keys: [KeyEntry]
    let reservedKeys: [ReservedKey]
    let modifiers: [ModifierEntry]
    let keyRemapSources: [String]
    let keyRemapTargets: [String]
  }

  private static func handleListKeys(json: Bool, stdout: (String) -> Void) -> Int32 {
    func category(for js: UInt16) -> String {
      switch js {
      case 65...90: return "letter"
      case 48...57: return "digit"
      case 112...135: return "function"
      case 33...40: return "navigation"
      case 8, 9, 13, 27, 32, 46: return "editing_control"
      default: return "punctuation"
      }
    }

    var entries: [KeyCatalogOutput.KeyEntry] = []
    for js in UInt16(0)...255 {
      if let mac = KeyCodes.jsToMac(js) {
        entries.append(.init(
          jsKeyCode: js,
          macVirtualKeyCode: mac,
          macHex: String(format: "0x%02X", mac),
          name: KeyCodes.name(js),
          category: category(for: js)
        ))
      }
    }

    let catalog = KeyCatalogOutput(
      keys: entries,
      reservedKeys: [
        .init(jsKeyCode: 129, macHex: "0x4F", name: "F18", reason: "Reserved internal CapsLock→F18 remap")
      ],
      modifiers: ModifierKey.allCases.map { m in
        .init(
          id: m.rawValue,
          supportsDoubleTapTrigger: true,
          supportsHoldModifierAction: m != .fn
        )
      },
      keyRemapSources: KeyRemapSource.allCases.map(\.rawValue),
      keyRemapTargets: KeyRemapTarget.allCases.map(\.rawValue)
    )

    if json {
      stdout(encodeJSON(catalog) + "\n")
    } else {
      var lines: [String] = ["Supported JS keyCodes (\(entries.count) keys; 129/F18 is reserved):"]
      for k in entries {
        let paddedName = k.name.padding(toLength: 10, withPad: " ", startingAt: 0)
        lines.append(String(format: "  %3d  %@  mac=%@  [%@]", k.jsKeyCode, paddedName, k.macHex, k.category))
      }
      lines.append("")
      lines.append("Modifiers (double_tap_modifier / hold_modifier):")
      for m in catalog.modifiers {
        let holdNote = m.supportsHoldModifierAction ? "double_tap + hold_modifier" : "double_tap ONLY (not hold_modifier)"
        lines.append("  \(m.id) (\(holdNote))")
      }
      lines.append("")
      lines.append("Low-level key_remaps sources: \(catalog.keyRemapSources.joined(separator: ", "))")
      lines.append("Low-level key_remaps targets: \(catalog.keyRemapTargets.joined(separator: ", "))")
      stdout(lines.joined(separator: "\n") + "\n")
    }
    return 0
  }

  private struct BuiltinsOutput: Codable {
    struct BuiltinItem: Codable {
      let id: String
      let kind: String
      let nameEn: String
      let nameZh: String
      let summary: String
    }
    let builtins: [BuiltinItem]
    let retiredBuiltins: [String]
  }

  private static func handleListBuiltins(json: Bool, stdout: (String) -> Void) -> Int32 {
    func describe(_ cfg: ActionConfig) -> String {
      switch cfg {
      case .directional(let d): return "directional(\(d.rawValue))"
      case .jump(let dir, let count): return "jump(direction: \(dir.rawValue), count: \(count))"
      case .independent(let i): return "independent(\(i.rawValue))"
      case .inputSource(let id): return "input_source(\(id))"
      case .command(let cmd): return "command(\(cmd))"
      case .keyCombo(let key, _, _, _, _): return "key_combo(\(key))"
      case .openApp(let bid, _, _): return "open_app(\(bid))"
      case .modifierKey(let m): return "hold_modifier(\(m.rawValue))"
      }
    }

    let labelsByID: [String: (en: String, zh: String)] = [
      "builtin.move_left": ("Left", "左"),
      "builtin.move_right": ("Right", "右"),
      "builtin.move_up": ("Up", "上"),
      "builtin.move_down": ("Down", "下"),
      "builtin.word_forward": ("Word Forward", "下一个词"),
      "builtin.word_back": ("Word Back", "上一个词"),
      "builtin.line_start": ("Home / Line Start", "行首"),
      "builtin.line_end": ("End / Line End", "行尾"),
      "builtin.jump_up_10": ("Jump Up 10", "向上跳 10 行"),
      "builtin.jump_down_10": ("Jump Down 10", "向下跳 10 行"),
      "builtin.backspace": ("Backspace", "退格"),
      "builtin.new_line": ("Next Line", "下一行"),
      "builtin.insert_quotes": ("Insert Quotes", "插入引号"),
      "builtin.toggle_caps_lock": ("Toggle Caps Lock", "大小写切换"),
      "builtin.noop": ("Do Nothing", "什么都不做"),
    ]

    let payload = BuiltinsOutput(
      builtins: BuiltinActions.all.map { a in
        let labels = labelsByID[a.id] ?? (en: a.id, zh: a.id)
        return .init(
          id: a.id,
          kind: a.config.kindTag,
          nameEn: labels.en,
          nameZh: labels.zh,
          summary: describe(a.config)
        )
      },
      retiredBuiltins: ["builtin.switch_input_source"]
    )

    if json {
      stdout(encodeJSON(payload) + "\n")
    } else {
      var lines = ["Active built-in action IDs (\(payload.builtins.count)):"]
      for b in payload.builtins {
        let padded = b.id.padding(toLength: 26, withPad: " ", startingAt: 0)
        lines.append("  \(padded) -> \(b.nameEn) / \(b.nameZh) [\(b.summary)]")
      }
      lines.append("")
      lines.append("Retired (do NOT use): \(payload.retiredBuiltins.joined(separator: ", ")) — use inline 'kind: input_source' with 'input_source_id' instead.")
      stdout(lines.joined(separator: "\n") + "\n")
    }
    return 0
  }

  private struct InputSourcesOutput: Codable {
    let sources: [InputSourceController.SourceDescriptor]
  }

  private static func handleListInputSources(json: Bool, stdout: (String) -> Void) -> Int32 {
    let list = InputSourceController.listSelectableKeyboardSources()
    if json {
      stdout(encodeJSON(InputSourcesOutput(sources: list)) + "\n")
    } else {
      var lines = ["Installed selectable keyboard input sources (\(list.count)):"]
      for s in list {
        let cur = s.isCurrent ? " [current]" : ""
        let cjkv = s.isCJKV ? " (CJKV)" : ""
        lines.append("  \(s.id) — \(s.name)\(cjkv)\(cur)")
      }
      stdout(lines.joined(separator: "\n") + "\n")
    }
    return 0
  }

  // MARK: - Validate

  private struct ValidateOutput: Codable {
    let ok: Bool
    let strict: Bool
    let errorCount: Int
    let warningCount: Int
    let issues: [ValidationIssue]
  }

  private static func handleValidate(
    args: [String],
    dataDir: URL,
    env: ValidationEnvironment,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var mappingsPath: String?
    var appConfigPath: String?
    var strict = false

    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--strict" {
        strict = true
        i += 1
      } else if arg == "--mappings" {
        guard i + 1 < args.count else {
          return emitError("Missing path for --mappings", json: json, stdout: stdout, stderr: stderr)
        }
        mappingsPath = args[i + 1]
        i += 2
      } else if arg.hasPrefix("--mappings=") {
        mappingsPath = String(arg.dropFirst("--mappings=".count))
        i += 1
      } else if arg == "--app-config" {
        guard i + 1 < args.count else {
          return emitError("Missing path for --app-config", json: json, stdout: stdout, stderr: stderr)
        }
        appConfigPath = args[i + 1]
        i += 2
      } else if arg.hasPrefix("--app-config=") {
        appConfigPath = String(arg.dropFirst("--app-config=".count))
        i += 1
      } else {
        return emitError("Unknown option '\(arg)' for 'cli validate'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    var issues: [ValidationIssue] = []
    if mappingsPath == nil && appConfigPath == nil {
      let defaultMappings = dataDir.appendingPathComponent("action_mappings.yml")
      let defaultAppConfig = dataDir.appendingPathComponent("app_config.yml")
      issues.append(contentsOf: ConfigValidator.validateMappingsFile(at: defaultMappings, environment: env).issues)
      if FileManager.default.fileExists(atPath: defaultAppConfig.path) {
        issues.append(contentsOf: ConfigValidator.validateAppConfigFile(at: defaultAppConfig, environment: env).issues)
      }
    } else {
      if let mp = mappingsPath {
        let url = URL(fileURLWithPath: NSString(string: mp).expandingTildeInPath).standardizedFileURL
        issues.append(contentsOf: ConfigValidator.validateMappingsFile(at: url, environment: env).issues)
      }
      if let ap = appConfigPath {
        let url = URL(fileURLWithPath: NSString(string: ap).expandingTildeInPath).standardizedFileURL
        issues.append(contentsOf: ConfigValidator.validateAppConfigFile(at: url, environment: env).issues)
      }
    }

    let report = ValidationReport(issues: issues)
    let code = report.exitCode(strict: strict)
    let out = ValidateOutput(
      ok: code == 0,
      strict: strict,
      errorCount: report.errors.count,
      warningCount: report.warnings.count,
      issues: report.issues
    )

    if json {
      stdout(encodeJSON(out) + "\n")
    } else {
      if report.issues.isEmpty {
        stdout("Validation passed (0 errors, 0 warnings).\n")
      } else {
        stdout(formatIssues(report.issues) + "\n")
        stdout("Summary: \(report.errors.count) error(s), \(report.warnings.count) warning(s)\(strict ? " [--strict]" : "").\n")
      }
    }
    return code
  }

  // MARK: - Apply

  private struct ApplyOutput: Codable {
    let ok: Bool
    let applied: Bool
    let reloaded: Bool
    var pid: Int32?
    var mappingsCount: Int?
    var customActionsCount: Int?
    let backupsCreated: [String]
    let issues: [ValidationIssue]
    let message: String
  }

  private static func handleApply(
    args: [String],
    dataDir: URL,
    env: ValidationEnvironment,
    reloadRequester: ReloadRequester,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var mappingsPath: String?
    var appConfigPath: String?
    var strict = false

    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--strict" {
        strict = true
        i += 1
      } else if arg == "--mappings" {
        guard i + 1 < args.count else {
          return emitError("Missing path for --mappings", json: json, stdout: stdout, stderr: stderr)
        }
        mappingsPath = args[i + 1]
        i += 2
      } else if arg.hasPrefix("--mappings=") {
        mappingsPath = String(arg.dropFirst("--mappings=".count))
        i += 1
      } else if arg == "--app-config" {
        guard i + 1 < args.count else {
          return emitError("Missing path for --app-config", json: json, stdout: stdout, stderr: stderr)
        }
        appConfigPath = args[i + 1]
        i += 2
      } else if arg.hasPrefix("--app-config=") {
        appConfigPath = String(arg.dropFirst("--app-config=".count))
        i += 1
      } else {
        return emitError("Unknown option '\(arg)' for 'cli apply'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    guard mappingsPath != nil || appConfigPath != nil else {
      return emitError(
        "Specify --mappings <path> and/or --app-config <path> (or use 'cli reload' to reload files already edited in place).",
        json: json,
        stdout: stdout,
        stderr: stderr
      )
    }

    let candidateMappingsURL = mappingsPath.map {
      URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath).standardizedFileURL
    }
    let candidateAppConfigURL = appConfigPath.map {
      URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath).standardizedFileURL
    }

    // 1. Pre-flight validate candidate files before touching active data directory.
    var issues: [ValidationIssue] = []
    if let mURL = candidateMappingsURL {
      issues.append(contentsOf: ConfigValidator.validateMappingsFile(at: mURL, environment: env).issues)
    }
    if let aURL = candidateAppConfigURL {
      issues.append(contentsOf: ConfigValidator.validateAppConfigFile(at: aURL, environment: env).issues)
    }
    let report = ValidationReport(issues: issues)
    let validationCode = report.exitCode(strict: strict)
    if validationCode != 0 {
      let out = ApplyOutput(
        ok: false,
        applied: false,
        reloaded: false,
        backupsCreated: [],
        issues: report.issues,
        message: "Pre-flight validation failed (\(report.errors.count) error(s), \(report.warnings.count) warning(s)). Active configuration was NOT modified."
      )
      if json {
        stdout(encodeJSON(out) + "\n")
      } else {
        stderr(formatIssues(report.issues) + "\n")
        stderr(out.message + "\n")
      }
      return validationCode
    }

    // 2. UUID-backup existing active files (if changed) & atomically write candidates.
    let backupManager = ConfigBackupManager(dataDirectory: dataDir)
    var backupsCreated: [String] = []
    var backedUpMappingsSHA: String?
    var backedUpAppConfigSHA: String?

    do {
      try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

      if let mURL = candidateMappingsURL {
        let activeURL = backupManager.activeFileURL(for: .mappings)
        if ReloadIPC.canonicalPath(mURL) != ReloadIPC.canonicalPath(activeURL) {
          let candidateData = try Data(contentsOf: mURL)
          if let backup = try backupManager.backupActiveFileIfChanged(kind: .mappings, incomingData: candidateData) {
            backupsCreated.append(backup.backupURL.path)
            backedUpMappingsSHA = backup.sha256
          }
          try candidateData.write(to: activeURL, options: .atomic)
        }
      }

      if let aURL = candidateAppConfigURL {
        let activeURL = backupManager.activeFileURL(for: .appConfig)
        if ReloadIPC.canonicalPath(aURL) != ReloadIPC.canonicalPath(activeURL) {
          let candidateData = try Data(contentsOf: aURL)
          if let backup = try backupManager.backupActiveFileIfChanged(kind: .appConfig, incomingData: candidateData) {
            backupsCreated.append(backup.backupURL.path)
            backedUpAppConfigSHA = backup.sha256
          }
          try candidateData.write(to: activeURL, options: .atomic)
        }
      }
    } catch {
      return emitError("Failed to apply configuration: \(error.localizedDescription)", json: json, stdout: stdout, stderr: stderr)
    }

    // 3. Trigger live IPC reload (wait up to 2.0s).
    let ack = reloadRequester(dataDir, backedUpMappingsSHA, backedUpAppConfigSHA, 2.0)
    if let ack {
      for b in ack.backupFilesCreated where !backupsCreated.contains(b) {
        backupsCreated.append(b)
      }
      if !ack.ok {
        let errSummary = ack.errors.joined(separator: "; ")
        let out = ApplyOutput(
          ok: false,
          applied: true,
          reloaded: false,
          pid: ack.pid,
          backupsCreated: backupsCreated,
          issues: report.issues,
          message: "Live reload rejected by running app (pid=\(ack.pid)): \(errSummary)"
        )
        if json {
          stdout(encodeJSON(out) + "\n")
        } else {
          stderr(out.message + "\n")
        }
        return 1
      }

      let out = ApplyOutput(
        ok: true,
        applied: true,
        reloaded: true,
        pid: ack.pid,
        mappingsCount: ack.mappingsCount,
        customActionsCount: ack.customActionsCount,
        backupsCreated: backupsCreated,
        issues: report.issues,
        message: "Applied and live-reloaded in running HyperCapslock (pid=\(ack.pid): \(ack.mappingsCount) mappings, \(ack.customActionsCount) custom actions)."
      )
      if json {
        stdout(encodeJSON(out) + "\n")
      } else {
        if !report.warnings.isEmpty { stdout(formatIssues(report.warnings) + "\n") }
        for b in backupsCreated { stdout("Backup saved: \(b)\n") }
        stdout(out.message + "\n")
      }
      return 0
    } else {
      let out = ApplyOutput(
        ok: true,
        applied: true,
        reloaded: false,
        backupsCreated: backupsCreated,
        issues: report.issues,
        message: "Configuration written to \(dataDir.path) (HyperCapslock is not currently running; changes will apply on next launch)."
      )
      if json {
        stdout(encodeJSON(out) + "\n")
      } else {
        if !report.warnings.isEmpty { stdout(formatIssues(report.warnings) + "\n") }
        for b in backupsCreated { stdout("Backup saved: \(b)\n") }
        stdout(out.message + "\n")
      }
      return 0
    }
  }

  // MARK: - Reload

  private static func handleReload(
    args: [String],
    dataDir: URL,
    env: ValidationEnvironment,
    reloadRequester: ReloadRequester,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var strict = false
    for arg in args {
      if arg == "--strict" {
        strict = true
      } else {
        return emitError("Unknown option '\(arg)' for 'cli reload'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    let mappingsURL = dataDir.appendingPathComponent("action_mappings.yml")
    let appConfigURL = dataDir.appendingPathComponent("app_config.yml")
    guard FileManager.default.fileExists(atPath: mappingsURL.path) || FileManager.default.fileExists(atPath: appConfigURL.path) else {
      return emitError("No configuration files found in \(dataDir.path)", json: json, stdout: stdout, stderr: stderr)
    }

    let report = ConfigValidator.validateDataDirectory(dataDir, environment: env)
    let code = report.exitCode(strict: strict)
    if code != 0 {
      let out = ApplyOutput(
        ok: false,
        applied: false,
        reloaded: false,
        backupsCreated: [],
        issues: report.issues,
        message: "Disk configuration validation failed (\(report.errors.count) error(s), \(report.warnings.count) warning(s)). Running app state unchanged."
      )
      if json {
        stdout(encodeJSON(out) + "\n")
      } else {
        stderr(formatIssues(report.issues) + "\n")
        stderr(out.message + "\n")
      }
      return code
    }

    let ack = reloadRequester(dataDir, nil, nil, 2.0)
    if let ack {
      if !ack.ok {
        let out = ApplyOutput(
          ok: false,
          applied: false,
          reloaded: false,
          pid: ack.pid,
          backupsCreated: ack.backupFilesCreated,
          issues: report.issues,
          message: "Live reload failed in running app (pid=\(ack.pid)): \(ack.errors.joined(separator: "; "))"
        )
        if json {
          stdout(encodeJSON(out) + "\n")
        } else {
          stderr(out.message + "\n")
        }
        return 1
      }

      let out = ApplyOutput(
        ok: true,
        applied: true,
        reloaded: true,
        pid: ack.pid,
        mappingsCount: ack.mappingsCount,
        customActionsCount: ack.customActionsCount,
        backupsCreated: ack.backupFilesCreated,
        issues: report.issues,
        message: "Live-reloaded HyperCapslock (pid=\(ack.pid): \(ack.mappingsCount) mappings, \(ack.customActionsCount) custom actions)."
      )
      if json {
        stdout(encodeJSON(out) + "\n")
      } else {
        if !report.warnings.isEmpty { stdout(formatIssues(report.warnings) + "\n") }
        for b in ack.backupFilesCreated { stdout("Backup saved: \(b)\n") }
        stdout(out.message + "\n")
      }
      return 0
    } else {
      let out = ApplyOutput(
        ok: true,
        applied: true,
        reloaded: false,
        backupsCreated: [],
        issues: report.issues,
        message: "Configuration on disk in \(dataDir.path) is valid (HyperCapslock is not currently running; changes will apply on next launch)."
      )
      if json {
        stdout(encodeJSON(out) + "\n")
      } else {
        if !report.warnings.isEmpty { stdout(formatIssues(report.warnings) + "\n") }
        stdout(out.message + "\n")
      }
      return 0
    }
  }

  // MARK: - Backups & Rollback

  private struct BackupsOutput: Codable {
    let backupsDir: String
    let backups: [ConfigBackupEntry]
  }

  private static func handleBackups(
    args: [String],
    dataDir: URL,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var filterKind: ConfigFileKind?
    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--kind" {
        guard i + 1 < args.count, let parsed = ConfigFileKind.parseCLI(args[i + 1]) else {
          return emitError("Invalid or missing --kind (expected 'mappings' or 'app-config')", json: json, stdout: stdout, stderr: stderr)
        }
        filterKind = parsed
        i += 2
      } else if arg.hasPrefix("--kind=") {
        let raw = String(arg.dropFirst("--kind=".count))
        guard let parsed = ConfigFileKind.parseCLI(raw) else {
          return emitError("Invalid or missing --kind (expected 'mappings' or 'app-config')", json: json, stdout: stdout, stderr: stderr)
        }
        filterKind = parsed
        i += 1
      } else {
        return emitError("Unknown option '\(arg)' for 'cli backups'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    let manager = ConfigBackupManager(dataDirectory: dataDir)
    let list = manager.listBackups(kind: filterKind)
    if json {
      stdout(encodeJSON(BackupsOutput(backupsDir: manager.backupsDirectory.path, backups: list)) + "\n")
    } else {
      if list.isEmpty {
        stdout("No backups found in \(manager.backupsDirectory.path)\n")
      } else {
        var lines = ["Backups in \(manager.backupsDirectory.path) (\(list.count), newest first):"]
        for b in list {
          lines.append("  [\(b.kind.rawValue)] \(b.fileName) (\(b.sizeBytes) B)")
        }
        stdout(lines.joined(separator: "\n") + "\n")
      }
    }
    return 0
  }

  private struct RollbackOutput: Codable {
    let ok: Bool
    let kind: ConfigFileKind
    let restoredFrom: String
    let activeFile: String
    let reloaded: Bool
    var pid: Int32?
    let backupsCreated: [String]
    let message: String
  }

  private static func handleRollback(
    args: [String],
    dataDir: URL,
    env: ValidationEnvironment,
    reloadRequester: ReloadRequester,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var latest = false
    var fileSpec: String?
    var filterKind: ConfigFileKind?

    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--latest" {
        latest = true
        i += 1
      } else if arg == "--file" {
        guard i + 1 < args.count else {
          return emitError("Missing argument for --file", json: json, stdout: stdout, stderr: stderr)
        }
        fileSpec = args[i + 1]
        i += 2
      } else if arg.hasPrefix("--file=") {
        fileSpec = String(arg.dropFirst("--file=".count))
        i += 1
      } else if arg == "--kind" {
        guard i + 1 < args.count, let parsed = ConfigFileKind.parseCLI(args[i + 1]) else {
          return emitError("Invalid or missing --kind (expected 'mappings' or 'app-config')", json: json, stdout: stdout, stderr: stderr)
        }
        filterKind = parsed
        i += 2
      } else if arg.hasPrefix("--kind=") {
        let raw = String(arg.dropFirst("--kind=".count))
        guard let parsed = ConfigFileKind.parseCLI(raw) else {
          return emitError("Invalid or missing --kind (expected 'mappings' or 'app-config')", json: json, stdout: stdout, stderr: stderr)
        }
        filterKind = parsed
        i += 1
      } else {
        return emitError("Unknown option '\(arg)' for 'cli rollback'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    if latest && fileSpec != nil {
      return emitError("Specify either --latest or --file, not both", json: json, stdout: stdout, stderr: stderr)
    }
    if !latest && fileSpec == nil {
      latest = true
    }

    let manager = ConfigBackupManager(dataDirectory: dataDir)
    let resolved: (url: URL, kind: ConfigFileKind)
    do {
      resolved = try manager.resolveBackup(latest: latest, fileSpec: fileSpec, kind: filterKind)
    } catch {
      return emitError(error.localizedDescription, json: json, stdout: stdout, stderr: stderr)
    }

    // Validate backup before restoring over active file.
    let report: ValidationReport = {
      switch resolved.kind {
      case .mappings:
        return ConfigValidator.validateMappingsFile(at: resolved.url, environment: env)
      case .appConfig:
        return ConfigValidator.validateAppConfigFile(at: resolved.url, environment: env)
      }
    }()
    if !report.isValid {
      return emitError(
        "Refusing to restore invalid backup \(resolved.url.lastPathComponent): \(report.errors.map(\.message).joined(separator: "; "))",
        json: json,
        stdout: stdout,
        stderr: stderr
      )
    }

    var backupsCreated: [String] = []
    var backedUpMappingsSHA: String?
    var backedUpAppConfigSHA: String?
    let activeURL = manager.activeFileURL(for: resolved.kind)

    do {
      let backupData = try Data(contentsOf: resolved.url)
      try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
      if let safetyBackup = try manager.backupActiveFileIfChanged(kind: resolved.kind, incomingData: backupData) {
        backupsCreated.append(safetyBackup.backupURL.path)
        switch resolved.kind {
        case .mappings: backedUpMappingsSHA = safetyBackup.sha256
        case .appConfig: backedUpAppConfigSHA = safetyBackup.sha256
        }
      }
      try backupData.write(to: activeURL, options: .atomic)
    } catch {
      return emitError("Rollback failed: \(error.localizedDescription)", json: json, stdout: stdout, stderr: stderr)
    }

    let ack = reloadRequester(dataDir, backedUpMappingsSHA, backedUpAppConfigSHA, 2.0)
    if let ack {
      for b in ack.backupFilesCreated where !backupsCreated.contains(b) {
        backupsCreated.append(b)
      }
    }

    let reloaded = ack?.ok ?? false
    let msg: String
    if let ack, ack.ok {
      msg = "Restored \(resolved.url.lastPathComponent) → \(activeURL.lastPathComponent) and live-reloaded HyperCapslock (pid=\(ack.pid))."
    } else if let ack, !ack.ok {
      return emitError("Restored file, but live reload failed: \(ack.errors.joined(separator: "; "))", json: json, stdout: stdout, stderr: stderr)
    } else {
      msg = "Restored \(resolved.url.lastPathComponent) → \(activeURL.lastPathComponent) (app not currently running; will apply on next launch)."
    }

    let out = RollbackOutput(
      ok: true,
      kind: resolved.kind,
      restoredFrom: resolved.url.path,
      activeFile: activeURL.path,
      reloaded: reloaded,
      pid: ack?.pid,
      backupsCreated: backupsCreated,
      message: msg
    )
    if json {
      stdout(encodeJSON(out) + "\n")
    } else {
      for b in backupsCreated { stdout("Previous active config backed up: \(b)\n") }
      stdout(msg + "\n")
    }
    return 0
  }

  // MARK: - Install Skill & Prompt

  private static func handleInstallSkill(
    args: [String],
    skillDir: URL?,
    homeDir: URL,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var target: SkillAgentTarget = .all
    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--target" {
        guard i + 1 < args.count else {
          return emitError("Missing value for --target", json: json, stdout: stdout, stderr: stderr)
        }
        guard let parsed = SkillAgentTarget(rawValue: args[i + 1].lowercased()) else {
          return emitError(SkillInstallError.invalidTarget(args[i + 1]).localizedDescription, json: json, stdout: stdout, stderr: stderr)
        }
        target = parsed
        i += 2
      } else if arg.hasPrefix("--target=") {
        let raw = String(arg.dropFirst("--target=".count))
        guard let parsed = SkillAgentTarget(rawValue: raw.lowercased()) else {
          return emitError(SkillInstallError.invalidTarget(raw).localizedDescription, json: json, stdout: stdout, stderr: stderr)
        }
        target = parsed
        i += 1
      } else {
        return emitError("Unknown option '\(arg)' for 'cli install-skill'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    do {
      let result = try SkillInstaller.install(target: target, sourceSkillDirectory: skillDir, homeDirectory: homeDir)
      if json {
        stdout(encodeJSON(result) + "\n")
      } else {
        var lines = ["Installed canonical skill: \(result.canonicalSkillDir)"]
        let linked = result.symlinks.filter { $0.status == "linked" }
        if linked.isEmpty {
          lines.append("No additional agent directories detected (canonical ~/.agents/skills/hypercapslock is ready).")
        } else {
          for s in linked {
            lines.append("  Linked [\(s.agent)]: \(s.linkPath)")
          }
        }
        stdout(lines.joined(separator: "\n") + "\n")
      }
      return 0
    } catch {
      return emitError(error.localizedDescription, json: json, stdout: stdout, stderr: stderr)
    }
  }

  private struct PromptOutput: Codable {
    let language: String
    let skillFile: String
    let executablePath: String
    let dataDir: String
    let prompt: String
  }

  private static func handlePrompt(
    args: [String],
    dataDir: URL,
    skillDir: URL?,
    exePath: String?,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    var explicitLocale: AppLocale?
    var i = 0
    while i < args.count {
      let arg = args[i]
      let rawLang: String
      if arg == "--lang" {
        guard i + 1 < args.count else {
          return emitError("Missing value for --lang (expected 'zh' or 'en')", json: json, stdout: stdout, stderr: stderr)
        }
        rawLang = args[i + 1]
        i += 2
      } else if arg.hasPrefix("--lang=") {
        rawLang = String(arg.dropFirst("--lang=".count))
        i += 1
      } else {
        return emitError("Unknown option '\(arg)' for 'cli prompt'", json: json, stdout: stdout, stderr: stderr)
      }
      switch rawLang.lowercased() {
      case "zh", "zh-cn", "zh-hans": explicitLocale = .zh
      case "en": explicitLocale = .en
      default:
        return emitError("Unsupported --lang '\(rawLang)'; expected 'zh' or 'en'", json: json, stdout: stdout, stderr: stderr)
      }
    }

    let resolvedLocale = explicitLocale ?? SkillPromptBuilder.resolveActiveLocale()
    let effectiveLang = (resolvedLocale == .zh) ? "zh" : "en"
    let resolvedSkillDir = (skillDir ?? SkillPromptBuilder.resolveBundledSkillDirectory()).standardizedFileURL
    let resolvedExe = exePath ?? SkillPromptBuilder.resolveExecutablePath()
    let skillFile = SkillPromptBuilder.skillFileURL(for: resolvedLocale, skillDirectory: resolvedSkillDir).path
    let prompt = SkillPromptBuilder.buildPrompt(
      for: resolvedLocale,
      skillDirectory: resolvedSkillDir,
      executablePath: resolvedExe,
      dataDirectory: dataDir
    )

    if json {
      let out = PromptOutput(
        language: effectiveLang,
        skillFile: skillFile,
        executablePath: resolvedExe,
        dataDir: dataDir.path,
        prompt: prompt
      )
      stdout(encodeJSON(out) + "\n")
    } else {
      stdout(prompt + "\n")
    }
    return 0
  }

  // MARK: - Formatting & Error Helpers

  private struct CLIErrorPayload: Codable {
    let ok: Bool
    let error: String
  }

  private static func emitError(
    _ message: String,
    json: Bool,
    stdout: (String) -> Void,
    stderr: (String) -> Void
  ) -> Int32 {
    if json {
      stdout(encodeJSON(CLIErrorPayload(ok: false, error: message)) + "\n")
    } else {
      stderr("Error: \(message)\n")
    }
    return 1
  }

  private static func encodeJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let str = String(data: data, encoding: .utf8) else {
      return #"{"ok":false,"error":"JSON serialization failed"}"#
    }
    return str
  }

  private static func formatIssues(_ issues: [ValidationIssue]) -> String {
    issues.map { issue in
      let loc: String = {
        if let line = issue.line, let col = issue.column {
          return ":\(line):\(col)"
        }
        return ""
      }()
      let tag = issue.severity == .error ? "ERROR" : "WARN "
      return "[\(tag)] \(issue.file)\(loc) (\(issue.path)): \(issue.message)"
    }.joined(separator: "\n")
  }

  private static func usageText(for subcommand: String? = nil) -> String {
    if let sub = subcommand {
      return "Usage: HyperCapslock cli \(sub) [options] [--data-dir <dir>] [--json]\n\n" + usageText()
    }
    return """
    HyperCapslock CLI — Safe configuration management & live hot-reload

    Usage:
      HyperCapslock cli <subcommand> [options] [--data-dir <dir>] [--json]

    Subcommands:
      info                                Show version, paths, backups, and live instance status
      list-keys                           List valid JS keyCodes, modifiers, and key_remaps tokens
      list-builtins                       List the 15 permanent built-in action IDs
      list-input-sources                  List installed selectable macOS keyboard input sources
      validate [--mappings <p>] [--app-config <p>] [--strict]
                                          Pre-flight validate YAML config (exit 0 ok, 1 error, 2 strict warn)
      apply [--mappings <p>] [--app-config <p>] [--strict]
                                          Validate, UUID-backup active file(s), write atomically & live-reload
      reload [--strict]                   Validate disk config in <dataDir> and live-reload running app
      backups [--kind mappings|app-config]
                                          List historical UUID backups newest-first
      rollback [--latest | --file <f>] [--kind mappings|app-config]
                                          UUID-backup active config, restore backup & live-reload
      install-skill [--target all|claude|codex|cursor|antigravity|windsurf|cline|copilot]
                                          Install bundled skill to ~/.agents/skills/hypercapslock + agent links
      prompt [--lang zh|en]               Print localized AI bootstrap prompt with runtime paths

    Global flags:
      --data-dir <dir>                    Override configuration directory
      --json                              Emit structured JSON to stdout
      -h, --help                          Show this help text
    """
  }
}
