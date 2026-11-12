import SwiftUI
import AppKit

/// Dedicated top-level "AI Setup / AI 辅助配置" page (Option B layout):
/// - Spacious Hero card (~80% of initial viewport) with a clean header, vertical 1-2-3 steps
///   sharing identical step-number badges, primary Copy CTA (`ai_skill.copy_prompt`) embedded
///   right on the trailing side of Step 1, open agent compatibility pills in Step 2, and quiet
///   secondary footer controls (`ai_skill.install_skill`, `ai_skill.reveal_skill`).
/// - De-emphasized 2-column "Reference Examples / 参考配置案例" section below (`ai_skill.example.<slug>`)
///   styled in calm monochrome with no bright category tiles or colored tags, peeking naturally
///   at the bottom edge of the default window.
struct AISkillPage: View {
  @EnvironmentObject var app: AppState
  @EnvironmentObject var config: ConfigStore
  @EnvironmentObject var loc: LocalizationManager
  @Environment(\.colorScheme) private var colorScheme

  @State private var copiedID: String?
  @State private var copyFeedbackResetWork: DispatchWorkItem?
  @State private var installFeedback: InstallFeedback?

  private static let agentNames: [String] = [
    "Claude Code",
    "Codex",
    "Cursor",
    "Antigravity",
    "WorkBuddy",
  ]

  private struct InstallFeedback: Equatable {
    let text: String
    let isError: Bool
  }

  private var examplePairs: [[AISkillExample]] {
    let all = AISkillExample.all
    return stride(from: 0, to: all.count, by: 2).map { idx in
      Array(all[idx..<min(idx + 2, all.count)])
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        heroCard
        examplesSection
      }
      .padding(.horizontal, 24)
      .padding(.top, 18)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(loc.t("nav.ai_skill"))
    // Keep title-bar height identical across all sidebar pages.
    .toolbar {
      ToolbarItem {
        Button {
          revealSkillInFinder()
        } label: {
          Image(systemName: "folder")
        }
        .help(loc.t("ai_skill.reveal_skill"))
        .accessibilityIdentifier("ai_skill.toolbar_reveal")
      }
    }
  }

  // MARK: - Hero Card (Option B)

  private var heroCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      heroHeader

      Spacer(minLength: 18)

      stepsStack

      Spacer(minLength: 18)

      heroFooter
    }
    .padding(.horizontal, 26)
    .padding(.top, 24)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, minHeight: 448, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(
          Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.075),
          lineWidth: 0.75
        )
    )
    .shadow(
      color: .black.opacity(colorScheme == .dark ? 0.20 : 0.035),
      radius: 10,
      x: 0,
      y: 3
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ai_skill.hero")
  }

  private var heroHeader: some View {
    HStack(alignment: .center, spacing: 14) {
      heroIconTile

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .center, spacing: 8) {
          Text(loc.t("ai_skill.hero_title"))
            .font(.system(size: 17.5, weight: .semibold))
            .foregroundStyle(.primary)

          Text(loc.t("ai_skill.badge"))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(Color.teal.opacity(0.90))
            .padding(.horizontal, 7.5)
            .padding(.vertical, 2)
            .background(
              Capsule()
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.14 : 0.09))
            )
            .overlay(
              Capsule()
                .strokeBorder(Color.teal.opacity(colorScheme == .dark ? 0.30 : 0.22), lineWidth: 0.6)
            )
            .accessibilityIdentifier("ai_skill.badge")
        }

        Text(loc.t("ai_skill.desc"))
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
  }

  private var heroIconTile: some View {
    Image(systemName: "sparkles")
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(
        LinearGradient(
          colors: [Color.teal, Color.accentColor],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: 40, height: 40)
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.teal.opacity(colorScheme == .dark ? 0.18 : 0.11),
                Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.11),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .strokeBorder(
            Color.teal.opacity(colorScheme == .dark ? 0.28 : 0.18),
            lineWidth: 0.75
          )
      )
  }

  // MARK: - Vertical 1-2-3 Steps (Uniform Number Badges)

  private var stepsStack: some View {
    VStack(spacing: 11) {
      // Step 1: Copy prompt + primary CTA button embedded on trailing side
      stepCard {
        HStack(alignment: .center, spacing: 16) {
          HStack(alignment: .top, spacing: 12) {
            stepBadge(1)
            VStack(alignment: .leading, spacing: 3) {
              Text(loc.t("ai_skill.step1.title"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
              Text(loc.t("ai_skill.step1.desc"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }

          Spacer(minLength: 12)

          Button {
            copyBasePrompt()
          } label: {
            HStack(spacing: 6) {
              Image(systemName: copiedID == "base" ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12.5, weight: .semibold))
              Text(copiedID == "base" ? loc.t("ai_skill.copied") : loc.t("ai_skill.copy_prompt"))
                .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
          }
          .buttonStyle(.borderedProminent)
          .tint(copiedID == "base" ? .green : .accentColor)
          .controlSize(.large)
          .accessibilityIdentifier("ai_skill.copy_prompt")
        }
      }

      // Step 2: Paste into any preferred AI assistant + quiet monochrome agent pills
      stepCard {
        HStack(alignment: .top, spacing: 12) {
          stepBadge(2)
          VStack(alignment: .leading, spacing: 3) {
            Text(loc.t("ai_skill.step2.title"))
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)

            Text(loc.t("ai_skill.step2.desc"))
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
              Text(loc.t("ai_skill.step2.agents_label"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("ai_skill.agents_label")

              AgentFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Self.agentNames, id: \.self) { agent in
                  agentPill(agent)
                }
              }
            }
            .padding(.top, 6)
          }
          Spacer(minLength: 0)
        }
      }

      // Step 3: Auto-validate, snapshot backup, and live hot-reload
      stepCard {
        HStack(alignment: .top, spacing: 12) {
          stepBadge(3)
          VStack(alignment: .leading, spacing: 3) {
            Text(loc.t("ai_skill.step3.title"))
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
            Text(loc.t("ai_skill.step3.desc"))
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
      }
    }
  }

  /// Uniform step-number badge shared identically across Steps 1, 2, and 3 so Step 1
  /// never looks like an active/selected tab in a multi-page wizard.
  private func stepBadge(_ number: Int) -> some View {
    Text("\(number)")
      .font(.system(size: 12.5, weight: .bold, design: .rounded))
      .foregroundStyle(Color.accentColor)
      .frame(width: 26, height: 26)
      .background(
        Circle()
          .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10))
      )
      .overlay(
        Circle()
          .strokeBorder(
            Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.18),
            lineWidth: 0.75
          )
      )
      .padding(.top, 1)
  }

  /// Uniform container surface shared identically across Steps 1, 2, and 3.
  private func stepCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.028))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .strokeBorder(
            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055),
            lineWidth: 0.75
          )
      )
  }

  private func agentPill(_ name: String) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color.secondary.opacity(0.45))
        .frame(width: 4.5, height: 4.5)
      Text(name)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8.5)
    .padding(.vertical, 3.5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(
          Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.065),
          lineWidth: 0.5
        )
    )
  }

  // MARK: - Quiet Secondary Footer inside Hero Card

  private var heroFooter: some View {
    VStack(alignment: .leading, spacing: 11) {
      Rectangle()
        .fill(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.055))
        .frame(height: 0.5)

      HStack(alignment: .center, spacing: 10) {
        if let fb = installFeedback {
          Label(
            fb.text,
            systemImage: fb.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
          )
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(fb.isError ? .red : .green)
          .lineLimit(1)
          .truncationMode(.tail)
          .accessibilityIdentifier("ai_skill.install_status")
        } else {
          Text(loc.t("ai_skill.install_hint"))
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        Spacer(minLength: 10)

        HStack(spacing: 6) {
          QuietSecondaryLinkButton(
            title: loc.t("ai_skill.install_skill"),
            systemImage: "square.and.arrow.down",
            action: installSkillToAgents
          )
          .accessibilityIdentifier("ai_skill.install_skill")

          Text("·")
            .font(.system(size: 12))
            .foregroundStyle(.quaternary)

          QuietSecondaryLinkButton(
            title: loc.t("ai_skill.reveal_skill"),
            systemImage: "folder",
            action: revealSkillInFinder
          )
          .accessibilityIdentifier("ai_skill.reveal_skill")
        }
      }
    }
  }

  // MARK: - De-emphasized Reference Examples Section (Quiet 2-Column Cards)

  private var examplesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(loc.t("ai_skill.examples.title"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("ai_skill.examples.title")

        Text(loc.t("ai_skill.examples.subtitle"))
          .font(.system(size: 11.5))
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 2)

      VStack(spacing: 10) {
        ForEach(Array(examplePairs.enumerated()), id: \.offset) { _, row in
          HStack(alignment: .top, spacing: 10) {
            ForEach(row) { ex in
              QuietExampleCard(
                example: ex,
                title: loc.t("ai_skill.ex.\(ex.slug).title"),
                symbol: quietSymbol(for: ex),
                promptPreview: ex.requestText(for: loc.locale),
                copyLabel: loc.t("ai_skill.copy_example"),
                copiedLabel: loc.t("ai_skill.copied"),
                isCopied: copiedID == ex.slug,
                onCopy: { copyExamplePrompt(ex) }
              )
            }
            if row.count == 1 {
              Color.clear.frame(maxWidth: .infinity)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func quietSymbol(for example: AISkillExample) -> String {
    switch example.slug {
    case "explore": return "magnifyingglass"
    case "vim_nav": return "arrow.up.and.down.and.arrow.left.and.right"
    case "input_source": return "globe"
    case "open_app": return "terminal"
    case "per_app": return "square.stack.3d.up"
    case "backups_rollback": return "clock.arrow.circlepath"
    default: return example.symbol
    }
  }

  // MARK: - Actions

  private func copyBasePrompt() {
    let prompt = SkillPromptBuilder.buildPrompt(
      for: loc.locale,
      dataDirectory: config.dataDirectory
    )
    writeToClipboard(prompt, feedbackID: "base", toastKey: "toast.ai_prompt_copied")
  }

  private func copyExamplePrompt(_ example: AISkillExample) {
    let prompt = SkillPromptBuilder.buildExamplePrompt(
      example,
      for: loc.locale,
      dataDirectory: config.dataDirectory
    )
    writeToClipboard(prompt, feedbackID: example.slug, toastKey: "toast.ai_example_copied")
  }

  private func writeToClipboard(_ text: String, feedbackID: String, toastKey: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)

    withAnimation(.easeInOut(duration: 0.15)) {
      copiedID = feedbackID
    }
    copyFeedbackResetWork?.cancel()
    let reset = DispatchWorkItem {
      withAnimation(.easeInOut(duration: 0.15)) {
        if copiedID == feedbackID {
          copiedID = nil
        }
      }
    }
    copyFeedbackResetWork = reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: reset)

    app.showToast(loc.t(toastKey))
  }

  private func installSkillToAgents() {
    do {
      let res = try SkillInstaller.install(target: .all)
      let linkedCount = res.symlinks.filter { $0.status == "linked" }.count
      let msg = loc.t("toast.ai_skill_installed", ["count": "\(linkedCount)"])
      withAnimation(.easeInOut(duration: 0.15)) {
        installFeedback = InstallFeedback(text: msg, isError: false)
      }
      app.showToast(msg)
    } catch {
      let msg = loc.t("toast.ai_skill_install_failed", ["error": error.localizedDescription])
      withAnimation(.easeInOut(duration: 0.15)) {
        installFeedback = InstallFeedback(text: msg, isError: true)
      }
      app.showToast(msg, isError: true)
    }
  }

  private func revealSkillInFinder() {
    let skillDir = SkillPromptBuilder.resolveBundledSkillDirectory()
    let skillFile = SkillPromptBuilder.skillFileURL(for: loc.locale, skillDirectory: skillDir)
    let fm = FileManager.default
    if fm.fileExists(atPath: skillFile.path) {
      NSWorkspace.shared.activateFileViewerSelecting([skillFile])
    } else if fm.fileExists(atPath: skillDir.path) {
      NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: skillDir.path)
    } else {
      app.showToast(loc.t("toast.ai_skill_missing"), isError: true)
    }
  }
}

// MARK: - Quiet Secondary Footer Link Button

private struct QuietSecondaryLinkButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: systemImage)
          .font(.system(size: 10.5, weight: .medium))
        Text(title)
          .font(.system(size: 11.5, weight: .medium))
      }
      .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
  }
}

// MARK: - Quiet Monochrome 2-Column Example Card

private struct QuietExampleCard: View {
  let example: AISkillExample
  let title: String
  let symbol: String
  let promptPreview: String
  let copyLabel: String
  let copiedLabel: String
  let isCopied: Bool
  let onCopy: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovered = false

  private var borderColor: Color {
    if isCopied {
      return Color.green.opacity(0.45)
    }
    if isHovered {
      return Color.accentColor.opacity(0.30)
    }
    return Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.06)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .center, spacing: 7) {
        Image(systemName: symbol)
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(.tertiary)
          .frame(width: 16, height: 16)

        Text(title)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(.primary.opacity(0.88))
          .lineLimit(1)

        Spacer(minLength: 6)

        Button(action: onCopy) {
          HStack(spacing: 4) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 10, weight: .semibold))
            Text(isCopied ? copiedLabel : copyLabel)
              .font(.system(size: 11, weight: isCopied || isHovered ? .semibold : .medium))
          }
          .foregroundStyle(
            isCopied
              ? Color.green
              : (isHovered ? Color.accentColor : Color.secondary.opacity(0.65))
          )
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(
                isCopied
                  ? Color.green.opacity(0.12)
                  : (isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
              )
          )
          .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai_skill.example.\(example.slug).copy")
      }

      Text("“\(promptPreview)”")
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary.opacity(0.82))
        .lineSpacing(2)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(
          Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.72 : 0.84)
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(borderColor, lineWidth: 0.75)
    )
    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    .onTapGesture {
      onCopy()
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("ai_skill.example.\(example.slug)")
  }
}

// MARK: - Wrapping Flow Layout for Agent Pills

private struct AgentFlowLayout: Layout {
  var spacing: CGFloat = 6
  var lineSpacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var rowHeight: CGFloat = 0
    var usedWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX > 0 && currentX + size.width > maxWidth {
        usedWidth = max(usedWidth, currentX - spacing)
        currentX = 0
        currentY += rowHeight + lineSpacing
        rowHeight = 0
      }
      currentX += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    if currentX > 0 {
      usedWidth = max(usedWidth, currentX - spacing)
    }
    return CGSize(width: usedWidth, height: currentY + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var currentX = bounds.minX
    var currentY = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX > bounds.minX && currentX + size.width > bounds.maxX {
        currentX = bounds.minX
        currentY += rowHeight + lineSpacing
        rowHeight = 0
      }
      subview.place(
        at: CGPoint(x: currentX, y: currentY),
        anchor: .topLeading,
        proposal: ProposedViewSize(size)
      )
      currentX += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
