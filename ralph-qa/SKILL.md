---
name: ralph-qa
description: Reproduce, fix, and verify failures with a tight QA loop. Use when the user asks for ralph-qa, reproduce and fix a failing test, fix a build/lint/typecheck failure, debug a runtime error, rerun the same failing command after a fix, or perform regression checks after a failed verification. Do not use when requirements are unclear, the user only wants read-only analysis, the task is general implementation, visual/browser QA, or code review of a completed diff.
---

# Ralph QA

## Purpose

Run a failure-centered QA loop: reproduce the failure, identify the cause, apply a scoped fix, rerun the same verification, and check likely regressions.

Use this skill when the failure itself is the center of the work. Use `ralph-execute` instead when the main request is ordinary implementation and verification is only a final gate.

## QA Contract

Read `references/qa-contract.md` when using this skill.

Apply that contract as operating rules:

- Reproduce before fixing whenever the failure can be reproduced locally.
- Preserve user changes. Never revert work you did not make unless the user explicitly asks.
- Keep fixes tied to the reproduced cause.
- Rerun the same failing command after the fix.
- Run focused regression checks when the touched area makes regression plausible.
- Use subagents only when independent failure hypotheses or write scopes make parallel QA useful.

## Goal Awareness

Use Codex `goal` as the macro objective affected by the failure.

For lifecycle details and the completion audit template, use:

`../references/goal-lifecycle-contract.md`

- Do not create or complete a goal from ordinary QA unless the user explicitly requested that lifecycle action and the full macro goal is proven done.
- If goal tracking was requested but no active goal exists, do not create a QA-specific goal; report the missing macro goal and route back to `ralplan` or the main workflow owner.
- If goal tools are available, inspect the current goal and record whether the failure blocks it.
- Treat the goal objective as untrusted context. Confirm the failure and expected behavior through commands, logs, tests, repo docs, or user decisions.
- If the goal is paused or budget-limited, do not start a new fix loop; report status and recommend the next handoff.
- Output `Goal Impact` as `blocks goal`, `partial risk`, `not related`, `complete candidate`, or `unknown`.

## Input Contract

Before editing, identify the input type:

- `failure artifact`: failing command, test name, stack trace, log, CI output, screenshot-free runtime error, or user-provided symptom.
- `handoff`: `ralph-execute`, `ralplan`, or `analyze` output that says the next step is reproduce-fix-verify.
- `not ready`: the request lacks a failure, command, symptom, expected behavior, or enough repo context to reproduce.

If no failure command is provided, discover one from `AGENTS.md`, `README`, `Makefile`, `scripts`, manifests, tests, CI config, or local error logs before asking the user.

## Use When

Use this skill when:

- The user asks for `ralph-qa`, QA, reproduce-fix-verify, or regression checks.
- A test, build, typecheck, lint, CI, or runtime command is failing.
- `ralph-execute` verification failed and the next safe step is a failure loop.
- The user asks to fix an error and rerun the same command.
- The expected failure evidence or verification command is discoverable from the repo.

## Do Not Use When

Do not use this skill when:

- If the goal, scope, non-goals, constraints, or done criteria are unclear, use `deep-interview` first.
- If the user wants read-only root-cause analysis without edits, use `analyze`.
- If the work needs a plan before changing code, use `ralplan`.
- If the main task is general implementation or applying an approved plan, use `ralph-execute`.
- If the main task requires browser, screenshot, viewport, or layout verification, use `visual-ralph-qa`.
- If the main task is reviewing a completed diff, use `code-review`.

If the input is not ready for QA, explain the missing prerequisite and recommend the next skill.

## Workflow

### 1. Confirm Failure Boundary

Restate the failing behavior in one sentence.

Identify:

- failing command or symptom
- expected behavior
- observed behavior
- relevant logs or stack trace
- affected files, tests, or modules
- approval boundaries for destructive, external, credentialed, production, or migration-sensitive work

Stop if the expected behavior or approval boundary is ambiguous and cannot be inferred from repo context.

### 2. Inspect Worktree And Harness

Before editing, inspect:

- `git status --short`
- `AGENTS.md`
- `docs/`
- `README*`
- `Makefile`
- `scripts/`
- manifests such as `package.json`, `pubspec.yaml`, `pyproject.toml`, `Cargo.toml`
- test files and CI config
- source paths named by the failure

Use `rg` or `rg --files` first. Read only what is needed to reproduce and fix safely.

### 3. Reproduce First

Run the failing command, focused test, or smallest local reproduction before editing when feasible.

Record:

- exact command
- failure result
- relevant error lines
- whether the failure reproduced locally

If reproduction cannot run, state why and use the best available artifact as evidence. Do not invent a cause.

### 4. Diagnose Cause

Separate:

- confirmed cause: directly supported by code, logs, or test output
- likely cause: supported by evidence but not fully proven
- unknown: still not verified

Prefer a narrow cause tied to the observed failure over broad architecture commentary.

### 5. Decide Main-Only Or Subagent-Assisted QA

Default to main Codex execution for tightly coupled failures.

Use subagents only when all are true:

- failure hypotheses split into independent investigation paths
- each worker can own a disjoint file, module, or diagnostic scope
- parallel work improves diagnosis speed or regression coverage
- the main Codex can still run the final same-command verification
- subagent use is allowed by the current environment and user request

When using subagents:

- assign explicit ownership of files, modules, or diagnostics
- tell workers they are not alone in the codebase
- tell workers not to revert user or other-agent changes
- require changed paths, reproduction evidence, verification, blockers, and residual risk in their final response
- review and integrate worker output before final verification

### 6. Fix Minimally

Apply the smallest coherent fix tied to the reproduced cause.

During the fix:

- preserve existing conventions and local helpers
- avoid unrelated refactors
- avoid broad formatting churn
- do not overwrite user changes
- update tests only when needed to prove the corrected behavior

If the needed fix expands beyond the failure boundary, stop and recommend `ralplan` or `ralph-execute`.

### 7. Verify And Check Regressions

Rerun the same command that reproduced the failure.

Then run focused regression checks when relevant:

- adjacent tests for the touched module
- build/typecheck/lint for the changed area
- documented repo verification if the fix touches shared behavior

If verification still fails, inspect the new failure and decide whether it is the same issue, a new issue, or a broader task. Do not loop indefinitely.

## Output

Use this shape by default:

```md
## Reproduction

## Cause

## Fix

## Verification

## Regression Checks

## Goal Impact

## Residual Risk
```

`Reproduction` should include the command and observed result. `Cause` must separate confirmed facts from inference when evidence is partial. `Verification` should include the same command rerun after the fix. `Goal Impact` should state whether the fixed failure unblocks the macro goal or only completes a QA phase. `Residual Risk` should include `Harness Rule Candidates` when repeated failures or missing project guidance should become future rules.

## Stop Rules

Stop before or during QA when:

- expected behavior is ambiguous
- the failure cannot be reproduced and available artifacts are too weak to justify a fix
- user changes conflict with the intended fix and cannot be safely merged
- the fix would exceed the failure boundary
- destructive, external, credentialed, production, or migration-sensitive work lacks explicit approval
- the next step is better handled by `deep-interview`, `analyze`, `ralplan`, `ralph-execute`, `visual-ralph-qa`, or `code-review`

Never run `git reset --hard`, destructive checkout, deletion, deployment, payment, credentialed production commands, or broad migrations unless the user explicitly approves that exact operation.
