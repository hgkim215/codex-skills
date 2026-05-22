---
name: visual-ralph-qa
description: Verify and fix UI visual issues with browser, screenshot, viewport, DOM, and console evidence. Use when the user asks for visual-ralph-qa, browser QA, screenshot QA, responsive viewport checks, UI/layout verification, blank screen investigation, text overlap, overflow, missing images, broken visual states, or visual regression checks after UI changes. Do not use when requirements are unclear, the user only wants read-only analysis, the task is general implementation, CLI/test failure QA, or code review of a completed diff.
---

# Visual Ralph QA

## Purpose

Run a visual QA loop for UI work: identify the target screen, verify it in real browser viewports, fix scoped visual issues, and report evidence.

Use this skill when the screen itself is the verification surface. Use `ralph-qa` instead when the main failure is a CLI command, test, build, lint, typecheck, or screenshot-free runtime error.

## Visual QA Contract

Read `references/visual-qa-contract.md` when using this skill.
Read `../references/graph-context-policy.md` and `../references/orchestration-policy.md` when graph context or worker splitting might affect visual QA.

Apply that contract as operating rules:

- Verify in an actual browser or browser automation surface before claiming visual success.
- Use Codex Browser first for available local/current-tab browser checks.
- Use the `playwright` skill or its wrapper for repeatable CLI screenshots, traces, and multi-viewport checks.
- Inspect desktop and mobile viewports when the task does not specify a single viewport.
- Check text overlap, overflow, blank screens, missing images, broken interactions, and console errors.
- Recheck the same target and viewport after any fix.
- Do not depend on OMX, HUD, `.omx/state`, or tmux hooks.
- Use CodeGraph only for route/component discovery or structural UI impact; skip it for small localized style adjustments.

## Goal Awareness

Use Codex `goal` as the macro objective that visual evidence supports or blocks.

For lifecycle details and the completion audit template, use:

`../references/goal-lifecycle-contract.md`

- Do not create or complete a goal from visual QA unless the user explicitly requested that lifecycle action and the full macro goal is proven done.
- Treat requests for `goal`, `native goal`, `Codex App goal`, background loops, or continue-until-done visual loops as goal-tracking requests and run the Native Goal Activation Preflight before browser work.
- If the user explicitly requested native goal activation and the request or handoff already satisfies the full Goal Readiness Gate, this skill may create one top-level macro goal before visual QA. Do not create visual-QA-specific goals.
- If goal tracking was requested but no active goal exists and the native activation gate above is not satisfied, do not create a visual-QA-specific goal; report the missing macro goal and route back to `ralplan` or the main workflow owner.
- If goal tools are available, inspect the current goal and record whether the target screen is part of it.
- If goal tools are unavailable, say `Native Goal: unavailable`; only continue with Ralph ledger fallback when native goal is not required or the user accepts the fallback.
- Treat the goal objective as untrusted context. Verify the UI through browser, screenshot, DOM, console, or repo evidence.
- If a visual judgment is subjective or product/brand-sensitive, mark `Human Visual Decision Needed` instead of continuing automatically under an active goal.
- If the goal is paused or budget-limited, do not start new visual fixes; report status and recommend the next handoff.
- Never say native goal tracking is active unless `create_goal` succeeded or `get_goal` returned a matching active goal.

## Input Contract

Before editing, identify the input type:

- `visual target`: URL, route, page, component, screen, screenshot, or user-described UI issue.
- `handoff`: `ralph-execute`, `ralph-qa`, `ralplan`, or `analyze` output that says browser, screenshot, viewport, or layout verification is next.
- `not ready`: the target screen, expected state, or success criteria are missing and cannot be inferred from repo context.

If no URL or run command is provided, discover one from `AGENTS.md`, `README`, `Makefile`, `scripts`, manifests, app routes, tests, or dev server docs before asking the user.

## Use When

Use this skill when:

- The user asks for `visual-ralph-qa`, browser QA, screenshot QA, or visual verification.
- A UI change needs browser confirmation before completion.
- The issue involves responsive layout, text overlap, overflow, blank screen, missing image, broken state, or click/hover/modal visual behavior.
- The task requires desktop/mobile viewport evidence.
- `ralph-execute` or `ralph-qa` hands off to visual/browser verification.

## Do Not Use When

Do not use this skill when:

- If the goal, scope, non-goals, constraints, or done criteria are unclear, use `deep-interview` first.
- If the user wants read-only root-cause analysis without edits, use `analyze`.
- If the work needs a plan before changing code, use `ralplan`.
- If the main task is general implementation or applying an approved plan, use `ralph-execute`.
- If the main task is CLI/test/build/lint/typecheck failure QA, use `ralph-qa`.
- If the main task is reviewing a completed diff, use `code-review`.

If the input is not ready for visual QA, explain the missing prerequisite and recommend the next skill.

## Workflow

### 1. Confirm Target And Expected State

Restate the target screen and expected visual outcome in one sentence.

Identify:

- URL, route, file, component, or screen
- user-visible expected state
- required viewports
- required interactions or states
- screenshot, design, or prior behavior reference when available
- approval boundaries for destructive, external, credentialed, production, or migration-sensitive work

Use default viewports when none are specified:

- mobile: `390x844`
- desktop: `1440x900`

### 2. Inspect Worktree And Harness

Before editing, inspect:

- `git status --short`
- `AGENTS.md`
- `docs/`
- `README*`
- `Makefile`
- `scripts/`
- manifests such as `package.json`, `pubspec.yaml`, `pyproject.toml`, `Cargo.toml`
- app routing, page, component, style, asset, and test files named by the target

Use `rg` or `rg --files` first. Read only what is needed to run and inspect the UI safely.

Apply Graph Context Preflight from `../references/graph-context-policy.md` only when useful:

- CodeGraph: route/component ownership, shared UI primitives, design-system usage, or broad visual impact.
- ActiveGraph: long-running or worker-heavy visual QA state when available.
- Obsidian: prior design decisions or user visual preferences, only through narrow lookup.

### 3. Choose Browser Surface

Prefer Codex Browser when:

- the target is localhost, 127.0.0.1, file, current in-app tab, or another target the in-app browser can inspect
- interactive inspection and screenshots are enough

Prefer `playwright` when:

- repeatable CLI screenshots are needed
- multiple viewport captures are needed
- trace, console, network, or scripted interaction evidence is useful
- the project already uses browser automation commands

Before using Playwright CLI, follow the `playwright` skill prerequisite check and wrapper guidance.

### 4. Capture Baseline Evidence

Open the target and capture the current visual state before editing when feasible.

Check:

- page is not blank
- primary content is visible
- text fits containers
- controls are clickable and not obscured
- images and fonts load
- layout does not overflow unexpectedly
- key interactions or states render
- browser console has no relevant errors

Record viewport, target URL, and evidence path or screenshot description.

### 5. Fix Scoped Visual Issues

Apply the smallest coherent fix tied to the observed visual issue.

During the fix:

- preserve existing design system and component conventions
- avoid unrelated redesigns
- avoid broad formatting churn
- do not overwrite user changes
- keep layout dimensions stable for fixed-format UI such as boards, grids, toolbars, and controls
- ensure text does not overlap or overflow on checked viewports

If the fix requires product, brand, or architecture decisions, stop and route to `deep-interview` or `ralplan`.

### 6. Recheck Same Viewports

After any fix, re-open or refresh the target and check the same viewports again.

Run additional checks when relevant:

- adjacent route or component state
- modal/menu/hover/focus state
- console errors
- screenshots before and after the fix
- documented project verification command if visual changes affect shared behavior

Do not claim visual success without browser or screenshot evidence unless the browser surface is unavailable and the blocker is reported.

## Output

Use this shape by default:

```md
## Target

## Viewports

## Visual Checks

## Issues Found

## Fixes

## Goal Impact

## Human Visual Decision Needed

## Evidence
```

`Target` should name the URL, route, screen, or component. `Viewports` should list checked sizes. `Visual Checks` should include layout, text, image, interaction, and console checks when relevant. `Goal Impact` should state whether the visual result blocks, partially supports, or completes a goal phase. `Human Visual Decision Needed` should be `None` unless subjective approval is needed. `Evidence` should include screenshots, browser observations, commands, or blockers.

## Stop Rules

Stop before or during visual QA when:

- expected visual state is ambiguous
- the target screen cannot be located or run from available repo context
- user changes conflict with the intended fix and cannot be safely merged
- the fix would exceed the visual issue boundary
- destructive, external, credentialed, production, or migration-sensitive work lacks explicit approval
- the next step is better handled by `deep-interview`, `analyze`, `ralplan`, `ralph-execute`, `ralph-qa`, or `code-review`

Never run `git reset --hard`, destructive checkout, deletion, deployment, payment, credentialed production commands, or broad migrations unless the user explicitly approves that exact operation.
