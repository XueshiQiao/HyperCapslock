import Foundation

/// Builds the localized AI bootstrap prompt and resolves bundled skill paths.
///
/// Language policy:
/// - `AppLocale.zh` → Chinese prompt + `<skillDir>/SKILL.zh.md`
/// - Every other locale (`en`, `ja`, `de`, …) → English prompt + `<skillDir>/SKILL.md`
enum SkillPromptBuilder {

  /// Resolves the bundled `skills/hypercapslock` directory inside `Bundle.main.resourceURL`,
  /// falling back to the repository's `skills/hypercapslock` directory when running unbundled.
  static func resolveBundledSkillDirectory(bundle: Bundle = .main) -> URL {
    if let resURL = bundle.resourceURL {
      let bundled = resURL.appendingPathComponent("skills/hypercapslock", isDirectory: true).standardizedFileURL
      if FileManager.default.fileExists(atPath: bundled.path) {
        return bundled
      }
    }
    // Fallback for unbundled test runs: walk up from `.../HyperCapslock/Sources/Support/SkillPromptBuilder.swift`
    let sourceURL = URL(fileURLWithPath: #filePath)
    let repoRoot = sourceURL
      .deletingLastPathComponent() // Support
      .deletingLastPathComponent() // Sources
      .deletingLastPathComponent() // HyperCapslock
      .deletingLastPathComponent() // <repo root>
    return repoRoot.appendingPathComponent("skills/hypercapslock", isDirectory: true).standardizedFileURL
  }

  /// Resolves the localized skill markdown file (`SKILL.zh.md` for `.zh`, `SKILL.md` otherwise).
  static func skillFileURL(for locale: AppLocale, skillDirectory: URL? = nil) -> URL {
    let dir = (skillDirectory ?? resolveBundledSkillDirectory()).standardizedFileURL
    let fileName = (locale == .zh) ? "SKILL.zh.md" : "SKILL.md"
    return dir.appendingPathComponent(fileName, isDirectory: false)
  }

  /// Resolves the active `AppLocale` without requiring `MainActor` / `NSApplication` (used by CLI).
  static func resolveActiveLocale() -> AppLocale {
    if let stored = UserDefaults.standard.string(forKey: "hc-locale"),
       let loc = AppLocale(rawValue: stored) {
      return loc
    }
    for code in Locale.preferredLanguages {
      let short = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
      if let loc = AppLocale(rawValue: short) {
        return loc
      }
    }
    return .en
  }

  /// Resolves the current binary's executable path for CLI invocations.
  static func resolveExecutablePath(bundle: Bundle = .main) -> String {
    if let exe = bundle.executableURL?.standardizedFileURL.path {
      return exe
    }
    let arg0 = CommandLine.arguments.first ?? "HyperCapslock"
    return URL(fileURLWithPath: arg0).standardizedFileURL.path
  }

  /// Builds the exact AI agent bootstrap prompt with runtime paths populated.
  ///
  /// When `exampleRequest` is nil/blank, the prompt ends with `我的需求：` (`zh`) or
  /// `My request: ` (all other locales) so the user can type right after pasting.
  /// When `exampleRequest` is provided, it is appended directly so the copied prompt
  /// is ready to send in a single paste.
  static func buildPrompt(
    for locale: AppLocale,
    skillDirectory: URL? = nil,
    executablePath: String? = nil,
    dataDirectory: URL? = nil,
    exampleRequest: String? = nil
  ) -> String {
    let skillDir = (skillDirectory ?? resolveBundledSkillDirectory()).standardizedFileURL
    let skillDocPath = skillFileURL(for: locale, skillDirectory: skillDir).path
    let cliPath = executablePath ?? resolveExecutablePath()
    let configDirPath = (dataDirectory ?? AppEnvironment.appSupportDirectory).standardizedFileURL.path
    let trimmed = exampleRequest?.trimmingCharacters(in: .whitespacesAndNewlines)
    let filledRequest = (trimmed?.isEmpty == false) ? trimmed : nil

    if locale == .zh {
      let header = """
      请帮我配置 macOS 上的 HyperCapslock（将 CapsLock 映射为 Hyper 键的工具）。

      当前运行环境路径：
      - Skill 配置指南："\(skillDocPath)"
      - CLI 可执行文件："\(cliPath)"
      - 当前配置目录："\(configDirPath)"（包含 action_mappings.yml 与 app_config.yml）

      请严格按以下步骤操作：
      1. 先完整阅读 "\(skillDocPath)"（并按需查阅同目录 references/ 下的参考文档），掌握 YAML 结构、JS keyCode 键码表、15 个内置动作 ID 及安全约束。
      2. 运行 "\(cliPath)" cli --data-dir "\(configDirPath)" info --json（以及 list-keys、list-builtins、list-input-sources）查看当前状态与已有配置。
      3. 修改配置时，先用 cli validate 预检，再通过 "\(cliPath)" cli --data-dir "\(configDirPath)" apply ...（或直接编辑后运行 cli reload）热加载生效；系统会自动在 backups/ 下保留带时间戳与 UUID 的历史备份（支持 cli backups / cli rollback 回滚）。
      4. 若下方“我的需求”已填写具体指令，请直接按该需求分析或执行；若为空，请先读取我当前的配置并简要告知准备就绪，然后询问我想添加或修改哪些快捷键。
      """
      let requestLine = filledRequest.map { "我的需求：\($0)" } ?? "我的需求："
      return header + "\n\n" + requestLine
    } else {
      let header = """
      Help me configure HyperCapslock on macOS (CapsLock → Hyper key remapper).

      Runtime paths on this Mac:
      - Skill guide: "\(skillDocPath)"
      - CLI binary: "\(cliPath)"
      - Active config directory: "\(configDirPath)" (contains action_mappings.yml and app_config.yml)

      Follow this workflow:
      1. Read "\(skillDocPath)" first (and any needed files in its sibling references/ folder) for the exact YAML schema, JS keyCodes, 15 built-in action IDs, and safety rules.
      2. Inspect the current setup using "\(cliPath)" cli --data-dir "\(configDirPath)" info --json (plus list-keys, list-builtins, and list-input-sources as needed).
      3. Always pre-flight validate edits with cli validate and apply live via "\(cliPath)" cli --data-dir "\(configDirPath)" apply ... (or cli reload), which hot-reloads the running app and saves timestamp+UUID backups in backups/ (recoverable via cli backups / cli rollback).
      4. If "My request" below contains a specific instruction, carry it out directly; if it is blank, read my current configuration first, confirm you are ready, and ask what CapsLock shortcuts or settings I want to add or change.
      """
      let requestLine = filledRequest.map { "My request: \($0)" } ?? "My request: "
      return header + "\n\n" + requestLine
    }
  }

  /// Convenience overload matching `buildPrompt(locale: ..., exampleRequest: ...)`.
  static func buildPrompt(
    locale: AppLocale,
    skillDirectory: URL? = nil,
    executablePath: String? = nil,
    dataDirectory: URL? = nil,
    exampleRequest: String? = nil
  ) -> String {
    buildPrompt(
      for: locale,
      skillDirectory: skillDirectory,
      executablePath: executablePath,
      dataDirectory: dataDirectory,
      exampleRequest: exampleRequest
    )
  }

  /// Builds a complete ready-to-send prompt for a curated `AISkillExample`.
  static func buildExamplePrompt(
    _ example: AISkillExample,
    for locale: AppLocale,
    skillDirectory: URL? = nil,
    executablePath: String? = nil,
    dataDirectory: URL? = nil
  ) -> String {
    buildPrompt(
      for: locale,
      skillDirectory: skillDirectory,
      executablePath: executablePath,
      dataDirectory: dataDirectory,
      exampleRequest: example.requestText(for: locale)
    )
  }
}

// MARK: - Curated Practical Prompt Examples

struct AISkillExample: Identifiable, Equatable {
  let slug: String
  let symbol: String
  let zhRequest: String
  let enRequest: String

  var id: String { slug }

  /// Follows the strict prompt language rule: Chinese request text when active UI
  /// locale is `.zh`, English request text for all non-Chinese locales (`en`, `ja`, `de`).
  func requestText(for locale: AppLocale) -> String {
    locale == .zh ? zhRequest : enRequest
  }

  static let all: [AISkillExample] = [
    AISkillExample(
      slug: "explore",
      symbol: "magnifyingglass",
      zhRequest: "帮我看一下我现在配了哪些快捷键和动作？顺便介绍一下 HyperCapslock 都支持哪些触发方式和高级映射功能，给我几个适合日常效率的推荐方案（先只分析不改配置）。",
      enRequest: "Inspect my current HyperCapslock mappings and summarize what I have configured. Also explain all trigger types and advanced mapping features HyperCapslock supports, with a few productivity recommendations (read-only analysis first)."
    ),
    AISkillExample(
      slug: "vim_nav",
      symbol: "arrow.up.and.down.and.arrow.left.and.right",
      zhRequest: "帮我设置一套经典 Vim 导航（保留我不冲突的已有配置）：CapsLock + H/J/K/L 映射为左/下/上/右方向键，CapsLock + U/D 为向上/向下跳 10 行，CapsLock + I/A 为跳到行首/行尾，CapsLock + W/B 为按词前进/后退。",
      enRequest: "Add classic Vim navigation while keeping my non-conflicting existing mappings: CapsLock + H/J/K/L for Left/Down/Up/Right arrows, CapsLock + U/D to jump 10 lines up/down, CapsLock + I/A for line start/end, and CapsLock + W/B for word forward/back."
    ),
    AISkillExample(
      slug: "input_source",
      symbol: "globe",
      zhRequest: "先用 CLI 查一下我这台 Mac 当前安装了哪些输入法，然后帮我配置：双击左 Shift 切换到英文输入法，双击右 Shift 切换到我的主力中文输入法。",
      enRequest: "First run the CLI to list the input sources installed on my Mac, then configure double-tap Left Shift to switch to my English keyboard layout and double-tap Right Shift to switch to my primary CJK/non-English input method."
    ),
    AISkillExample(
      slug: "open_app",
      symbol: "arrow.up.forward.app.fill",
      zhRequest: "帮我配置快速启动/切换应用：按 CapsLock + T 打开或切换到我电脑上安装的终端（如 Ghostty / iTerm / Terminal，若已在最前则自动隐藏），按 CapsLock + E 打开或切换访达（Finder）。",
      enRequest: "Configure quick app launch/toggle shortcuts: CapsLock + T to open or toggle-hide my installed terminal app (e.g. Ghostty, iTerm, or Terminal), and CapsLock + E to open or toggle-hide Finder."
    ),
    AISkillExample(
      slug: "per_app",
      symbol: "square.stack.3d.up.fill",
      zhRequest: "帮我给 CapsLock + R 配置按前台应用区分的规则：在浏览器（Safari / Chrome / Arc）里触发刷新页面 Cmd+R，在代码编辑器（Cursor / VS Code / Xcode）里触发运行快捷键，在其他应用里保持不触发或保留默认动作。",
      enRequest: "Configure per-app conditional bindings on CapsLock + R: send Cmd+R in browsers (Safari / Chrome / Arc), trigger Run in code editors (Cursor / VS Code / Xcode), and leave other apps unaffected."
    ),
    AISkillExample(
      slug: "backups_rollback",
      symbol: "clock.arrow.circlepath",
      zhRequest: "用 CLI 列出我最近的 HyperCapslock 配置备份记录，告诉我最近一次备份是什么时候生成的；如果我想退回上一版，帮我回滚到最新的一份备份并热刷新生效。",
      enRequest: "Use the CLI to list my HyperCapslock configuration backups, show when the most recent snapshot was created, and roll back to the latest backup with live hot-reload."
    ),
  ]
}

// MARK: - Local Agent Skill Installer

enum SkillAgentTarget: String, Codable, CaseIterable, Equatable {
  case all
  case claude
  case codex
  case cursor
  case antigravity
  case windsurf
  case cline
  case copilot
}

struct SkillInstallResult: Codable, Equatable {
  struct SymlinkOutcome: Codable, Equatable {
    let agent: String
    let linkPath: String
    let status: String // "linked" | "skipped_not_detected"
  }

  let sourceSkillDir: String
  let canonicalSkillDir: String
  let symlinks: [SymlinkOutcome]
}

enum SkillInstallError: LocalizedError {
  case bundledSkillNotFound(String)
  case invalidTarget(String)
  case io(String)

  var errorDescription: String? {
    switch self {
    case .bundledSkillNotFound(let path):
      return "Bundled skill directory not found at \(path)"
    case .invalidTarget(let raw):
      let allowed = SkillAgentTarget.allCases.map(\.rawValue).joined(separator: ", ")
      return "Invalid --target '\(raw)'; expected one of: \(allowed)"
    case .io(let msg):
      return msg
    }
  }
}

/// Copies the bundled `skills/hypercapslock` folder to `~/.agents/skills/hypercapslock`
/// and creates/updates symlinks inside local coding agents' skill folders.
enum SkillInstaller {

  private struct AgentDestination {
    let agent: SkillAgentTarget
    let detectRelativeDir: String
    let linkRelativePath: String
  }

  private static let destinations: [AgentDestination] = [
    AgentDestination(agent: .claude, detectRelativeDir: ".claude", linkRelativePath: ".claude/skills/hypercapslock"),
    AgentDestination(agent: .codex, detectRelativeDir: ".codex", linkRelativePath: ".codex/skills/hypercapslock"),
    AgentDestination(agent: .cursor, detectRelativeDir: ".cursor", linkRelativePath: ".cursor/skills/hypercapslock"),
    AgentDestination(agent: .antigravity, detectRelativeDir: ".gemini/config", linkRelativePath: ".gemini/config/skills/hypercapslock"),
    AgentDestination(agent: .antigravity, detectRelativeDir: ".gemini/antigravity", linkRelativePath: ".gemini/antigravity/skills/hypercapslock"),
    AgentDestination(agent: .windsurf, detectRelativeDir: ".codeium/windsurf", linkRelativePath: ".codeium/windsurf/skills/hypercapslock"),
    AgentDestination(agent: .cline, detectRelativeDir: ".cline", linkRelativePath: ".cline/skills/hypercapslock"),
    AgentDestination(agent: .copilot, detectRelativeDir: ".copilot", linkRelativePath: ".copilot/skills/hypercapslock"),
  ]

  static func install(
    target: SkillAgentTarget = .all,
    sourceSkillDirectory: URL? = nil,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> SkillInstallResult {
    let fm = FileManager.default
    let srcDir = (sourceSkillDirectory ?? SkillPromptBuilder.resolveBundledSkillDirectory()).standardizedFileURL
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: srcDir.path, isDirectory: &isDir), isDir.boolValue else {
      throw SkillInstallError.bundledSkillNotFound(srcDir.path)
    }

    let home = homeDirectory.standardizedFileURL
    let canonicalDir = home.appendingPathComponent(".agents/skills/hypercapslock", isDirectory: true).standardizedFileURL

    do {
      try fm.createDirectory(at: canonicalDir.deletingLastPathComponent(), withIntermediateDirectories: true)
      if srcDir.resolvingSymlinksInPath().standardizedFileURL.path != canonicalDir.resolvingSymlinksInPath().standardizedFileURL.path {
        let stagingDir = canonicalDir.deletingLastPathComponent()
          .appendingPathComponent(".hypercapslock-staging-\(UUID().uuidString.lowercased())", isDirectory: true)
        if fm.fileExists(atPath: stagingDir.path) {
          try? fm.removeItem(at: stagingDir)
        }
        try fm.copyItem(at: srcDir, to: stagingDir)
        // Remove existing canonical item (directory or symlink) before moving staging into place.
        if (try? fm.attributesOfItem(atPath: canonicalDir.path)) != nil {
          try fm.removeItem(at: canonicalDir)
        }
        try fm.moveItem(at: stagingDir, to: canonicalDir)
      }
    } catch {
      throw SkillInstallError.io("Failed to install canonical skill to \(canonicalDir.path): \(error.localizedDescription)")
    }

    let candidateDestinations: [AgentDestination] = {
      if target == .all {
        return destinations
      }
      return destinations.filter { $0.agent == target }
    }()

    var outcomes: [SkillInstallResult.SymlinkOutcome] = []
    for dest in candidateDestinations {
      let detectURL = home.appendingPathComponent(dest.detectRelativeDir, isDirectory: true)
      let linkURL = home.appendingPathComponent(dest.linkRelativePath, isDirectory: false)
      let detected = fm.fileExists(atPath: detectURL.path)

      // Under `all`, only symlink into agent roots that exist on this Mac; when a
      // specific `--target <agent>` is requested, create its skills dir explicitly.
      guard target != .all || detected else {
        outcomes.append(.init(agent: dest.agent.rawValue, linkPath: linkURL.path, status: "skipped_not_detected"))
        continue
      }

      do {
        try fm.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.attributesOfItem(atPath: linkURL.path)) != nil {
          try fm.removeItem(at: linkURL)
        }
        try fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: canonicalDir.path)
        outcomes.append(.init(agent: dest.agent.rawValue, linkPath: linkURL.path, status: "linked"))
      } catch {
        throw SkillInstallError.io("Failed to link \(linkURL.path) → \(canonicalDir.path): \(error.localizedDescription)")
      }
    }

    return SkillInstallResult(
      sourceSkillDir: srcDir.path,
      canonicalSkillDir: canonicalDir.path,
      symlinks: outcomes
    )
  }
}
