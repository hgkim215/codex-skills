# Harness Engineering Guide

Use this shared guide when a Ralph skill needs project-harness structure without depending on a private local document.

## Layer Model

- Global skill: reusable behavior for one phase, such as interview, analysis, planning, execution, QA, visual QA, review, or worker watching.
- Project harness: repo-local facts and rules, such as `AGENTS.md`, `README`, `docs/`, `Makefile`, `scripts/`, tests, manifests, CI config, and existing plans.
- Runtime surface: Codex App for orchestration, Codex CLI for worker execution, and tmux/Ghostty for progress visibility when worker execution is selected.

## Discovery Order

Before asking the user for facts, inspect accessible project evidence:

- `AGENTS.md`
- `README*`
- `docs/`
- `Makefile`
- `scripts/`
- manifests such as `package.json`, `pyproject.toml`, `Cargo.toml`, `pubspec.yaml`
- tests, CI config, and existing execution plans
- source files named by the request

Ask the user only for judgment calls: priority, scope, non-goals, approval boundaries, production/external action, credentials, destructive changes, and subjective acceptance.

## Output Discipline

Every phase should separate:

- confirmed facts
- inference
- assumptions
- unknowns
- decisions needed from the user
- validation evidence
- next handoff

## Phase Boundaries

- `deep-interview`: clarify macro goal, scope, constraints, non-goals, done criteria, and approval boundaries.
- `analyze`: inspect without editing; produce evidence-backed findings and uncertainty.
- `ralplan`: turn clarified requirements and evidence into an execution-ready plan.
- `ralph-execute`: implement an approved plan or concrete request and verify the result.
- `ralph-qa`: reproduce, fix, and verify a failure-centered loop.
- `visual-ralph-qa`: verify UI or visual behavior with browser, screenshot, viewport, console, or DOM evidence.
- `code-review`: review completed diffs or QA evidence; findings come first.
- `tmux-worker-watch`: summarize existing worker panes and run status read-only.

## Worker Visibility

Use worker-first assessment for non-trivial execution, QA, and visual QA. Before choosing main-only, actively look for useful worker splits across implementation, tests, docs, migration surfaces, reproduction hypotheses, verification, or review.

Prefer tmux-visible workers when at least one of these is true:

- two or more files, modules, screens, or responsibilities can be owned independently
- implementation and tests/docs/verification can proceed in parallel
- independent hypotheses or regression surfaces can be investigated without blocking the main path
- the task is multi-step, continuation-prone, or likely to exceed a short focused edit

Use main-only only when worker scopes would overlap unsafely, worker output is an immediate blocker for the next local step, tools are unavailable, the task is tiny and clearly one-shot, or the user asks not to use workers. When main-only is selected for non-trivial work, state the no-worker reason explicitly.

When worker execution is selected:

- assign explicit file, module, or responsibility ownership
- tell workers they are not alone in the codebase
- tell workers not to revert user or other-worker changes
- require changed paths, verification, blockers, and residual risk
- integrate and verify in main Codex before completion

## Goal Layer

Codex `goal` is a thread-level macro objective. It does not replace the phase workflow.

Use the shared `goal-lifecycle-contract.md` for creation, status, and completion rules.

Do not create per-phase goals. Create a goal only when the user explicitly requests goal tracking and the macro objective is clear enough to audit later.
