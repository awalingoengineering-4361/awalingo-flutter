# Notification click actions implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native execution.

**Goal:** Fix tracker #101 by opening notification destinations or complete item details.
**Architecture:** Keep the shared native router, report whether it handled a link,
and add a record-aware entry point shared by the bell and list. A detail screen
handles announcements, absent links and destinations unavailable natively.
**Tech Stack:** Flutter, existing Supabase notification service and fixture tests.
**Spec:** docs/superpowers/specs/2026-11-03-notification-click-actions.md

## Constraints and review focus

- Retain existing linked native routes and native push fallback behavior.
- Scope read writes by user and ID; prevent duplicate writes, delayed navigation
  after account/source changes, and read state falsely succeeding on failure.
- Check generic /notifications links, absent/unsupported links, already-read
  items, long message text, immediate repeats, rapid taps and retry.
- No live user data or backend mutations are needed for deterministic checks.

### Task 1: Notification item navigation and read lifecycle

- [ ] Reproduce list-to-list announcement taps and absent-link taps with failing
  widget tests; cover both bell and full list, repeat opening and persisted reads.
- [ ] Implement shared item-aware routing, themed detail display and guarded list
  read/open lifecycle; retain existing push routing contract behavior.
- [ ] Run targeted tests, complete scripts/verify-change in order, inspect launch
  evidence, then run deterministic Android navigation fixtures with screenshots.
- [ ] Obtain one fresh whole-change review, resolve important findings with tests,
  record actual results and keep the branch ready for the user's PR request.
