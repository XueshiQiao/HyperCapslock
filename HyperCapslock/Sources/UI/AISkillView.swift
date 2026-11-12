import SwiftUI
import AppKit

/// Dedicated top-level "AI Setup / AI 辅助配置" page:
/// - Hero card with 3-step visual workflow, 1-click Copy Base Prompt (`ai_skill.copy_prompt`),
///   Install Skill to Local Agents (`ai_skill.install_skill`), and Reveal in Finder (`ai_skill.reveal_skill`).
/// - 6 curated, real-world prompt example cards (`ai_skill.example.<slug>`) where clicking Copy
///   places the COMPLETE ready-to-send prompt (environment header + `SKILL.zh.md`/`SKILL.md` +
///   CLI path + active config dir + pre-filled `我的需求：…` / `My request: …`) onto the clipboard.
struct AISkillPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    @State private var copiedID: String?
    @State private var copyFeedbackResetWork: DispatchWorkItem?
    @State private var installFeedback: InstallFeedback?

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
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                examplesSection
            }
            .padding(20)
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

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 13) {
                heroIconTile
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(loc.t("ai_skill.hero_title"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(loc.t("ai_skill.badge"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(Color.teal)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.teal.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.teal.opacity(0.32), lineWidth: 0.75))
                            .accessibilityIdentifier("ai_skill.badge")
                    }
                    Text(loc.t("ai_skill.desc"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    copyBasePrompt()
                } label: {
                    Label(
                        copiedID == "base" ? loc.t("ai_skill.copied") : loc.t("ai_skill.copy_prompt"),
                        systemImage: copiedID == "base" ? "checkmark" : "doc.on.doc"
                    )
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(copiedID == "base" ? .green : .accentColor)
                .controlSize(.regular)
                .accessibilityIdentifier("ai_skill.copy_prompt")
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                stepColumn(
                    number: 1,
                    title: loc.t("ai_skill.step1.title"),
                    desc: loc.t("ai_skill.step1.desc"),
                    tint: .teal
                )
                stepArrow
                stepColumn(
                    number: 2,
                    title: loc.t("ai_skill.step2.title"),
                    desc: loc.t("ai_skill.step2.desc"),
                    tint: .blue
                )
                stepArrow
                stepColumn(
                    number: 3,
                    title: loc.t("ai_skill.step3.title"),
                    desc: loc.t("ai_skill.step3.desc"),
                    tint: .purple
                )
            }
            .padding(.vertical, 2)

            Divider()

            HStack(spacing: 10) {
                Button {
                    installSkillToAgents()
                } label: {
                    Label(loc.t("ai_skill.install_skill"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ai_skill.install_skill")

                Button {
                    revealSkillInFinder()
                } label: {
                    Label(loc.t("ai_skill.reveal_skill"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ai_skill.reveal_skill")

                if let fb = installFeedback {
                    Label(
                        fb.text,
                        systemImage: fb.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(fb.isError ? .red : .green)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("ai_skill.install_status")
                } else {
                    Text(loc.t("ai_skill.install_hint"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_skill.hero")
    }

    private var heroIconTile: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.teal, Color.blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(0.20))
            )
    }

    private func stepColumn(number: Int, title: String, desc: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 5)
    }

    // MARK: - Practical Examples Section

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("ai_skill.examples.title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(loc.t("ai_skill.examples.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(Array(examplePairs.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { ex in
                            exampleCard(ex)
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

    private func exampleCard(_ example: AISkillExample) -> some View {
        let accent = accentColor(for: example.slug)
        let isCopied = (copiedID == example.slug)
        let promptPreview = example.requestText(for: loc.locale)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(symbol: example.symbol, color: accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.t("ai_skill.ex.\(example.slug).title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc.t("ai_skill.ex.\(example.slug).tag"))
                        .modifier(BadgeStyle(color: accent))
                }
                Spacer(minLength: 0)
            }

            Text("“\(promptPreview)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: 4)

            HStack {
                Spacer(minLength: 0)
                Button {
                    copyExamplePrompt(example)
                } label: {
                    Label(
                        isCopied ? loc.t("ai_skill.copied") : loc.t("ai_skill.copy_example"),
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .tint(isCopied ? .green : accent)
                .controlSize(.small)
                .accessibilityIdentifier("ai_skill.example.\(example.slug).copy")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isCopied ? Color.green.opacity(0.45) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_skill.example.\(example.slug)")
    }

    private func accentColor(for slug: String) -> Color {
        switch slug {
        case "explore": return .blue
        case "vim_nav": return .indigo
        case "input_source": return .purple
        case "open_app": return .teal
        case "per_app": return .orange
        case "backups_rollback": return .green
        default: return .blue
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
