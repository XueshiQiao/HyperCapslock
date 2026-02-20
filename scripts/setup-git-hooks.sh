#!/bin/sh
set -eu

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  echo "Error: run this script inside a git repository."
  exit 1
fi

cd "$REPO_ROOT"

if [ ! -f ".githooks/pre-commit" ]; then
  echo "Error: .githooks/pre-commit not found."
  exit 1
fi

chmod +x .githooks/pre-commit
git config --local core.hooksPath .githooks

echo "Configured local git hooks path:"
git config --local --get core.hooksPath
echo "Pre-commit hook is now managed from .githooks/pre-commit"
