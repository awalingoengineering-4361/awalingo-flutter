#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/awalingo-branch-workflow.XXXXXX")"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

new_repository() {
  local repository="$1"

  git init -q -b main "$repository"
  git -C "$repository" config user.name "Workflow Test"
  git -C "$repository" config user.email "workflow-test@example.com"
  printf 'fixture\n' >"$repository/README.md"
  git -C "$repository" add README.md
  git -C "$repository" commit -q -m "test: initialize fixture"
}

test_start_change_creates_prefixed_branch() {
  local repository="$test_root/start-clean"
  new_repository "$repository"

  (
    cd "$repository"
    "$project_root/scripts/start-change" awaquiz-stages >/dev/null
  )

  [[ "$(git -C "$repository" branch --show-current)" == "codex/awaquiz-stages" ]] ||
    fail "start-change did not create the expected codex-prefixed branch"
}

test_start_change_rejects_dirty_tree() {
  local repository="$test_root/start-dirty"
  new_repository "$repository"
  printf 'uncommitted\n' >>"$repository/README.md"

  if (
    cd "$repository"
    "$project_root/scripts/start-change" unsafe-start >/dev/null 2>&1
  ); then
    fail "start-change accepted a dirty working tree"
  fi

  [[ "$(git -C "$repository" branch --show-current)" == "main" ]] ||
    fail "start-change changed branches after rejecting a dirty tree"
}

assert_hook_blocks_protected_branch_and_allows_feature_branch() {
  local protected_branch="$1"
  local repository="$test_root/pre-commit-$protected_branch"
  new_repository "$repository"
  if [[ "$protected_branch" != "main" ]]; then
    git -C "$repository" branch -m "$protected_branch"
  fi
  mkdir -p "$repository/.githooks"
  cp "$project_root/.githooks/pre-commit" "$repository/.githooks/pre-commit"
  chmod +x "$repository/.githooks/pre-commit"

  (
    cd "$repository"
    "$project_root/scripts/install-git-hooks.sh" >/dev/null
  )

  [[ "$(git -C "$repository" config --local --get core.hooksPath)" == ".githooks" ]] ||
    fail "hook installer did not configure the tracked hooks directory"

  printf 'blocked\n' >>"$repository/README.md"
  git -C "$repository" add README.md
  if git -C "$repository" commit -q -m "test: protected commit" >/dev/null 2>&1; then
    fail "pre-commit hook allowed a commit on $protected_branch"
  fi

  git -C "$repository" switch -q -c codex/allowed
  git -C "$repository" commit -q -m "test: feature commit" ||
    fail "pre-commit hook blocked a feature-branch commit"
}

test_hook_blocks_protected_branches_and_allows_feature_branch() {
  assert_hook_blocks_protected_branch_and_allows_feature_branch main
  assert_hook_blocks_protected_branch_and_allows_feature_branch master
}

test_start_change_creates_prefixed_branch
test_start_change_rejects_dirty_tree
test_hook_blocks_protected_branches_and_allows_feature_branch

printf 'PASS: branch workflow contracts\n'
