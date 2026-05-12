# Harness Contract

Use this contract when turning project context into a plan.

## Source of Truth

- Treat `AGENTS.md` as a short map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, CI, source paths, and existing plans before inventing project assumptions.
- Prefer accessible repo knowledge over user memory.
- Separate confirmed facts from inference and assumptions.

## Plan as Artifact

- Make plans reusable by another agent.
- Include decision drivers, alternatives, why the chosen path was selected, and why rejected paths were rejected.
- Include a `Goal Contract` for long-running, multi-skill, worker-assisted, or continuation-prone work.
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

When a plan will hand off to `ralph-execute`, choose one worker mode:

- `main-only`: one main Codex execution path is safer than parallel workers.
- `tmux-visible`: execution should launch CLI workers in tmux/Ghostty when `ralph-execute` decides to use subagents.

Only choose `tmux-visible` when worker ownership can be separated into disjoint write scopes. The plan must name each worker's `worker_id`, responsibility, write scope, required prompt input, validation expectation, and dependency.
