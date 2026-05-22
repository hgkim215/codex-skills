# Execution Contract

Use this contract when turning an approved plan or concrete request into changes.

## Source of Truth

- Treat `AGENTS.md` as a map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, CI, source paths, and existing plans before guessing.
- Inspect `git status --short` before editing.
- Preserve user changes and generated work that you did not create.

## Graph Context

Follow the suite-level `../../references/graph-context-policy.md`.

- Use CodeGraph before editing when symbol ownership, callers/callees, route/component discovery, shared API impact, or architecture boundaries matter.
- Skip CodeGraph when the change is tiny, already localized, docs/config-only, or faster to handle with direct reads and `rg`.
- Use ActiveGraph only when available and the work is long-running, worker-heavy, experiment-prone, or completion-audit heavy. Do not duplicate `.ralph` ledger text into ActiveGraph.
- Use Obsidian only for narrow prior decisions or user preferences that materially affect implementation. Skip broad or slow memory lookup.

## Plan Consumption

- If a `ralplan` output exists, consume `Decision`, `Plan`, `Validation`, `Risks`, `Assumptions`, and `Handoff`.
- If a `Goal Contract` exists, consume it as macro-objective context and check that the execution request is still aligned.
- If a `Goal Scorecard` exists, consume it as the verification target for fast checks, full checks, and completion evidence.
- Execute only when `Handoff` is `ralph-execute` or the user explicitly asks to implement the plan.
- Keep edits inside the selected plan and accepted assumptions.
- If new evidence invalidates the plan, stop and report the mismatch.
- If goal tracking is requested but the objective, scope, done criteria, scorecard, or checks are unclear, stop before editing and ask the user for the missing goal information.

## Goal Checkpoint

For the full lifecycle policy and completion audit template, use the suite-level `../references/goal-lifecycle-contract.md` from the skill root.

Before editing, classify goal state when available:

- `aligned`: current goal and requested execution match.
- `unknown`: goal tools or goal state are unavailable.
- `missing`: goal tracking was requested, but no macro goal exists.
- `mismatch`: current goal points to different work.
- `unclear`: goal tracking was requested, but objective, scope, done criteria, scorecard, or checks are not auditable.
- `paused`: goal exists but should not auto-continue.
- `budget_limited`: budget has stopped continuation.

Stop on `missing`, `mismatch`, `unclear`, `paused`, or `budget_limited` unless the user explicitly redirects with the missing information or a different non-goal execution request. Execution should not create a phase-level goal. Only mark a goal complete after the full macro objective, scorecard, validation, and review gates are satisfied.

## Progress Ledger

When goal-aware execution is multi-step, worker-assisted, likely to continue across turns, or experiment-prone, maintain a ledger under:

```text
.ralph/goals/<goal-slug>/
  PLAN.md
  SCORECARD.md
  EXPERIMENTS.md
  NOTES.md
```

Use the ledger as durable working memory, not as permission to expand scope.

- `PLAN.md`: selected plan, constraints, non-goals, and handoff boundaries.
- `SCORECARD.md`: `Metric`, `Baseline`, `Target`, `Fast Check`, `Full Check`, `Regression Gates`, and `Stop Condition`.
- `EXPERIMENTS.md`: append each meaningful attempt with hypothesis, change, check, result, and decision.
- `NOTES.md`: short live notes, blockers, user decisions, and open questions.

Do not create a ledger for trivial one-shot changes unless the plan requires it. If the ledger is required but the scorecard is not clear, stop and request clarification before editing.

## Subagent Policy

Follow the suite-level `../../references/orchestration-policy.md`.

- Use worker-first assessment for every non-trivial execution. Before editing locally, actively try to split the work across implementation, tests, docs, migration surfaces, verification, or review.
- Prefer subagents when work can split into independent write scopes, independent diagnostic scopes, or parallel verification responsibilities and the expected value beats coordination cost.
- Use main-only when the task is tiny and clearly one-shot, tightly coupled, write scopes would overlap unsafely, worker output is an immediate blocker for the next local step, the work is mostly product judgment, worker tooling is unavailable, or the user explicitly asks not to use workers.
- When selecting main-only for non-trivial work, record `No-Worker Justification` in the final response.
- When subagents are used, run them as tmux-visible CLI workers through `scripts/ralph_tmux_workers.sh`, opening Ghostty with one `workers` tmux window and one tiled pane per subagent unless the user explicitly disables terminal opening.
- Pass `--goal-file` when a goal contract should be visible in the run directory and worker prompts.
- Give each worker explicit ownership of files, modules, or responsibility.
- Tell workers they are not alone in the codebase and must not revert user or other-agent changes.
- Require each worker to return changed paths, verification performed, blockers, and residual risk.
- Main Codex must review, integrate, and run final verification before reporting completion.
- Worker run summaries should preserve status, started/finished timestamps, duration seconds, result size, and last-message state for completion audit evidence.
- Worker-assisted runs must produce a user-facing `worker_handoff_summary.md` that shows each worker's scope, status, duration, result log, final handoff, blockers, and residual risk as reported by the worker.
- Unless the user explicitly disables workspace artifacts, persist the handoff bundle under `.ralph/worker-runs/<run-name>-<timestamp>/` and update `.ralph/worker-runs/INDEX.md` so the user can audit past subagent work across turns.

## Tmux-Visible Worker Policy

Use `ralph_tmux_workers.sh` when `ralplan` says `Worker Mode: tmux-visible`, when the user asks for worker/subagent splitting, or when main Codex identifies separable scopes that pass the orchestration decision gate during worker-first assessment.

The expected visibility surface is:

- one Ghostty window attached to the worker tmux session
- one `workers` tmux window containing exactly one pane per subagent
- tiled pane layout with pane titles matching worker roles
- one optional `monitor` tmux window for aggregate status
- Terminal fallback only when Ghostty cannot be opened

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

Do not use tmux-visible workers when write scopes overlap unsafely, worker output must be consumed immediately by the next step, the task is too coupled for safe parallel work, tooling is unavailable, or the user explicitly disables workers. If worker use is skipped for non-trivial work, state the skipped worker split and why it was rejected.

After a tmux-visible run completes, inspect `worker_handoff_summary.md` first. Use `results/<worker>.last_message.md` for deeper worker-specific final handoffs and `results/<worker>.out` only for logs or diagnosis. Include the terminal app, tmux session, worker window, worker pane count, transient `WORKER_HANDOFF_SUMMARY`, and persistent `PERSISTENT_HANDOFF_SUMMARY` paths in the final worker-run report when they exist.

## Verification Loop

- Prefer validation named by the plan.
- For goal-aware work, run the `Fast Check` before broader validation whenever it is available and relevant.
- Otherwise use documented repo commands from `AGENTS.md`, `README`, `Makefile`, `scripts`, manifests, or CI.
- Run focused tests or checks for touched behavior when full verification is expensive.
- If checks fail, inspect the failure, attempt a scoped fix, and rerun the same check.
- Update `SCORECARD.md` or report the scorecard result after each meaningful fast/full check when a progress ledger is active.
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
