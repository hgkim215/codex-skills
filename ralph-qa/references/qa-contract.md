# QA Contract

Use this contract when a failure, failed verification, or regression check drives the work.

## Source of Truth

- Treat `AGENTS.md` as a map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, CI, source paths, and existing plans before guessing.
- Inspect `git status --short` before editing.
- Preserve user changes and generated work that you did not create.

## Failure Artifact Consumption

- Prefer an exact failing command, test name, stack trace, log excerpt, or CI output.
- If the command is missing, discover likely verification commands from repo docs, scripts, manifests, tests, or CI.
- Do not ask the user for facts that can be discovered from the repo.
- Ask only for human decisions such as expected behavior, scope, approvals, or production boundaries.

## Goal Impact

For the full lifecycle policy and completion audit template, use the suite-level `../references/goal-lifecycle-contract.md` from the skill root.

When a thread goal is available, classify how the failure affects it:

- `blocks goal`: the macro objective cannot finish until this failure is fixed.
- `partial risk`: the failure affects confidence but not the whole objective.
- `not related`: the failure is outside the current goal.
- `complete candidate`: the QA phase appears to satisfy its goal-related gate.
- `unknown`: goal context or evidence is insufficient.

If goal tracking was requested but no active goal exists, report that the macro goal was never initialized instead of creating a QA-specific goal. Do not complete a goal from QA unless the full objective, not just the failing command, has been audited.

## Reproduction First

- Reproduce locally before editing when feasible.
- Record the exact command, failure result, and relevant error lines.
- If local reproduction is impossible, explain the blocker and mark the cause as inference unless another artifact proves it.

## Fix Boundary

- Keep the fix tied to the reproduced failure.
- Prefer the smallest coherent change over broad refactors.
- Update tests only when they prove the corrected behavior or prevent the same regression.
- If the fix requires product or architecture decisions, stop and route to `deep-interview` or `ralplan`.

## Subagent Policy

- Default to main Codex execution for tightly coupled failures.
- Use subagents only for independent hypotheses, disjoint write scopes, or parallel regression coverage.
- Give each worker explicit ownership of files, modules, diagnostics, or tests.
- Tell workers they are not alone in the codebase and must not revert user or other-agent changes.
- Main Codex must decide the final cause, integrate changes, and rerun the same failing command.

## Verification And Regression

- Rerun the same command that reproduced the failure after the fix.
- Add focused regression checks when the touched behavior is shared or high risk.
- If the same command still fails, classify the result as same issue, new issue, or broader task.
- Do not claim success without command evidence unless verification is blocked and the blocker is reported.

## Stop And Approval Boundaries

Stop and ask before:

- destructive git operations
- deleting user data
- external deployment or publication
- credentialed production actions
- payment or irreversible account changes
- broad migrations or generated changes not already approved

## Rule Candidates

When QA reveals a repeated issue, record it as a future harness rule candidate:

- missing or stale verification command
- missing failure reproduction steps
- brittle test setup
- unclear expected behavior
- missing regression coverage
- failure message without recovery guidance
