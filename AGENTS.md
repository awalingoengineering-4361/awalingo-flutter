# Awalingo Flutter Agent Instructions

These instructions apply to the entire repository.

## Branch-first development

Every code change must begin on a task branch. Before modifying files, run:

```bash
git status --short --branch
git branch --show-current
```

Read-only investigation may happen on any branch. Do not edit, generate, format,
or commit code directly on `main` or `master`.

For one independently reviewable change, start from a clean working tree:

```bash
scripts/start-change <short-task-name>
```

This creates and checks out `codex/<short-task-name>`. If pre-existing changes
are discovered on a protected branch, preserve them. Never reset, discard, or
silently mix them with a new task. Branch in place only when the changes clearly
belong to the active task and the user has authorized it; otherwise ask before
proceeding.

## Stacked changes

Use a stack when the work can be split into two or more dependent, independently
reviewable pull requests. Prefer GitHub's official `gh stack` extension:

```bash
gh stack init codex/<bottom-layer>
gh stack add codex/<next-layer>
gh stack view --json
```

Keep each layer focused and passing its relevant checks. For non-interactive
agent sessions, use `gh stack submit --auto`; never invoke an interactive stack
command. Pushing, submitting, or merging changes is an external mutation and
still requires user authorization.

If `gh stack` is unavailable or the repository does not have GitHub stacked pull
requests enabled, use ordinary branches: branch each layer from the layer below
it and target each pull request at its immediate parent branch.

## Commit guardrail

Install this clone's tracked hooks once:

```bash
scripts/install-git-hooks.sh
```

The pre-commit hook blocks commits on `main` and `master`. Do not bypass it with
`--no-verify`; create the correct branch instead.

## Verification workflow

After every runtime code change, run the complete local verification workflow:

```bash
scripts/verify-change
```

The command runs static analysis and automated tests before building, installing,
and launching the app on an Android emulator. It must remain in that order. A
documentation-only change is exempt from the emulator step.

After the command succeeds, inspect
`build/verification/android-emulator/screenshot.png` and, when relevant,
`window.xml` to confirm the changed interface or journey is visibly correct. The
generic launch check does not replace feature-specific integration tests; add
those for important user journeys as deterministic fixtures become available.

## Engineering standard

Preserve unrelated user changes. Keep commits and stack layers cohesive, add
tests for behavior changes, and run the smallest relevant checks before broader
verification. Do not claim completion without fresh verification evidence.
