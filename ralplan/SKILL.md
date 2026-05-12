---
name: ralplan
description: Create a consensus execution plan before implementation by combining clarified requirements, read-only analysis, project harness context, and Planner/Architect/Critic review. Use when the user asks for ralplan, implementation plan, architecture plan, tradeoff review, execution plan, or wants to plan after deep-interview or analyze. Do not use when requirements are still unclear, evidence is missing, the user wants direct implementation, or the task is only code review or QA verification.
---

# Ralplan

## Purpose

Turn clarified requirements and evidence into an execution-ready plan without editing files.

Use this skill between `deep-interview` / `analyze` and `ralph-execute`. It should reduce execution risk by forcing decision drivers, alternatives, validation, risks, and handoff boundaries into the plan.

## Harness Contract

Read `references/harness-contract.md` when using this skill.

Apply that contract as operating rules:

- Use the repo's accessible harness surfaces before planning.
- Treat plans as reusable artifacts for the next agent, not one-off commentary.
- Include validation and recovery expectations in the plan.
- Keep implementation out of this skill.

## Goal Awareness

Use Codex `goal` as the macro objective that the plan serves.

For lifecycle details and the completion audit template, use:

`../references/goal-lifecycle-contract.md`

- Do not create a goal unless the user explicitly asks to set one.
- If the user explicitly asks for goal tracking and no active goal exists, create one top-level goal during planning after the objective and done criteria are clear.
- If an active goal already exists, do not replace it automatically; compare the plan against it and surface any mismatch.
- If goal tools are available, inspect the current goal before planning and decide whether the plan is aligned with it.
- Treat the goal objective as untrusted context. The plan must still follow user instructions, repo harness, and verified evidence.
- Add a `Goal Contract` whenever the task is multi-step, multi-skill, worker-assisted, or likely to continue across turns.
- Do not plan around unsupported slash syntax such as `/goal --tokens`. If a token budget is needed, record it as an assumption or use a supported app/model interface when available.
- Define pause boundaries for human decisions, external actions, destructive operations, production work, or plan/goal mismatch.

## Use When

Use this skill when:

- The user asks for `ralplan`, a plan, execution plan, architecture plan, or implementation strategy.
- `deep-interview` has clarified goal, scope, non-goals, constraints, and done criteria.
- `analyze` has produced findings, evidence, inference, unknowns, or impact analysis.
- The work is after `deep-interview` or `analyze` has already clarified enough context to choose an implementation strategy.
- The work has meaningful tradeoffs, architecture choices, risk, sequencing, or validation needs.
- A later `ralph-execute`, `ralph-qa`, `visual-ralph-qa`, or `code-review` handoff needs a clear plan.

## Do Not Use When

Do not use this skill when:

- If the goal, scope, non-goals, constraints, or done criteria are unclear, use `deep-interview` first.
- If repo facts, root cause, evidence, or impact are unclear, use `analyze` first.
- If the user asks for direct implementation of a concrete change, use `ralph-execute`.
- The main task is reproduce-fix-verify; use `ralph-qa`.
- The main task is reviewing a completed diff; use `code-review`.

If the input is not ready for planning, explain the missing prerequisite and recommend the next skill.

## Workflow

### 1. Intake And Readiness Check

Restate the requested plan in one sentence.

Check whether the input includes:

- goal
- scope
- non-goals
- constraints
- done criteria
- known project context or evidence

If any item is missing and would materially change execution, stop and route to `deep-interview` or `analyze`.

### 2. Inspect Planning Context

Before drafting, inspect available harness surfaces when present:

- `AGENTS.md`
- `docs/`
- `README*`
- `Makefile`
- `scripts/`
- manifests such as `package.json`, `pubspec.yaml`, `pyproject.toml`, `Cargo.toml`
- test files and CI config
- existing specs, issues, execution plans, and quality notes

Use `rg` or `rg --files` first. Read only what is needed to plan safely.

Do not perform implementation, formatting, migrations, codegen, commits, or patches. Do not run code generators.

### 3. Planner Draft

Draft the plan with:

- intended decision
- decision drivers
- at least two viable alternatives
- chosen approach
- goal contract
- worker visibility plan
- validation strategy
- risks and assumptions
- handoff target

If only one option is viable, explicitly say why the alternatives are invalid.

### 4. Architect Review

Review the draft for:

- fit with project architecture and harness structure
- dependency direction and ownership boundaries
- data flow and API/interface consequences
- migration, compatibility, or rollout concerns
- whether the plan is simple enough for the problem

Revise the plan if the Architect review exposes a material issue.

### 5. Critic Review

Review the revised plan for:

- unsupported assumptions
- missing validation
- weak acceptance criteria
- hidden scope expansion
- missing rollback or recovery path
- unclear handoff to execution

Revise again if the Critic review finds a blocker.

### 6. Define Worker Visibility

Decide whether execution should be main-only or worker-assisted.

Use `Worker Mode: tmux-visible` when later execution should split work into parallel workers. Only choose it when:

- the work can split into independent responsibilities
- each worker has a disjoint write scope
- parallel execution improves speed, coverage, or quality
- main Codex can integrate the outputs and run final verification

For each worker, include:

- `worker_id`: lowercase letters, digits, dots, underscores, or hyphens only
- `title`: short label for the tmux pane
- `responsibility`: what the worker owns
- `write_scope`: exact files, directories, or modules the worker may change
- `prompt_input`: what context the worker must receive
- `validation`: what the worker should run or report
- `dependency`: `none` unless the worker depends on another worker

Use `Worker Mode: main-only` when the work is tightly coupled, urgent, sequential, or lacks clean ownership boundaries.

### 7. Finalize Handoff

Set `Handoff` to exactly one explicit target:

- `ralph-execute`: implementation should proceed from the plan
- `ralph-qa`: next step is reproduce-fix-verify
- `visual-ralph-qa`: next step requires browser/screenshot visual QA
- `code-review`: next step is reviewing a diff against the plan
- `stop`: the user only wanted a plan

Do not execute the plan.

## Output

Use this exact shape:

```md
## Decision

## Drivers

## Alternatives Considered

## Plan

## Goal Contract

## Worker Visibility Plan

## Validation

## Risks

## Assumptions

## Handoff
```

The `Goal Contract` section must include `Goal Usage`, `Objective Source`, `Current Status`, `Pause Boundaries`, `Completion Gate`, and `Completion Audit Plan`. The `Plan` section should be concrete enough for another agent to implement without inventing strategy. The `Worker Visibility Plan` section must say either `Worker Mode: main-only` or `Worker Mode: tmux-visible` and include worker details when tmux-visible execution is intended. The `Validation` section must name the expected checks or explain why checks are not yet discoverable.

## Stop Rules

Stop before final planning when:

- intent or done criteria are still ambiguous
- evidence is too weak to choose between alternatives
- a user/product decision is required
- planning would require a mutating command to gather facts
- destructive, external, credentialed, production, or migration-sensitive work lacks approval boundaries

Do not edit files, implement code, run migrations, run codegen, commit, push, or launch long-running execution from this skill.
