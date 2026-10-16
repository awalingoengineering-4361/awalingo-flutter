# Offline Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Fix APK issue 34 by distinguishing connection failures from empty data and providing safe retry across the affected screens.

**Architecture:** A shared classifier and theme-aware retry widget present failures consistently. Each screen owns its loading/error state and retries the correct read or bootstrap operation. Preserve valid existing data and entered text.

**Tech Stack:** Flutter, Dart, Supabase, package:http, flutter_test, integration_test.

**Spec:** [Issue 34 acceptance criteria](2026-10-16-offline-handling-spec.md).

## Global Constraints

- Branch `codex/offline-handling`; preserve the original checkout's changes.
- Exact offline title: “You are offline”; action: “Retry”. Never show exception strings.
- Distinguish connection failure, other failure, and successful empty data.
- Retry reads only; preserve existing mutation and reward behavior.
- Required verification order: analysis, automated tests, Android build/install/launch, screenshot inspection.

## Review Focus

- Server errors falsely reported as offline: classifier and screen tests in task 1.
- Failed bootstrap enabling controls with fallback IDs: offline-first tests in task 2.
- Pagination retries duplicating or replacing loaded terms: dictionary tests in task 2.
- Late responses overwriting new results or updating disposed screens: delayed-response tests in task 2.
- Repeated recovery duplicating timers or replaying mutations: method assertions and Android replay in tasks 2–3.

### Task 1: Shared load-failure presentation

**Files:** Create `lib/services/load_failure.dart`, `lib/widgets/load_failure_view.dart`, `test/services/load_failure_test.dart`, and `test/widgets/load_failure_view_test.dart`.

**Interfaces:** Consumes thrown `Object` values. Produces `LoadFailure.fromError(Object error)` with `isOffline`, `title`, and `message`, plus `LoadFailureView({required LoadFailure failure, required VoidCallback onRetry, bool compact = false})`.

- [x] Write failing classifier tests: HTTP connection failure/timeout → offline; PostgREST permission error, server rejection, and malformed data → generic failure; no exception details exposed.
- [x] Write widget tests for exact title/action, Retry callback, light/dark readability, and compact layout.
- [x] Run `flutter test test/services/load_failure_test.dart test/widgets/load_failure_view_test.dart` and confirm the missing behavior fails.
- [x] Implement type-based classification and the retry widget using existing theme tokens/fonts, compatible with existing platform targets.
- [x] Rerun those tests; all must pass.

### Task 2: Distinguish failed loads on the affected screens

**Files:** Modify `lib/screens/main/awaquiz_screen.dart`, `curator_test_screen.dart`, `dictionary_screen.dart`, `vote_screen.dart`, `translate_screen.dart`, `request_screen.dart`, and `my_word_requests_screen.dart`. Create `test/support/offline_fixture.dart` and `test/screens/offline_recovery_test.dart`.

**Interfaces:** Consumes `LoadFailure`/`LoadFailureView` from task 1. Produces explicit screen failure states and screen-owned Retry callbacks; controlled HTTP fixtures exercise the real screens and services.

- [x] Write offline-first tests for every named screen: show offline feedback, hide invalid controls and false empty states, reconnect, then Retry to successful data.
- [x] Add genuine-empty and server-error tests to keep all three outcomes distinct.
- [x] Add disconnect-during-language-change, search/pagination, form initialization, delayed-response, and disposal cases. Assert loaded terms/text survive where applicable and stale responses do not win.
- [x] Add repeated-retry and curator initialization cases; assert no duplicate entries/timers and no mutation requests from read retries.
- [x] Run `flutter test test/screens/offline_recovery_test.dart` and reproduce the misleading current behavior before implementation.
- [x] Preserve thrown failures instead of converting them to raw text or silent empty results. Clear errors after successful reload and retry bootstrap when initialization failed.
- [x] Make dictionary alphabet errors propagate instead of returning partial success. Keep page offsets unchanged on failed pagination and offer retry for that page.
- [x] Gate bootstrap-dependent forms/toggles and preserve input after network failures. Use friendly network feedback for explicit submit attempts without changing submission transactions or automatically resubmitting.
- [x] Run targeted screen and shared tests; all must pass.

### Task 3: Verify repeated offline/recovery journeys on Android

**Files:** Create `integration_test/offline_recovery_test.dart` and `test_driver/offline_recovery.dart`; document the command in `README.md`.

**Interfaces:** Consumes task 2's deterministic fixtures and the repository's existing integration-test tooling. Produces Android journey results and representative offline/recovery screenshots.

- [x] Run the full `flutter test` suite and `scripts/verify-change`; inspect emulator evidence.
- [x] Reuse the screen cases through `flutter drive`, including initial offline entry, reconnect/retry, and a second offline/recovery run.
- [x] Capture AwaQuiz offline, failed lounge bootstrap, and successful retry. Inspect copy wrapping, Retry visibility, and hidden invalid controls.
- [x] Obtain final code review, fix actionable findings, and rerun affected checks.
- [x] Record fixture-backed versus real-network verification. Prepare a focused PR when publication is requested.

## Verification evidence

- Full automated suite: 71 passing tests.
- Required `scripts/verify-change`: passed (analysis, tests, Android build,
  ARM64 APK install, launch, and inspected onboarding screenshot).
- Android integration: all 32 screen tests passed, plus framework teardown.
- Controlled HTTP failures exercise the actual screens/services; fixtures seed
  a local-only Supabase session and cover populated voting recovery.
- These checks do not contact production or toggle physical device connectivity.
- Fresh read-only review found no confirmed runtime Critical/Important bugs.
  Its authentication/replay coverage findings were reproduced with a failing
  test, corrected, and verified with the full suite.
- A dedicated screenshot replay corrects the fixture's Material ancestor so
  AwaQuiz's standalone capture matches the Material supplied by AppShell.

## Review scope decisions

- Keep unchanged Vote/Jury detail and Suggest screens outside the approved
  lounge-loading scope. Cost if wrong: separate downstream offline fixes.
- Preserve existing fallback behavior for successful empty language lookups.
  Cost if wrong: separate account-configuration validation.
- Preserve submission/reward transactions and retry reads only.
  Cost if wrong: separate handling of ambiguous submission outcomes.
- Keep Android execution and screenshot inspection as the executor's completion
  gate; review was read-only. Cost if wrong: insufficient device evidence.
