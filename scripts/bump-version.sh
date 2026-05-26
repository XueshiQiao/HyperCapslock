#!/usr/bin/env bash
#
# Cut a new HyperCapslock version.
#
# Scheme: MARKETING_VERSION = "YY.MM.<build>", where <build> is a monotonic
# integer (CURRENT_PROJECT_VERSION). The build number is the key Sparkle compares
# to decide "is this newer", so it MUST only ever increase — this script is the
# single place that touches it, +1 each release, to avoid hand-editing mistakes.
#
# It bumps both fields in project.yml, commits, and creates tag v<version>.
# It does NOT push by default (push is the irreversible release trigger) —
# pass --push to also push main + the tag.
#
# Usage:  scripts/bump-version.sh [--push]
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_YML="project.yml"
[ -f "$PROJECT_YML" ] || { echo "error: $PROJECT_YML not found (run from repo root)" >&2; exit 1; }

# Clean tree required so the release commit contains only the version bump.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree not clean — commit or stash first" >&2
  exit 1
fi

# `|| true`: don't let a no-match abort under `set -o pipefail` before the guard.
cur_build=$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | sed -E 's/[^0-9]*([0-9]+).*/\1/' || true)
[ -n "$cur_build" ] || { echo "error: could not read CURRENT_PROJECT_VERSION from $PROJECT_YML" >&2; exit 1; }

new_build=$((cur_build + 1))
version="$(date -u +%y.%m).${new_build}"
tag="v${version}"

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "error: tag ${tag} already exists" >&2
  exit 1
fi

# Update both fields (BSD/macOS sed).
sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:).*/\1 \"${version}\"/" "$PROJECT_YML"
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:).*/\1 \"${new_build}\"/" "$PROJECT_YML"

echo "Version → ${version}   (build ${cur_build} → ${new_build})"

git add "$PROJECT_YML"
git commit -m "chore(release): ${version}" >/dev/null
git tag "$tag"
echo "Committed + tagged ${tag}."

if [ "${1:-}" = "--push" ]; then
  git push origin HEAD
  git push origin "$tag"
  echo "Pushed — CI release pipeline triggered for ${tag}."
else
  echo "Not pushed. To release:  git push origin HEAD && git push origin ${tag}"
fi
