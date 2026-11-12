import XCTest
import Yams
@testable import HyperCapslock

@MainActor
final class Issue29CLISkillTests: XCTestCase {

  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("hc-issue29-tests-\(UUID().uuidString.lowercased())", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - 1. ConfigValidator Tests

  func testValidatorAcceptsValidMappingsAndAppConfig() {
    let customUUID = "11111111-2222-3333-4444-555555555555"
    let mappingsYAML = """
    actions:
      - id: "\(customUUID)"
        name: "Run Tmux"
        action:
          kind: command
          command: "open -a Terminal"
    mappings:
      - trigger:
          kind: hyper_plus_key
          key: 72
          with_shift: false
        action_id: builtin.move_left
      - trigger:
          kind: double_tap_modifier
          modifier: right_command
        action_id: "\(customUUID)"
        bindings:
          - when:
              - type: frontmost_app
                include:
                  - com.apple.Safari
            action:
              kind: key_combo
              target_key: 84
              with_cmd: true
    """
    let env = ValidationEnvironment(
      isInputSourceInstalled: { _ in true },
      isAppBundleInstalled: { _ in true }
    )
    let mReport = ConfigValidator.validateMappingsYAML(mappingsYAML, environment: env)
    XCTAssertTrue(mReport.issues.isEmpty, "Expected 0 issues, got: \(mReport.issues)")
    XCTAssertEqual(mReport.exitCode(strict: true), 0)

    let appConfigYAML = """
    hide_dock_icon: false
    show_hud: true
    hud_duration_ms: 1350
    double_tap_window_ms: 200
    theme_mode: system
    cjkv_fix_strategy: switching_focus
    broadcast_caps_hold_for_anydrag: false
    mappings_view_style: keyboard
    stats_show_inline: true
    show_window_on_launch: true
    analytics_enabled: false
    key_remaps:
      - source: right_option
        destination: f19
    """
    let aReport = ConfigValidator.validateAppConfigYAML(appConfigYAML, environment: env)
    XCTAssertTrue(aReport.issues.isEmpty, "Expected 0 issues, got: \(aReport.issues)")
    XCTAssertEqual(aReport.exitCode(strict: true), 0)
  }

  func testValidatorDetectsYAMLSyntaxErrorWithLineAndColumn() {
    let brokenYAML = """
    mappings:
      - trigger:
          kind: hyper_plus_key
          key: [unclosed
    """
    let report = ConfigValidator.validateMappingsYAML(brokenYAML, environment: .offline)
    XCTAssertFalse(report.isValid)
    XCTAssertEqual(report.errors.count, 1)
    XCTAssertNotNil(report.errors.first?.line)
    XCTAssertNotNil(report.errors.first?.column)
  }

  func testValidatorRejectsReservedF18AndUnmappedJSKeyCodes() {
    let f18TriggerYAML = """
    mappings:
      - trigger:
          kind: hyper_plus_key
          key: 129
          with_shift: false
        action_id: builtin.move_left
    """
    let r1 = ConfigValidator.validateMappingsYAML(f18TriggerYAML, environment: .offline)
    XCTAssertEqual(r1.errors.count, 1)
    XCTAssertTrue(r1.errors[0].message.contains("129"))

    let unmappedComboYAML = """
    mappings:
      - trigger:
          kind: single_tap_hyper
        action:
          kind: key_combo
          target_key: 250
          with_cmd: true
    """
    let r2 = ConfigValidator.validateMappingsYAML(unmappedComboYAML, environment: .offline)
    XCTAssertEqual(r2.errors.count, 1)
    XCTAssertTrue(r2.errors[0].path.contains("target_key"))
  }

  func testValidatorRejectsHoldModifierFnAndRetiredSwitchInputSource() {
    let fnHoldYAML = """
    mappings:
      - trigger:
          kind: hyper_plus_key
          key: 70
        action:
          kind: hold_modifier
          modifier: fn
    """
    let r1 = ConfigValidator.validateMappingsYAML(fnHoldYAML, environment: .offline)
    XCTAssertEqual(r1.errors.count, 1)
    XCTAssertTrue(r1.errors[0].message.contains("fn"))

    // Inline retired `switch_input_source`
    let retiredInlineYAML = """
    mappings:
      - trigger:
          kind: single_tap_hyper
        action:
          kind: independent
          action: switch_input_source
    """
    let r2 = ConfigValidator.validateMappingsYAML(retiredInlineYAML, environment: .offline)
    XCTAssertEqual(r2.errors.count, 1)
    XCTAssertTrue(r2.errors[0].message.contains("input_source"))

    // Retired `builtin.switch_input_source` ID
    let retiredIDYAML = """
    mappings:
      - trigger:
          kind: single_tap_hyper
        action_id: builtin.switch_input_source
    """
    let r3 = ConfigValidator.validateMappingsYAML(retiredIDYAML, environment: .offline)
    XCTAssertEqual(r3.errors.count, 1)
    XCTAssertTrue(r3.errors[0].message.contains("retired"))
  }

  func testValidatorRejectsOrphanedActionIDNonUUIDCustomActionAndDuplicateTriggers() {
    let invalidYAML = """
    actions:
      - id: "not-a-uuid"
        name: ""
        action:
          kind: jump
          direction: up
          count: 0
    mappings:
      - trigger:
          kind: hyper_plus_key
          key: 72
        action_id: builtin.does_not_exist
      - trigger:
          kind: hyper_plus_key
          key: 72
        action_id: builtin.move_left
    """
    let report = ConfigValidator.validateMappingsYAML(invalidYAML, environment: .offline)
    let paths = Set(report.errors.map(\.path))
    XCTAssertTrue(paths.contains("actions[0].id"), "Expected non-UUID error, got \(paths)")
    XCTAssertTrue(paths.contains("actions[0].name"), "Expected empty name error, got \(paths)")
    XCTAssertTrue(paths.contains("actions[0].action.count"), "Expected jump count < 1 error, got \(paths)")
    XCTAssertTrue(paths.contains("mappings[0].action_id"), "Expected orphaned action_id error, got \(paths)")
    XCTAssertTrue(paths.contains("mappings[1].trigger"), "Expected duplicate trigger error, got \(paths)")
  }

  func testValidatorRejectsInvalidAppConfigRangesEnumsAndDuplicateRemaps() {
    let badAppConfig = """
    hud_duration_ms: 9000
    double_tap_window_ms: 50
    theme_mode: midnight
    cjkv_fix_strategy: magic
    mappings_view_style: list
    show_hud: "yes"
    key_remaps:
      - source: right_option
        destination: f18
      - source: right_option
        destination: f19
    """
    let report = ConfigValidator.validateAppConfigYAML(badAppConfig, environment: .offline)
    let paths = Set(report.errors.map(\.path))
    XCTAssertTrue(paths.contains("hud_duration_ms"))
    XCTAssertTrue(paths.contains("double_tap_window_ms"))
    XCTAssertTrue(paths.contains("theme_mode"))
    XCTAssertTrue(paths.contains("cjkv_fix_strategy"))
    XCTAssertTrue(paths.contains("mappings_view_style"))
    XCTAssertTrue(paths.contains("show_hud"))
    XCTAssertTrue(paths.contains("key_remaps[0].destination"))
    XCTAssertTrue(paths.contains("key_remaps[1].source"))
    XCTAssertEqual(report.exitCode(strict: false), 1)
  }

  func testValidatorWarningsVsStrictExitCode() {
    let warningsYAML = """
    future_top_level_flag: true
    mappings:
      - trigger:
          kind: hyper_plus_key
          key: 72
        action:
          kind: input_source
          input_source_id: com.example.missing.ime
          extra_typo_field: 123
        bindings:
          - when:
              - type: frontmost_app
                include:
                  - com.example.uninstalled.App
            action_id: builtin.move_left
    """
    let env = ValidationEnvironment(
      isInputSourceInstalled: { _ in false },
      isAppBundleInstalled: { _ in false }
    )
    let report = ConfigValidator.validateMappingsYAML(warningsYAML, environment: env)
    XCTAssertTrue(report.errors.isEmpty, "Expected 0 hard errors, got \(report.errors)")
    XCTAssertEqual(report.warnings.count, 4, "Expected 4 warnings (top-level key, extra key, missing IME, missing app), got \(report.warnings)")
    XCTAssertEqual(report.exitCode(strict: false), 0, "Non-strict mode must exit 0 on warnings")
    XCTAssertEqual(report.exitCode(strict: true), 2, "Strict mode must exit 2 on warnings")
  }

  // MARK: - 2. ConfigBackupManager, Reload Deduplication & Lossless Preservation

  func testUUIDBackupFormatAndLifecycleAcrossApplyDirectReloadAndRollback() throws {
    let dataDir = tempDir.appendingPathComponent("data", isDirectory: true)
    try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

    let v1YAML = """
    future_preserved_root:
      keep_me: 42
    mappings:
      - trigger: { kind: hyper_plus_key, key: 72, with_shift: false }
        action_id: builtin.move_left
        per_entry_extra: "hello"
    """
    let mappingsURL = dataDir.appendingPathComponent("action_mappings.yml")
    try Data(v1YAML.utf8).write(to: mappingsURL, options: .atomic)

    let store = ConfigStore(dataDirectory: dataDir, syncRegistries: false)
    store.load()
    XCTAssertEqual(store.mappings.count, 1)

    // Step A: `cli apply` candidate v2 → CLI creates 1 UUID backup of v1, passes SHA256
    // to store.reloadFromDisk, so reloadFromDisk MUST NOT create a duplicate backup!
    let v2CandidateURL = tempDir.appendingPathComponent("candidate_v2.yml")
    let v2YAML = """
    future_preserved_root:
      keep_me: 42
    mappings:
      - trigger: { kind: hyper_plus_key, key: 72, with_shift: false }
        action_id: builtin.move_left
        per_entry_extra: "hello"
      - trigger: { kind: hyper_plus_key, key: 76, with_shift: false }
        action_id: builtin.move_right
    """
    try Data(v2YAML.utf8).write(to: v2CandidateURL, options: .atomic)

    var reloadCalls = 0
    let applyCode = CLIRunner.execute(
      arguments: ["cli", "apply", "--mappings", v2CandidateURL.path, "--data-dir", dataDir.path, "--json"],
      validationEnvironment: .offline,
      reloadRequester: { dir, mSHA, aSHA, _ in
        reloadCalls += 1
        let reloadBackups = (try? store.reloadFromDisk(backedUpMappingsSHA256: mSHA, backedUpAppConfigSHA256: aSHA)) ?? []
        return ReloadIPC.ReloadAck(
          requestId: "req-1",
          targetDataDir: ReloadIPC.canonicalPath(dir),
          ok: true,
          pid: 1234,
          mappingsCount: store.mappings.count,
          customActionsCount: store.customActions.count,
          backupFilesCreated: reloadBackups.map(\.path),
          errors: [],
          warnings: []
        )
      },
      writeStdout: { _ in },
      writeStderr: { XCTFail("Unexpected stderr: \($0)") }
    )
    XCTAssertEqual(applyCode, 0)
    XCTAssertEqual(reloadCalls, 1)
    XCTAssertEqual(store.mappings.count, 2)

    let backupManager = ConfigBackupManager(dataDirectory: dataDir)
    let backupsAfterApply = backupManager.listBackups(kind: .mappings)
    XCTAssertEqual(backupsAfterApply.count, 1, "Expected exactly 1 backup (no duplicate from reloadFromDisk)")
    XCTAssertNotNil(ConfigBackupManager.parseUUIDBackupFileName(backupsAfterApply[0].fileName),
                    "Backup filename must match <prefix>-<yyyyMMdd-HHmmss>-<uuid>.yml, got \(backupsAfterApply[0].fileName)")
    let v1BackupContent = try String(contentsOfFile: backupsAfterApply[0].path, encoding: .utf8)
    XCTAssertEqual(v1BackupContent, v1YAML)

    // Step B: Direct YAML edit on disk to v3 + `cli reload` (no CLI backup yet) →
    // `store.reloadFromDisk(backedUpMappingsSHA256: nil)` MUST back up outgoing v2 in memory!
    let v3YAML = """
    future_preserved_root:
      keep_me: 99
    mappings:
      - trigger: { kind: single_tap_hyper }
        action_id: builtin.backspace
    """
    try Data(v3YAML.utf8).write(to: mappingsURL, options: .atomic)

    let reloadCode = CLIRunner.execute(
      arguments: ["cli", "reload", "--data-dir", dataDir.path, "--json"],
      validationEnvironment: .offline,
      reloadRequester: { dir, mSHA, aSHA, _ in
        let reloadBackups = (try? store.reloadFromDisk(backedUpMappingsSHA256: mSHA, backedUpAppConfigSHA256: aSHA)) ?? []
        return ReloadIPC.ReloadAck(
          requestId: "req-2",
          targetDataDir: ReloadIPC.canonicalPath(dir),
          ok: true,
          pid: 1234,
          mappingsCount: store.mappings.count,
          customActionsCount: store.customActions.count,
          backupFilesCreated: reloadBackups.map(\.path),
          errors: [],
          warnings: []
        )
      },
      writeStdout: { _ in },
      writeStderr: { XCTFail("Unexpected stderr: \($0)") }
    )
    XCTAssertEqual(reloadCode, 0)
    XCTAssertEqual(store.mappings.count, 1)

    let backupsAfterDirectReload = backupManager.listBackups(kind: .mappings)
    XCTAssertEqual(backupsAfterDirectReload.count, 2, "Direct disk edit + reload must create a UUID backup of outgoing v2")
    let newestContent = try String(contentsOfFile: backupsAfterDirectReload[0].path, encoding: .utf8)
    XCTAssertEqual(newestContent, v2YAML)

    // Step C: `cli rollback --latest --kind mappings` restores v2 AND backs up outgoing v3 first!
    let rollbackCode = CLIRunner.execute(
      arguments: ["cli", "rollback", "--latest", "--kind", "mappings", "--data-dir", dataDir.path, "--json"],
      validationEnvironment: .offline,
      reloadRequester: { dir, mSHA, aSHA, _ in
        let reloadBackups = (try? store.reloadFromDisk(backedUpMappingsSHA256: mSHA, backedUpAppConfigSHA256: aSHA)) ?? []
        return ReloadIPC.ReloadAck(
          requestId: "req-3",
          targetDataDir: ReloadIPC.canonicalPath(dir),
          ok: true,
          pid: 1234,
          mappingsCount: store.mappings.count,
          customActionsCount: store.customActions.count,
          backupFilesCreated: reloadBackups.map(\.path),
          errors: [],
          warnings: []
        )
      },
      writeStdout: { _ in },
      writeStderr: { XCTFail("Unexpected stderr: \($0)") }
    )
    XCTAssertEqual(rollbackCode, 0)
    XCTAssertEqual(store.mappings.count, 2, "Store should be restored back to v2's 2 mappings")

    let backupsAfterRollback = backupManager.listBackups(kind: .mappings)
    XCTAssertEqual(backupsAfterRollback.count, 3, "Rollback must also preserve outgoing v3 as a 3rd UUID backup")
    let backedUpV3 = try String(contentsOfFile: backupsAfterRollback[0].path, encoding: .utf8)
    XCTAssertEqual(backedUpV3, v3YAML)

    // Verify lossless unknown-key preservation survived reloadFromDisk + subsequent UI save!
    try store.upsert(
      trigger: .hyperPlusKey(key: 74, withShift: false),
      actionId: "builtin.move_down",
      inlineAction: nil
    )
    let savedYAML = try String(contentsOf: mappingsURL, encoding: .utf8)
    XCTAssertTrue(savedYAML.contains("future_preserved_root"), "Unknown top-level key must survive reloadFromDisk + save")
    XCTAssertTrue(savedYAML.contains("per_entry_extra"), "Unknown per-entry key must survive reloadFromDisk + save")
  }

  // MARK: - 3. SkillPromptBuilder & SkillInstaller Tests

  func testSkillPromptBuilderUsesChineseForZhAndEnglishForAllOtherLocales() {
    let fakeSkillDir = tempDir.appendingPathComponent("skills/hypercapslock", isDirectory: true)
    let fakeExe = "/Applications/HyperCapslock.app/Contents/MacOS/HyperCapslock"
    let fakeDataDir = tempDir.appendingPathComponent("config-dir", isDirectory: true)

    // Chinese (`zh`) → Chinese prompt + SKILL.zh.md
    let zhPrompt = SkillPromptBuilder.buildPrompt(
      for: .zh,
      skillDirectory: fakeSkillDir,
      executablePath: fakeExe,
      dataDirectory: fakeDataDir
    )
    XCTAssertTrue(zhPrompt.contains(fakeSkillDir.appendingPathComponent("SKILL.zh.md").path))
    XCTAssertFalse(zhPrompt.contains(fakeSkillDir.appendingPathComponent("SKILL.md").path))
    XCTAssertTrue(zhPrompt.contains(fakeExe))
    XCTAssertTrue(zhPrompt.contains(fakeDataDir.standardizedFileURL.path))
    XCTAssertTrue(zhPrompt.contains("请帮我配置"))

    // English, Japanese, German (`en`, `ja`, `de`) → ALL use English prompt + SKILL.md!
    for locale in [AppLocale.en, .ja, .de] {
      let prompt = SkillPromptBuilder.buildPrompt(
        for: locale,
        skillDirectory: fakeSkillDir,
        executablePath: fakeExe,
        dataDirectory: fakeDataDir
      )
      XCTAssertTrue(prompt.contains(fakeSkillDir.appendingPathComponent("SKILL.md").path), "Failed for \(locale)")
      XCTAssertFalse(prompt.contains("SKILL.zh.md"), "Failed for \(locale)")
      XCTAssertTrue(prompt.contains(fakeExe), "Failed for \(locale)")
      XCTAssertTrue(prompt.contains(fakeDataDir.standardizedFileURL.path), "Failed for \(locale)")
      XCTAssertTrue(prompt.contains("Help me configure HyperCapslock"), "Failed for \(locale)")
      XCTAssertTrue(prompt.hasSuffix("My request: "), "Expected trailing empty request label for \(locale)")
    }
    XCTAssertTrue(zhPrompt.hasSuffix("我的需求："))
  }

  func testSkillPromptBuilderWithExampleRequestInZhAndNonZhLocales() throws {
    let fakeSkillDir = tempDir.appendingPathComponent("skills/hypercapslock", isDirectory: true)
    let fakeExe = "/Applications/HyperCapslock.app/Contents/MacOS/HyperCapslock"
    let fakeDataDir = tempDir.appendingPathComponent("config-dir", isDirectory: true)

    // 1. Direct `exampleRequest` parameter (trimmed & appended) + whitespace-only fallback
    let zhCustom = SkillPromptBuilder.buildPrompt(
      for: .zh,
      skillDirectory: fakeSkillDir,
      executablePath: fakeExe,
      dataDirectory: fakeDataDir,
      exampleRequest: "  帮我把 CapsLock + H/J/K/L 设成方向键  \n"
    )
    XCTAssertTrue(zhCustom.contains(fakeSkillDir.appendingPathComponent("SKILL.zh.md").path))
    XCTAssertFalse(zhCustom.contains(fakeSkillDir.appendingPathComponent("SKILL.md").path))
    XCTAssertTrue(zhCustom.hasSuffix("我的需求：帮我把 CapsLock + H/J/K/L 设成方向键"))

    let zhBlank = SkillPromptBuilder.buildPrompt(
      for: .zh,
      skillDirectory: fakeSkillDir,
      executablePath: fakeExe,
      dataDirectory: fakeDataDir,
      exampleRequest: "   \n  "
    )
    XCTAssertTrue(zhBlank.hasSuffix("我的需求："))

    for locale in [AppLocale.en, .ja, .de] {
      let nonZhCustom = SkillPromptBuilder.buildPrompt(
        for: locale,
        skillDirectory: fakeSkillDir,
        executablePath: fakeExe,
        dataDirectory: fakeDataDir,
        exampleRequest: "  Map CapsLock + H/J/K/L to arrow keys  \n"
      )
      XCTAssertTrue(nonZhCustom.contains(fakeSkillDir.appendingPathComponent("SKILL.md").path), "Failed for \(locale)")
      XCTAssertFalse(nonZhCustom.contains("SKILL.zh.md"), "Failed for \(locale)")
      XCTAssertTrue(nonZhCustom.hasSuffix("My request: Map CapsLock + H/J/K/L to arrow keys"), "Failed for \(locale)")
    }

    // 2. Curated `AISkillExample` (`vim_nav`): Chinese for `.zh`, English for `.en`/`.ja`/`.de`
    let vimExample = try XCTUnwrap(AISkillExample.all.first(where: { $0.slug == "vim_nav" }))
    let zhExamplePrompt = SkillPromptBuilder.buildExamplePrompt(
      vimExample,
      for: .zh,
      skillDirectory: fakeSkillDir,
      executablePath: fakeExe,
      dataDirectory: fakeDataDir
    )
    XCTAssertTrue(zhExamplePrompt.contains("SKILL.zh.md"))
    XCTAssertTrue(zhExamplePrompt.hasSuffix("我的需求：\(vimExample.zhRequest)"))

    for locale in [AppLocale.en, .ja, .de] {
      let enExamplePrompt = SkillPromptBuilder.buildExamplePrompt(
        vimExample,
        for: locale,
        skillDirectory: fakeSkillDir,
        executablePath: fakeExe,
        dataDirectory: fakeDataDir
      )
      XCTAssertTrue(enExamplePrompt.contains(fakeSkillDir.appendingPathComponent("SKILL.md").path), "Failed for \(locale)")
      XCTAssertFalse(enExamplePrompt.contains("SKILL.zh.md"), "Failed for \(locale)")
      XCTAssertTrue(enExamplePrompt.hasSuffix("My request: \(vimExample.enRequest)"), "Failed for \(locale)")
    }

    // 3. AI-Native badge, open agent label, reference examples title & About tagline localized across all 4 supported locales
    XCTAssertEqual(LocalizationManager.tables[.en]?["about.tagline"], "AI-Native macOS Hyper Key Engine")
    XCTAssertEqual(LocalizationManager.tables[.zh]?["about.tagline"], "AI 原生 macOS 超级键引擎")
    XCTAssertEqual(LocalizationManager.tables[.ja]?["about.tagline"], "AI ネイティブ macOS Hyper キーエンジン")
    XCTAssertEqual(LocalizationManager.tables[.de]?["about.tagline"], "KI-native macOS Hyper-Key-Engine")

    XCTAssertEqual(LocalizationManager.tables[.zh]?["ai_skill.step2.agents_label"], "可使用你喜欢的任意 AI 助手")
    XCTAssertEqual(LocalizationManager.tables[.en]?["ai_skill.step2.agents_label"], "Use any AI agent you prefer")
    XCTAssertEqual(LocalizationManager.tables[.ja]?["ai_skill.step2.agents_label"], "お好みの AI エージェントで利用可能")
    XCTAssertEqual(LocalizationManager.tables[.de]?["ai_skill.step2.agents_label"], "Mit jedem bevorzugten KI-Assistenten nutzbar")

    XCTAssertEqual(LocalizationManager.tables[.zh]?["ai_skill.examples.title"], "参考配置案例")
    XCTAssertEqual(LocalizationManager.tables[.en]?["ai_skill.examples.title"], "Reference Examples")
    XCTAssertEqual(LocalizationManager.tables[.ja]?["ai_skill.examples.title"], "参考設定例")
    XCTAssertEqual(LocalizationManager.tables[.de]?["ai_skill.examples.title"], "Konfigurationsbeispiele")

    for locale in AppLocale.allCases {
      XCTAssertEqual(LocalizationManager.tables[locale]?["ai_skill.badge"], "AI-NATIVE")
    }
  }

  func testSkillInstallerCopiesCanonicalAndLinksDetectedAgents() throws {
    let fakeSourceSkill = tempDir.appendingPathComponent("bundle-skills/hypercapslock", isDirectory: true)
    try FileManager.default.createDirectory(at: fakeSourceSkill.appendingPathComponent("references"), withIntermediateDirectories: true)
    try Data("# EN".utf8).write(to: fakeSourceSkill.appendingPathComponent("SKILL.md"))
    try Data("# ZH".utf8).write(to: fakeSourceSkill.appendingPathComponent("SKILL.zh.md"))

    let fakeHome = tempDir.appendingPathComponent("home", isDirectory: true)
    // Simulate detected `.claude` and `.gemini/config` agent roots, while `.cursor` is absent.
    try FileManager.default.createDirectory(at: fakeHome.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fakeHome.appendingPathComponent(".gemini/config"), withIntermediateDirectories: true)

    let res = try SkillInstaller.install(
      target: .all,
      sourceSkillDirectory: fakeSourceSkill,
      homeDirectory: fakeHome
    )

    let canonical = fakeHome.appendingPathComponent(".agents/skills/hypercapslock/SKILL.md")
    XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))

    let claudeLink = fakeHome.appendingPathComponent(".claude/skills/hypercapslock/SKILL.md")
    let agyLink = fakeHome.appendingPathComponent(".gemini/config/skills/hypercapslock/SKILL.zh.md")
    let cursorLink = fakeHome.appendingPathComponent(".cursor/skills/hypercapslock")
    XCTAssertTrue(FileManager.default.fileExists(atPath: claudeLink.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: agyLink.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: cursorLink.path))
    XCTAssertEqual(res.symlinks.filter { $0.status == "linked" }.count, 2)
  }
}
