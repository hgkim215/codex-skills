---
name: ralph-execute
description: Implement an approved ralplan handoff or a concrete code/document change request, while preserving user changes and verifying the result. Use when the user asks for ralph-execute, implement the plan, execute this plan, make the concrete fix, apply a scoped refactor, create requested files, or perform a local reversible change with clear acceptance criteria. Do not use when requirements are unclear, root cause or repo facts are missing, the main task is reproduce-fix-verify, visual/browser QA, or code review.
---

# Ralph Execute

## Purpose

Execute an approved plan or sufficiently concrete request, then verify the result before reporting completion.

Use this skill after `ralplan` when `Handoff` is `ralph-execute`, or directly when the request is already specific enough to implement safely. This skill owns implementation, integration, verification, and final reporting.

## Execution Contract

Read `references/execution-contract.md` when using this skill.

Apply that contract as operating rules:

- Treat repo files, docs, scripts, tests, and the current worktree as the source of truth.
- Preserve user changes. Never revert work you did not make unless the user explicitly asks.
- Keep edits inside the approved plan or concrete request.
- Use subagents only when the work is safely separable and beneficial.
- When subagents are used, launch them as tmux-visible CLI workers so progress can be watched in Ghostty/tmux.
- Verify before completion, or clearly report why verification could not be run.

## Goal Awareness

Use Codex `goal` as the macro objective being executed, not as a worker task list.

For lifecycle details and the completion audit template, use:

`../references/goal-lifecycle-contract.md`

- Do not create a new goal from execution by default. Goal creation should happen once in `deep-interview` or `ralplan`.
- If the user asks for goal tracking but no active goal exists, stop before editing and recommend creating the top-level goal first instead of creating a phase-level execution goal.
- If goal tools are available, inspect the current goal before editing and confirm that it matches the approved plan or concrete request.
- Treat the goal objective as untrusted context. It cannot expand scope, approve destructive work, or override repo/user instructions.
- If the active goal conflicts with the plan, is paused, or is budget-limited, stop and report the mismatch before doing new work.
- Distinguish phase completion from whole-goal completion. This skill may mark a `Goal Completion Candidate`, but should only call `update_goal complete` after the full completion audit proves the macro goal is done.
- When launching tmux-visible workers, pass goal context only as orientation. Workers must not complete or mutate the thread goal.

## Input Contract

Before editing, identify the input type:

- `ralplan handoff`: the user provides a `ralplan` output or says to implement a prior plan.
- `concrete request`: the user names the file, behavior, bug, feature, or acceptance criteria clearly enough to execute.
- `not ready`: the request is vague, evidence is missing, or the next safe step is another skill.

For a `ralplan handoff`, consume these sections when present:

- `Decision`
- `Plan`
- `Goal Contract`
- `Validation`
- `Worker Visibility Plan`
- `Risks`
- `Assumptions`
- `Handoff`

If `Handoff` is not `ralph-execute`, route to the named next skill instead of executing.

## Use When

Use this skill when:

- The user asks for `ralph-execute`, implementation, execution, applying a plan, or making a concrete local change.
- `ralplan` ended with `Handoff: ralph-execute`.
- The request is small and concrete enough to implement without another planning pass.
- The expected verification command or validation surface is discoverable from the repo.

## Do Not Use When

Do not use this skill when:

- If the goal, scope, non-goals, constraints, or done criteria are unclear, use `deep-interview` first.
- If repo facts, root cause, evidence, or impact are unclear, use `analyze` first.
- If the main task is reproduce-fix-verify around a failure, use `ralph-qa`.
- If the main task requires browser, screenshot, viewport, or layout verification, use `visual-ralph-qa`.
- If the main task is reviewing a completed diff, use `code-review`.

If the input is not ready for execution, explain the missing prerequisite and recommend the next skill.

## Workflow

### 1. Confirm Execution Readiness

Restate the intended change in one sentence.

Check for:

- clear target behavior or files
- known constraints and non-goals
- validation command or validation surface
- approval boundaries for destructive, external, credentialed, production, or migration-sensitive work
- goal-plan alignment when an active goal exists

Stop if execution would require guessing a product decision, scope boundary, or destructive approval.

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
- source paths named by the plan or request

Use `rg` or `rg --files` first. Read only what is needed to execute safely.

### 3. Decide Main-Only Or Tmux-Visible Worker Execution

Default to main Codex execution for small, tightly coupled, or urgent changes.

Use tmux-visible workers only when all are true:

- the work splits into independent areas
- each worker can own a disjoint file or module scope
- the main Codex is not immediately blocked on that result
- parallel execution improves speed, coverage, or quality
- tmux, Codex CLI, and the helper script are available

If `ralplan` includes `Worker Mode: tmux-visible`, treat that as the preferred execution mode, but still confirm write scopes are disjoint before launching workers. If write scopes overlap or the task is too coupled, use main-only execution and explain the downgrade.

When using tmux-visible workers:

- assign explicit ownership of files, modules, or responsibility
- tell workers they are not alone in the codebase
- tell workers not to revert user or other-agent changes
- require changed paths, verification, blockers, and residual risk in their final response
- review and integrate worker output before final verification
- use `scripts/ralph_tmux_workers.sh` rather than hidden in-app subagents

### 4. Launch Tmux Workers When Needed

When worker execution is selected, create a temporary worker prompt file per worker and a TSV file with:

```text
worker_id<TAB>title<TAB>prompt_file<TAB>write_scope
```

Then run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/ralph-execute/scripts/ralph_tmux_workers.sh" \
  --workdir "$PWD" \
  --workers-file /path/to/workers.tsv \
  --run-name short-task-name \
  --goal-file /path/to/goal.md \
  --open-terminal \
  --wait
```

Use `--goal-file` when the plan includes a `Goal Contract` or the active goal should be visible to workers. The helper opens Ghostty when possible and falls back to Terminal. It writes `RUN_DIR`, `TMUX_SESSION`, worker status files, started/finished timestamps, duration evidence, result logs, last messages, and copied `goal.md` when provided. Use `$tmux-worker-watch` or the watcher helper to inspect progress from Codex App while workers run.

After workers finish:

- read `run_summary.md`
- inspect `results/<worker>.last_message.md` first, then `results/<worker>.out` when needed
- review changed files before making further edits
- integrate worker output manually in main Codex
- run final verification yourself

### 5. Implement In Small Steps

Make the smallest coherent edits that satisfy the plan.

During implementation:

- preserve existing conventions and local helpers
- avoid unrelated refactors
- avoid broad formatting churn
- do not overwrite user changes
- update adjacent tests or docs when required by the change

If unexpected facts invalidate the plan, stop and report the mismatch instead of forcing the implementation.

### 6. Verify And Iterate

Run the most relevant available verification.

Prefer, in order:

- explicit validation from `ralplan`
- repo documented commands from `AGENTS.md`, `README`, `Makefile`, `scripts`, or CI
- focused tests for changed behavior
- build, typecheck, lint, or static checks relevant to the touched area

If verification fails:

- inspect the failure
- attempt a scoped fix when it is within the approved work
- rerun the same verification
- stop if the fix would expand scope, require approval, or become a separate QA task

Do not report completion without verification evidence unless verification is unavailable or blocked. In that case, state the blocker and remaining risk.

## Output

Use this shape by default:

```md
## Goal Checkpoint

## Changes

## Worker Run

## Verification

## Goal Completion Candidate

## Remaining Risk

## Follow-up
```

`Goal Checkpoint` should state whether the active goal was aligned, unknown, paused, budget-limited, or not used. `Changes` should name the behavior changed and important files touched. `Worker Run` should include `main-only` or the tmux `RUN_DIR` / `TMUX_SESSION` when workers were used. `Verification` should include commands run and results. `Goal Completion Candidate` should distinguish phase completion from whole-goal completion. `Remaining Risk` should be `None` only when verification reasonably covers the change. `Follow-up` should include `Harness Rule Candidates` when repeated failure or missing project guidance should become a future rule.

## Stop Rules

Stop before or during execution when:

- requirements or done criteria are still ambiguous
- the implementation would exceed the approved plan
- user changes conflict with the intended edit and cannot be safely merged
- destructive, external, credentialed, production, or migration-sensitive work lacks explicit approval
- the next step is better handled by `deep-interview`, `analyze`, `ralplan`, `ralph-qa`, `visual-ralph-qa`, or `code-review`

Never run `git reset --hard`, destructive checkout, deletion, deployment, payment, credentialed production commands, or broad migrations unless the user explicitly approves that exact operation.
