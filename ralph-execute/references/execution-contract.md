# Execution Contract

Use this contract when turning an approved plan or concrete request into changes.

## Source of Truth

- Treat `AGENTS.md` as a map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, CI, source paths, and existing plans before guessing.
- Inspect `git status --short` before editing.
- Preserve user changes and generated work that you did not create.

## Plan Consumption

- If a `ralplan` output exists, consume `Decision`, `Plan`, `Validation`, `Risks`, `Assumptions`, and `Handoff`.
- If a `Goal Contract` exists, consume it as macro-objective context and check that the execution request is still aligned.
- Execute only when `Handoff` is `ralph-execute` or the user explicitly asks to implement the plan.
- Keep edits inside the selected plan and accepted assumptions.
- If new evidence invalidates the plan, stop and report the mismatch.

## Goal Checkpoint

For the full lifecycle policy and completion audit template, use the suite-level `../references/goal-lifecycle-contract.md` from the skill root.

Before editing, classify goal state when available:

- `aligned`: current goal and requested execution match.
- `unknown`: goal tools or goal state are unavailable.
- `missing`: goal tracking was requested, but no macro goal exists.
- `mismatch`: current goal points to different work.
- `paused`: goal exists but should not auto-continue.
- `budget_limited`: budget has stopped continuation.

Stop on `missing`, `mismatch`, `paused`, or `budget_limited` unless the user explicitly redirects. Execution should not create a phase-level goal. Only mark a goal complete after the full macro objective, validation, and review gates are satisfied.

## Subagent Policy

- Default to main Codex execution for small or tightly coupled work.
- Use subagents only when work can split into independent write scopes and parallelism improves speed, coverage, or quality.
- When subagents are used, run them as tmux-visible CLI workers through `scripts/ralph_tmux_workers.sh`.
- Pass `--goal-file` when a goal contract should be visible in the run directory and worker prompts.
- Give each worker explicit ownership of files, modules, or responsibility.
- Tell workers they are not alone in the codebase and must not revert user or other-agent changes.
- Require each worker to return changed paths, verification performed, blockers, and residual risk.
- Main Codex must review, integrate, and run final verification before reporting completion.
- Worker run summaries should preserve status, started/finished timestamps, duration seconds, result size, and last-message state for completion audit evidence.

## Tmux-Visible Worker Policy

Use `ralph_tmux_workers.sh` when `ralplan` says `Worker Mode: tmux-visible` or when main Codex decides worker execution is useful.

Create one prompt file per worker and a `workers.tsv` file:

```text
worker_id<TAB>title<TAB>prompt_file<TAB>write_scope
```

Each prompt must include:

- goal context when provided, marked as untrusted orientation rather than permission or completion authority
- task responsibility
- exact write scope
- instruction that other workers may be active
- instruction not to revert user or other-worker changes
- expected verification
- required final response: changed paths, verification, blockers, residual risk

Do not use tmux-visible workers when write scopes overlap, worker output must be consumed immediately by the next step, or the task is too coupled for safe parallel work.

## Verification Loop

- Prefer validation named by the plan.
- Otherwise use documented repo commands from `AGENTS.md`, `README`, `Makefile`, `scripts`, manifests, or CI.
- Run focused tests or checks for touched behavior when full verification is expensive.
- If checks fail, inspect the failure, attempt a scoped fix, and rerun the same check.
- If verification cannot run, report the blocker and residual risk.

## Stop And Approval Boundaries

Stop and ask before:

- destructive git operations
- deleting user data
- external deployment or publication
- credentialed production actions
- payment or irreversible account changes
- broad migrations or generated changes not already approved

## Rule Candidates

When execution reveals a repeated issue, record it as a future harness rule candidate:

- missing or stale validation command
- unclear ownership boundary
- missing test coverage
- hidden generated-file workflow
- recurring manual review comment
- brittle script or failure message without recovery guidance
