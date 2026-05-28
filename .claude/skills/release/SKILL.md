---
name: release
description: Cut a new HyperCapslock release end-to-end — write cumulative bilingual notes, run bump-version.sh, watch CI, verify Homebrew cask + Apps Gallery cascades.
disable-model-invocation: true
---

# Release HyperCapslock

End-to-end release routine. Owns the full chain from notes through Homebrew cask + Apps Gallery propagation. Treat each numbered phase as a checkpoint — show the user what you're about to do, then execute.

The release flow shares conventions with the AnyDrag project (`.claude/skills/release/SKILL.md` there): cumulative HTML release notes, bare-@mention contributor credit, `repository_dispatch` to shared tap, etc. The blueprint is documented in `XueshiQiao/macos-app-scaffold`.

## Phase 0 — Validate state

1. `git status` — bail if there are uncommitted changes that aren't yours to ship.
2. `git log --all --oneline -10` — list local-only branches whose commits aren't on `main` yet. Cherry-pick (not merge) if you want them in this release; that preserves the linear history of `chore(release): YY.MM.build` + `Update cask for hypercapslock` commits.
3. `gh issue list --repo XueshiQiao/HyperCapslock --state open` — note any open issues that the new release likely closes. You'll close these in Phase 6.

## Phase 1 — Prepend this version's notes to `RELEASE_NOTES.html`

The file is cumulative — every past version stays in it. You add a NEW per-version block at the TOP. Two `<h3>` sections, EN first then `更新内容` (matched by the heading shape the CI extractor + Sparkle appcast both rely on).

**Pick the version first** (it determines the heading text). CalVer is `YY.MM.<build>`:
- `YY.MM` = current UTC year + month (e.g. `26.05`).
- `<build>` = current `CURRENT_PROJECT_VERSION` in `project.yml` + 1.

Then prepend:

```html
<h3>What's New in YY.MM.<build></h3>
<ul>
  <li><b>Feature name</b> — Plain-English description, ≤2 sentences. Credit contributors with a BARE @handle (not an <a> link — see below).</li>
  ...
</ul>

<h3>YY.MM.<build> 更新内容</h3>
<ul>
  <li><b>功能名称</b> — 简体中文描述。贡献者用 @handle 标注（同样裸写，不要包 <a>）。</li>
  ...
</ul>
```

**Contributor credit convention:** write a **bare** `@handle`, not `<a href="...">@handle</a>`. The CI uses each version's section as the GitHub Release body; a bare handle lands the contributor in the release's **Contributors** avatar list and gets autolinked. A handle wrapped in `<a>` is skipped by GitHub's autolinker, so neither happens. Renders as plain text in Sparkle — acceptable. `#N` issue/PR refs CAN stay as `<a>` links so they're clickable inside Sparkle too.

**Notification:** a release-body @mention is **credit, not a notification** — GitHub doesn't reliably ping. The reliable ping happens in the Phase 6 issue comment, which must @mention them.

**Translation accuracy:** write each language directly, don't translate word-for-word. Mirror structure (same bullets, same order, same `<b>` headers), but use natural phrasing per locale. The `@handle` stays identical across languages — it's a handle, not text.

`scripts/bump-version.sh` warns at Phase 3 if there's no `<h3>What's New in <new-version></h3>` block in the file yet. Heed the warning before pushing.

## Phase 2 — `bump-version.sh` (no `--push`)

Leave the `RELEASE_NOTES.html` edits from Phase 1 **uncommitted** — the script folds them into the same release commit.

```bash
scripts/bump-version.sh
```

What it does:
- Computes the new version from `YY.MM.<cur_build+1>`.
- Refuses to run if the working tree has changes other than `RELEASE_NOTES.html`. (Uncommitted notes edits are expected and welcome.)
- Warns if `RELEASE_NOTES.html` has no block for the new version yet (Phase 1 not yet done — fix it before continuing).
- Edits `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- Stages `project.yml` + `RELEASE_NOTES.html` and commits with message `chore(release): YY.MM.<build>`, then tags `vYY.MM.<build>`.

Do NOT pass `--push` yet — sanity-check first.

## Phase 3 — Sanity-check then push

```bash
# Confirm what was bumped + tagged matches HEAD.
git show --stat HEAD
git tag --points-at HEAD     # → vYY.MM.<build>

# Tag MUST point at the same commit as HEAD; if not, fix before pushing.
[ "$(git rev-parse "vYY.MM.<build>")" = "$(git rev-parse HEAD)" ] || echo "TAG MISMATCH — DO NOT PUSH"

# Push main first, then the tag — gives CI a clean view.
git push origin main
git push origin vYY.MM.<build>
```

Tagging triggers `.github/workflows/build.yml` which: builds universal → signs (inside-out, including embedded Sparkle.framework) → notarizes → staples → DMG → signs DMG with Sparkle EdDSA → writes `appcast.xml` (embeds the WHOLE `RELEASE_NOTES.html` into `<description>` CDATA) → extracts this version's section into `release_body.html` → publishes GitHub Release with the DMG + appcast.xml + latest.json attached and the per-version HTML as the body → fires `repository_dispatch` to `XueshiQiao/homebrew_tap` (event `update_cask`) AND to `XueshiQiao/XueshiQiao.github.io` (event `app_released`).

**Gotcha — tags don't follow rebase.** If origin moved while you were preparing, `git pull --rebase` must happen BEFORE the tag is created, not after. The sanity-check `[ "$(git rev-parse <tag>)" = "$(git rev-parse HEAD)" ]` catches the mismatch.

## Phase 4 — Watch CI

```bash
RUN=$(gh run list --repo XueshiQiao/HyperCapslock --workflow build.yml --limit 5 --json databaseId,headBranch --jq '.[] | select(.headBranch=="vYY.MM.<build>") | .databaseId' | head -1)
gh run watch "$RUN" --repo XueshiQiao/HyperCapslock --exit-status
```

If conclusion isn't `success`, stop and report. The cascades in Phase 5 won't fire on a failed build.

## Phase 5 — Verify the cascades (now automatic)

**Don't manually bump the cask or the gallery.** The release workflow's final two steps (`Trigger Homebrew Tap Update` and the gallery dispatch) fired both. Verify:

```bash
# Tap regeneration of Casks/hypercapslock.rb
gh run list --repo XueshiQiao/homebrew_tap --workflow update-casks.yml --limit 1 \
  --json status,conclusion,createdAt,displayTitle
gh api repos/XueshiQiao/homebrew_tap/contents/Casks/hypercapslock.rb --jq '.content' | base64 -d | head -4

# Gallery rebuild
gh run list --repo XueshiQiao/XueshiQiao.github.io --workflow deploy.yml --limit 1 \
  --json status,conclusion,event,createdAt
```

Both should be `completed` / `success` within a few minutes after the AnyDrag/HCL CI completes.

Requirements (one-time setup, already in place on this repo):
- `HOMEBREW_TAP_PAT` secret — PAT with `Contents: Read and write` on `XueshiQiao/homebrew_tap`.
- `GALLERY_UPDATE_PAT` secret — PAT with `Contents: Read and write` on `XueshiQiao/XueshiQiao.github.io`.

If either dispatch doesn't fire, check the workflow run log for the corresponding step; usually it's a missing/expired PAT (the step `if`-condition gates on the secret presence so the skip can be silent in old versions of the workflow — the current one prints a `::warning::`).

To re-fire a missed dispatch manually:

```bash
gh workflow run update-casks.yml --repo XueshiQiao/homebrew_tap -f app_token=hypercapslock
# Gallery has no manual app_token form; trigger a no-op push to main if needed.
```

Verify the public brew install actually works:

```bash
brew update
brew install --cask XueshiQiao/tap/hypercapslock
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "/Applications/HyperCapslock.app/Contents/Info.plist"  # → YY.MM.<build>
spctl -a -t exec -vv /Applications/HyperCapslock.app    # → Notarized Developer ID
brew uninstall --cask hypercapslock                     # leave clean state
```

## Phase 6 — Close referenced issues, ping reporters

For each issue identified in Phase 0:

```bash
gh issue close <N> --repo XueshiQiao/HyperCapslock \
  --comment "Released in [vYY.MM.<build>](https://github.com/XueshiQiao/HyperCapslock/releases/tag/vYY.MM.<build>). <One-line how-to-use.> @reporter thanks for the report!"
```

**@-mention the reporter here.** This is the reliable contributor notification (release-body mentions only add a Contributors avatar — they don't ping). An issue comment notifies the issue's author/participants regardless, and the explicit @mention makes the credit unambiguous.

## Phase 7 — Final report

Tell your human partner:
- Release URL, CI run URL.
- Tap workflow run URL + commit on `homebrew_tap`.
- Gallery deploy run URL.
- Issues closed with their numbers and one-line summaries.
- Any deltas from a clean run.

---

## Constraints and gotchas

- **Build number must increase every release** (`CURRENT_PROJECT_VERSION`). Sparkle compares `CFBundleVersion`, not `CFBundleShortVersionString`, to decide "is this newer." `bump-version.sh` is the single touchpoint; never hand-edit.
- **Tags don't follow rebase.** Hit live in earlier projects: pre-release prep had a `git pull --rebase` *after* `git tag`, so the tag stayed at the pre-rebase orphan commit. Pushing it triggered CI, the build succeeded, the appcast step's final push back to `main` failed (`! [rejected] HEAD -> main`), the GitHub Release was never created, and `gh release view` returned "release not found." Prevention: tag *after* rebase, and run the sanity-check before pushing.
- **`RELEASE_NOTES.html` stays HTML — don't "upgrade" it to JSON/YAML.** It's not an internal data file; it's the rendered payload shown to end users in two places. Sparkle's update dialog renders the HTML natively (it's the appcast `<description>` CDATA), and GitHub renders the inline HTML in the Release body. JSON/YAML can't be displayed to users.
- **Don't put the cask file in this repo.** It belongs in `XueshiQiao/homebrew_tap`, auto-generated by that repo's `update-casks.yml` workflow from the `latest.json` this release publishes. See the macos-app-scaffold blueprint for the full pipeline.
- **Codex review** per global rule: invoke after Phase 5 verifies, scope = files touched in this release. Skip only if your human partner has explicitly said "ignore codex" in this session.
