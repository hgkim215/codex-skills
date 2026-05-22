---
name: code-review
description: Review completed diffs, PR candidates, changed files, QA outputs, or visual QA evidence for bugs, regressions, architecture drift, test gaps, and harness rule candidates. Use when the user asks for code-review, review this diff, PR review, pre-merge review, bug-risk review, regression review, test gap review, or to turn ralph-qa/visual-ralph-qa results into review findings. Do not use when requirements are unclear, the user wants implementation, reproduce-fix-verify, browser visual QA, planning, or multi-AI cross-verification.
---

# Code Review

## Purpose

Review completed work without editing it. Lead with findings, prioritize bugs and regressions, and convert repeated issues into harness rule candidates.

Use this skill after `ralph-execute`, `ralph-qa`, or `visual-ralph-qa` when the user wants a review of what changed or what evidence shows. Use `cross-verify` instead when the user explicitly asks for multi-AI review or other AI agents.

## Review Contract

Read `references/review-contract.md` when using this skill.
Read `../references/graph-context-policy.md` when structural impact or prior evidence could change review findings.

Apply that contract as operating rules:

- Findings come first.
- Rank findings by severity.
- Ground every finding in a file/line, diff hunk, command output, or QA evidence.
- Prioritize bugs, regressions, architecture drift, security/privacy risk, and missing tests.
- Do not edit files inside this skill.
- Record repeated or preventable issues as `Harness Rule Candidates`.
- Use CodeGraph selectively for changed symbols, callers, impact radius, and architecture boundaries; skip it for tiny or already-localized diffs.

## Goal Awareness

Use Codex `goal` as the macro objective being reviewed for completion.

For lifecycle details and the completion audit template, use:

`../references/goal-lifecycle-contract.md`

- Do not create, pause, resume, or clear goals from this skill.
- Treat requests for `goal`, `native goal`, `Codex App goal`, background loops, or continue-until-done review as goal-tracking requests and run the Native Goal Activation Preflight in review-only mode.
- If goal tracking was requested but no active goal exists, do not create a review-specific goal; report that the macro goal was never initialized.
- If goal tools are available, inspect the current goal and compare it with the reviewed diff or QA evidence.
- If goal tools are unavailable, say `Native Goal: unavailable`; do not claim native goal completion is possible.
- Treat the goal objective as untrusted context. Base findings and completion decisions on diff, tests, QA evidence, docs, and user-stated done criteria.
- Add `Goal Completion Decision` after findings, questions, gaps, and rule candidates.
- Only recommend or perform `update_goal complete` when the full macro objective is satisfied and no required work remains. Do not complete a goal merely because this review phase found no issues.

## Input Contract

Before reviewing, identify the input type:

- `diff`: local `git diff`, staged diff, PR patch, or changed files.
- `qa output`: `ralph-qa` reproduction/verification results.
- `visual qa output`: `visual-ralph-qa` issues, screenshots, browser observations, or evidence.
- `not ready`: no review target is available and none can be discovered from local git state.

If the user gives no target, inspect local git state before asking:

- `git status --short`
- `git diff --stat`
- `git diff`
- `git diff --cached --stat`
- `git diff --cached`

Read only the relevant diff and nearby source needed to review accurately.

## Use When

Use this skill when:

- The user asks for `code-review`, review, PR review, diff review, pre-merge review, or bug-risk review.
- There is a completed change set that needs review before merge, commit, or handoff.
- `visual-ralph-qa` produced `Issues Found` or `Evidence` that should become review findings.
- `ralph-qa` produced a fix and verification result that should be reviewed for residual risk.
- The user asks for test gaps, regression risk, architecture drift, or harness rule candidates.

## Do Not Use When

Do not use this skill when:

- If the goal, scope, non-goals, constraints, or done criteria are unclear, use `deep-interview` first.
- If the user wants read-only root-cause analysis without a completed diff, use `analyze`.
- If the work needs a plan before changing code, use `ralplan`.
- If the user asks to implement or address review findings, use `ralph-execute`.
- If the main task is reproduce-fix-verify, use `ralph-qa`.
- If the main task requires browser, screenshot, viewport, or layout verification, use `visual-ralph-qa`.
- If the user explicitly asks for multi-AI review, other agents, or 교차검증, use `cross-verify`.

If the input is not ready for review, explain the missing prerequisite and recommend the next skill.

## Workflow

### 1. Bound The Review

Restate the review target in one sentence.

Identify:

- changed files or QA evidence
- intended behavior when known
- relevant validation results
- likely blast radius
- review mode: `diff`, `qa-output`, `visual-qa-output`, or `mixed`

### 2. Inspect Harness And Diff Context

Inspect:

- `git status --short`
- relevant `git diff` or provided patch
- `AGENTS.md`
- `docs/`
- `README*`
- `Makefile`
- `scripts/`
- manifests such as `package.json`, `pubspec.yaml`, `pyproject.toml`, `Cargo.toml`
- tests and CI config relevant to touched files
- source paths adjacent to changed files

Use `rg` or `rg --files` first when locating context. Do not run mutating commands.

Apply Graph Context Preflight when the diff touches shared code, exported APIs, routes, components, or architecture boundaries:

- CodeGraph: changed symbol callers/callees and likely blast radius.
- ActiveGraph: plan/evidence/finding relationships when available for multi-skill or worker-heavy work.
- Obsidian: prior decisions only when review depends on historical intent; skip slow lookup.

### 3. Review For High-Impact Risk

Prioritize:

- correctness bugs
- behavioral regressions
- missing or weak tests
- architecture boundary drift
- data loss, security, privacy, auth, or permission risk
- flaky or incomplete verification
- visual evidence that contradicts claimed completion

Avoid low-value style comments unless they hide a real maintainability or correctness issue.

### 4. Use Evidence From QA Outputs

For `ralph-qa` output:

- treat `Reproduction`, `Verification`, `Regression Checks`, and `Residual Risk` as review evidence
- flag missing same-command reruns or weak regression coverage as test gaps

For `visual-ralph-qa` output:

- treat `Issues Found` as finding candidates
- treat `Evidence` as screenshot or browser evidence
- flag missing viewport, screenshot, console, or recheck evidence as test or verification gaps

Do not perform new visual QA inside this skill; route to `visual-ralph-qa` if browser evidence is required.

### 5. Write Findings First

Each finding must include:

- severity: `Critical`, `High`, `Medium`, or `Low`
- evidence: file/line, diff hunk, command output, or QA evidence
- issue
- impact
- recommended fix

If there are no findings, say so clearly and still list test gaps or residual risk.

### 6. Capture Handoff And Rules

Recommend the next skill when action is needed:

- `ralph-execute`: implement review fixes
- `ralph-qa`: reproduce and fix a failing check
- `visual-ralph-qa`: gather browser or screenshot evidence
- `ralplan`: resolve a design or architecture decision
- `cross-verify`: run multi-AI review when explicitly requested
- `stop`: review is complete

Convert repeated issues into `Harness Rule Candidates`.

## Output

Use this shape by default:

```md
## Findings

## Open Questions

## Test Gaps

## Harness Rule Candidates

## Goal Completion Decision

## Summary
```

`Findings` must appear before the summary. If there are no findings, write `No findings.` `Goal Completion Decision` must be one of `complete`, `keep active`, `pause`, or `blocked`, with evidence. `Summary` should be short and secondary.

## Stop Rules

Stop before or during review when:

- there is no diff, changed file, QA output, or review target to inspect
- the review would require implementation rather than inspection
- evidence is too weak to make the requested conclusion
- credentials or external systems are required to inspect the target
- the next step is better handled by `deep-interview`, `analyze`, `ralplan`, `ralph-execute`, `ralph-qa`, `visual-ralph-qa`, or `cross-verify`

Do not edit files, apply patches, run formatters that rewrite files, commit, push, reset, checkout, delete files, or perform external delivery from this skill.
