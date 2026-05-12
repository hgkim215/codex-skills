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

Use tmux-visible workers only when work can be split into disjoint ownership boundaries and the main Codex is not immediately blocked on the worker result.

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
