# Harness Contract

Use this contract when turning project context into a plan.

## Source of Truth

- Treat `AGENTS.md` as a short map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, CI, source paths, and existing plans before inventing project assumptions.
- Prefer accessible repo knowledge over user memory.
- Separate confirmed facts from inference and assumptions.

## Graph Context

Follow the suite-level `../../references/graph-context-policy.md`.

- Use CodeGraph for structural planning, dependency direction, impacted callers, route/component ownership, and shared API blast radius.
- Skip CodeGraph for small one-shot edits, docs/config-only changes, and plans where the target file and validation are already obvious.
- Use ActiveGraph only when a plan will need durable machine-readable state across workers, attempts, evidence, and completion review.
- Use Obsidian only for narrow prior decisions or user/project preferences that could change the plan. Broad or slow lookup should be skipped.

## Plan as Artifact

- Make plans reusable by another agent.
- Include decision drivers, alternatives, why the chosen path was selected, and why rejected paths were rejected.
- Include a `Goal Contract` for long-running, multi-skill, worker-assisted, or continuation-prone work.
- Include a `Goal Scorecard` whenever a `Goal Contract` is present.
- Include a progress ledger recommendation when execution is likely to involve repeated attempts, workers, or continuation across turns.
- Include validation commands or validation surfaces when discoverable.
- Include a worker visibility plan for execution: `main-only` or `tmux-visible`.
- Include rollback, recovery, or escalation expectations for risky work.

## Goal Contract

Use goal as a thread-level macro objective. Do not use it as a per-skill checklist. For the full lifecycle policy and completion audit template, use the suite-level `../references/goal-lifecycle-contract.md` from the skill root.

Create a goal only when the user explicitly asks for goal tracking and the macro objective is clear enough. Prefer creating it once during `deep-interview` closure or `ralplan` planning. Later execution, QA, review, and watcher skills should read the existing goal rather than creating phase-specific goals.

Every goal-aware plan should state:

- `Goal Usage`: `none`, `observe`, `suggest`, or `active`
- `Objective Source`: current goal, proposed `/goal` text, or repo document path
- `Current Status`: active, paused, budget-limited, complete, missing, or unknown
- `Pause Boundaries`: where automatic continuation should stop for user judgment or approval
- `Completion Gate`: which later skill or evidence can decide whole-goal completion
- `Completion Audit Plan`: the evidence needed before `update_goal complete`

Every goal-aware plan should also include a `Goal Scorecard`:

- `Metric`: one or more measurable or observable success signals
- `Baseline`: current state, failing state, or unknown with a discovery step
- `Target`: exact target or pass/fail condition
- `Fast Check`: the shortest repeatable check to run after each attempt
- `Full Check`: final validation before completion
- `Regression Gates`: behavior that must not regress
- `Stop Condition`: when automation must pause for user input

If goal tracking is requested but objective, scope, done criteria, scorecard, or checks cannot be stated from user input or verified repo evidence, stop before producing an execution plan. Ask the user for the missing fields instead of creating an ambiguous goal or continuing as ordinary execution.

Do not rely on `/goal --tokens`; slash input treats the remaining text as objective in current known behavior. Long objectives should point to a repo document.

## Guardrails

- Do not implement during planning.
- Do not edit files, run formatters that rewrite files, run migrations, run codegen, commit, push, delete, reset, or apply patches.
- Do not ask the user for facts that can be discovered from repo/docs/config/scripts.
- Ask the user only for decisions: scope, non-goals, tradeoffs, approvals, destructive changes, external delivery, credentials, or production behavior.

## Rule Candidates

When a planning issue is likely to repeat, record it as a future harness rule candidate:

- missing or stale docs
- unclear ownership boundaries
- missing validation command
- architecture drift risk
- missing test coverage
- failure messages without recovery guidance
- repeated review comments that could become lint, CI, docs, or skill rules

## Worker Visibility Planning

Follow the suite-level `../../references/orchestration-policy.md`.

When a plan will hand off to `ralph-execute`, choose one worker mode:

- `tmux-visible`: preferred for non-trivial work when useful splits pass the orchestration decision gate; execution should launch CLI workers in tmux/Ghostty unless `ralph-execute` finds a concrete safety, coupling, or overhead reason not to.
- `main-only`: use for tiny one-shot work, tightly coupled changes, unsafe overlapping write scopes, immediate blocker dependencies, product-judgment-heavy work, unavailable worker tooling, or explicit user instruction not to use workers.

Run a worker-first decomposition before selecting `main-only`. Look for splits across implementation, tests, docs, data/migration boundaries, reproduction hypotheses, visual viewports, regression checks, or review. Choose workers only when coordination cost is lower than the expected value. If a plan selects `main-only` for non-trivial work, include `No-Worker Justification` with the concrete split considered and rejected.

Choose `tmux-visible` when worker ownership can be separated into disjoint write scopes or disjoint diagnostic/verification responsibilities. The plan must name each worker's `worker_id`, responsibility, write scope or diagnostic scope, required prompt input, validation expectation, and dependency.

For tmux-visible plans, include the visibility expectation: one Ghostty window attached to the tmux session, a `workers` window with one tiled pane per subagent, and an optional `monitor` window for aggregate status.
