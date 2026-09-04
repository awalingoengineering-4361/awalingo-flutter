#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture_bin="$project_root/test/workflows/fixtures/bin"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/awalingo-ci-quality.XXXXXX")"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test_verify_ci_runs_quality_checks_in_order_and_bootstraps_env() {
  local command_log="$test_root/verify-ci.log"
  local env_file="$test_root/.env"
  local output

  output="$(PATH="$fixture_bin:$PATH" \
    AWALINGO_TEST_COMMAND_LOG="$command_log" \
    AWALINGO_APK_PATH="$test_root/app-debug.apk" \
    AWALINGO_CI_ENV_FILE="$env_file" \
    AWALINGO_TEST_EXPECT_ENV_FILE="$env_file" \
    "$project_root/scripts/verify-ci")"

  [[ "$(wc -l <"$command_log" | tr -d ' ')" -eq 4 ]] ||
    fail "verify-ci did not run exactly four Flutter commands"
  [[ "$(sed -n '1p' "$command_log")" == "flutter pub get" ]] ||
    fail "dependency resolution was not the first CI phase"
  [[ "$(sed -n '2p' "$command_log")" == "flutter analyze --no-fatal-infos" ]] ||
    fail "static analysis was not the second CI phase"
  [[ "$(sed -n '3p' "$command_log")" == "flutter test" ]] ||
    fail "automated tests were not the third CI phase"
  [[ "$(sed -n '4p' "$command_log")" == "flutter build apk --debug" ]] ||
    fail "the Android debug build was not the final CI phase"

  [[ "$output" == *"PASS: branch workflow contracts"* ]] ||
    fail "verify-ci did not run the branch workflow contracts"
  [[ "$output" == *"PASS: emulator verification contracts"* ]] ||
    fail "verify-ci did not run the emulator workflow contracts"

  [[ ! -e "$env_file" ]] ||
    fail "verify-ci did not remove its temporary environment file"
}

test_verify_ci_runs_quality_checks_in_order_and_bootstraps_env

printf 'PASS: CI quality workflow contracts\n'
