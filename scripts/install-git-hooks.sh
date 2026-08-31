#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'Run this command inside a Git repository.\n' >&2
  exit 69
}

hook="$repository_root/.githooks/pre-commit"
if [[ ! -f "$hook" ]]; then
  printf 'Tracked pre-commit hook is missing: %s\n' "$hook" >&2
  exit 66
fi

chmod +x "$hook"
git -C "$repository_root" config --local core.hooksPath .githooks
printf 'Configured Git to use %s/.githooks.\n' "$repository_root"
