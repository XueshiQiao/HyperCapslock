# Submitting HyperCapslock to the official Homebrew Cask

提交 HyperCapslock 到 Homebrew 官方库的就绪材料 + 计划。

This folder holds the **submission-ready cask** ([`hypercapslock.rb`](./hypercapslock.rb))
for [`Homebrew/homebrew-cask`](https://github.com/Homebrew/homebrew-cask), plus
the plan to get it accepted. Goal: let users run

```bash
brew install --cask hypercapslock
```

without first tapping the third-party repo (today's command is
`brew install --cask XueshiQiao/tap/hypercapslock`).

## ⚠️ The blocker: notability

Homebrew Cask only accepts apps above a popularity bar
([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)). **Self-submitted**
casks (the PR author owns the upstream repo — i.e. us) face the higher bar:

| Submitter | Threshold (any one) | HyperCapslock now | Pass? |
|-----------|---------------------|-------------------|-------|
| Third party | ≥ 75 stars **/** ≥ 30 forks **/** ≥ 30 watchers | 7 / 0 / 0 | ❌ |
| **Author (us)** | **≥ 225 stars / ≥ 90 forks / ≥ 90 watchers** | **7 / 0 / 0** | ❌ |

Submitting before clearing this bar gets the PR closed as "not notable enough".
So the cask is **prepared and parked** here until the repo grows.

Everything else Homebrew checks is already satisfied: Developer ID signed +
notarized (passes Gatekeeper), stable versioned download URL, a homepage, and
GPL-3.0 source that ships official binaries (so it belongs in `cask`, not
`homebrew/core`).

## Submission procedure (run once notability is met)

```bash
# 1) Fork Homebrew/homebrew-cask on GitHub, then clone your fork.
# 2) Generate the cask (downloads, computes sha256, opens an editor):
brew create --cask \
  https://github.com/XueshiQiao/HyperCapslock/releases/download/v26.06.106/HyperCapslock.dmg \
  --set-name hypercapslock
#    → replace the template with this folder's hypercapslock.rb

# 3) Audit a NEW cask (note: `--new --cask`, not the old `--new-cask`):
brew audit --new --cask hypercapslock

# 4) Auto-fix style:
brew style --fix hypercapslock

# 5) Local install/uninstall/zap test (force local file, skip the API):
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1
brew install --cask hypercapslock
brew uninstall --cask hypercapslock
brew zap --cask hypercapslock

# 6) Open the PR:
git checkout -b hypercapslock
git add Casks/h/hypercapslock.rb       # official repo shards casks by first letter
git commit -v                          # title e.g. "Add HyperCapslock 26.06.106"
git push <your-fork> hypercapslock
#    → open the PR from the printed URL; Homebrew CI runs audit/style/install.
```

## Keeping this file current

The CI release pipeline already updates the **third-party tap**
(`XueshiQiao/homebrew-tap`) on every release. This file is a manual snapshot —
bump `version` + `sha256` here only when actually preparing the official PR
(or just regenerate via `brew create --cask`).
