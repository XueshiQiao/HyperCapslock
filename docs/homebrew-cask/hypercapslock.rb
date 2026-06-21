# Submission-ready cask for the OFFICIAL Homebrew Cask repository
# (Homebrew/homebrew-cask), so users can `brew install --cask hypercapslock`
# without first tapping a third-party repo.
#
# ⚠️ NOT submittable yet — blocked on Homebrew's notability rule. Self-submitted
# casks (PR author owns the upstream repo) require the upstream to have
# >= 225 stars OR >= 90 forks OR >= 90 watchers. See ./README.md for the plan.
#
# When ready: this file goes to Casks/h/hypercapslock.rb in a fork of
# Homebrew/homebrew-cask. Re-verify `version`/`sha256` against the real release
# asset (or let `brew create --cask <dmg-url>` recompute the sha256).
cask "hypercapslock" do
  version "26.06.106"
  sha256 "3753788751f14945f09512993fcfbaf5c115d71427044b4cf396888855c3eb3e"

  url "https://github.com/XueshiQiao/HyperCapslock/releases/download/v#{version}/HyperCapslock.dmg"
  name "HyperCapslock"
  desc "Remaps Caps Lock to a Hyper key for vim-style navigation and shortcuts"
  homepage "https://github.com/XueshiQiao/HyperCapslock"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "HyperCapslock.app"

  # Paths verified to exist on disk for the release bundle id
  # `me.xueshi.hypercapslock` (2026-06-21).
  zap trash: [
    "~/Library/Application Support/me.xueshi.hypercapslock",
    "~/Library/Caches/me.xueshi.hypercapslock",
    "~/Library/HTTPStorages/me.xueshi.hypercapslock",
    "~/Library/HTTPStorages/me.xueshi.hypercapslock.binarycookies",
    "~/Library/Preferences/me.xueshi.hypercapslock.plist",
  ]
end
