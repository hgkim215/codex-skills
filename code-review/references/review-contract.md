# Review Contract

Use this contract when reviewing a completed diff, PR candidate, changed files, or QA evidence.

## Source of Truth

- Treat `AGENTS.md` as a map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, CI, source paths, and existing plans before guessing project rules.
- Inspect local git state before reviewing an unspecified target.
- Preserve user changes. Do not edit files inside this skill.

## Findings First

- Lead with findings, not a summary.
- Sort by severity: `Critical`, `High`, `Medium`, `Low`.
- Include only actionable issues with a plausible bug, regression, safety, architecture, test, or verification impact.
- Avoid style-only comments unless they mask a concrete risk.

## Finding Evidence

Each finding must include:

- severity
- file and line, diff hunk, command output, screenshot/browser evidence, or QA output section
- issue
- impact
- recommended fix

If line numbers are unavailable, cite the strongest available evidence and state the limitation.

## Review Focus

- Correctness and behavior
- Regressions and compatibility
- Data loss, security, privacy, auth, permissions, or production safety
- Architecture and ownership boundaries
- Missing or weak tests
- Verification gaps and residual risk
- Visual evidence that contradicts claimed completion

## QA Evidence Intake

- For `ralph-qa`, inspect `Reproduction`, `Verification`, `Regression Checks`, and `Residual Risk`.
- Missing same-command reruns or weak regression checks are test gaps.
- For `visual-ralph-qa`, inspect `Issues Found`, `Evidence`, `Viewports`, and `Visual Checks`.
- Missing viewport, screenshot, console, or recheck evidence are visual verification gaps.
- Do not run new QA inside this skill; route to the matching QA skill when evidence is missing.

## Handoff

- Use `ralph-execute` when findings should be fixed.
- Use `ralph-qa` when a failing command must be reproduced and fixed.
- Use `visual-ralph-qa` when browser or screenshot evidence is missing.
- Use `ralplan` when the finding depends on a design or architecture decision.
- Use `cross-verify` only when the user explicitly asks for multi-AI review or 교차검증.

## Goal Completion Decision

For the full lifecycle policy and completion audit template, use the suite-level `../references/goal-lifecycle-contract.md` from the skill root.

When a thread goal is available, decide one of:

- `complete`: the macro objective is fully satisfied and evidence covers the done criteria.
- `keep active`: the reviewed phase passed, but remaining planned work or verification exists.
- `pause`: user judgment, approval, external action, or subjective decision is needed.
- `blocked`: findings, failed checks, missing evidence, or scope conflict prevents completion.

If goal tracking was requested but no active goal exists, report that the macro goal was never initialized instead of creating a review-specific goal. Never treat "no findings" as automatic goal completion. Completion requires a prompt-to-artifact audit against the whole objective.

## Rule Candidates

Record a `Harness Rule Candidate` when the same issue could be prevented by:

- `AGENTS.md` guidance
- repo docs
- lint or static analysis
- tests or CI
- scripts
- skill instruction updates
- review checklist updates

If no candidates exist, write `None`.
