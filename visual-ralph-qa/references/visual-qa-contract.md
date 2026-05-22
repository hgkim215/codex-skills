# Visual QA Contract

Use this contract when a browser-rendered UI, screenshot, viewport, or visual state drives the work.

## Source of Truth

- Treat `AGENTS.md` as a map, not the full source of truth.
- Search `docs/`, `README`, `Makefile`, `scripts/`, manifests, routes, source paths, tests, and CI before guessing how to run the UI.
- Inspect `git status --short` before editing.
- Preserve user changes and generated work that you did not create.

## Graph Context

Follow the suite-level `../../references/graph-context-policy.md`.

- Use CodeGraph for route/component discovery, shared UI primitive impact, and design-system boundary checks.
- Skip CodeGraph for tiny localized style changes where the target file is already clear.
- Use ActiveGraph only for long-running or worker-heavy visual QA state when available.
- Use Obsidian only for narrow prior design decisions or user visual preferences.

## Browser Surface Selection

- Prefer Codex Browser for localhost, current in-app browser tabs, file URLs, and interactive inspection.
- Prefer `playwright` for repeatable CLI screenshots, traces, scripted interactions, or multi-viewport capture.
- Follow the `playwright` skill prerequisite check before using its CLI wrapper.
- Do not require OMX, HUD, `.omx/state`, tmux hooks, or Ghostty to perform visual QA.

## Target And Viewports

- Identify the URL, route, screen, component, or state before editing.
- If no viewport is specified, check mobile `390x844` and desktop `1440x900`.
- If a visual issue is stateful, capture the interaction path needed to reach that state.
- If expected appearance is unclear, ask for the human visual decision before changing style.

## Goal Impact

For the full lifecycle policy and completion audit template, use the suite-level `../references/goal-lifecycle-contract.md` from the skill root.

When a thread goal is available, classify how the visual result affects it:

- `blocks goal`: the UI cannot be accepted until fixed.
- `partial risk`: visual confidence is limited or one viewport remains weak.
- `not related`: the visual target is outside the current goal.
- `complete candidate`: the visual QA gate appears satisfied.
- `unknown`: goal context or evidence is insufficient.

If goal tracking was requested but no active goal exists, report that the macro goal was never initialized instead of creating a visual-QA-specific goal. Do not complete a goal from visual QA unless the whole objective has been audited. If the decision is subjective, mark `Human Visual Decision Needed` instead of continuing automatically.

## Visual Checklist

- Page is not blank.
- Primary content is visible and correctly framed.
- Text fits its containers without overlap, clipping, or awkward wrapping.
- Images, icons, fonts, and media load.
- Layout does not overflow unexpectedly.
- Buttons, controls, menus, modals, and focus states are not obscured.
- Console has no relevant rendering or asset errors.
- Mobile and desktop checked viewports both remain usable.

## Fix Boundary

- Keep fixes tied to the observed visual issue.
- Prefer the smallest coherent UI change over broad redesign.
- Preserve the existing design system, spacing conventions, and component patterns.
- Do not introduce unrelated visual themes, decorative backgrounds, or broad styling churn.
- If the fix needs brand, product, or architecture decisions, route to `deep-interview` or `ralplan`.

## Verification Evidence

- Capture baseline evidence before editing when feasible.
- Recheck the same target and same viewport after each fix.
- Include screenshot paths, browser observations, console output, or explicit blockers in the final response.
- Do not claim visual success without browser or screenshot evidence unless the browser surface is unavailable and the blocker is reported.

## Subagent Policy

Follow the suite-level `../../references/orchestration-policy.md`.

- Use worker-first assessment for non-trivial visual QA. Look for independent screens, viewport groups, console/DOM inspection, screenshot comparison, component scopes, or regression review that can run in parallel.
- Prefer subagents for independent screens, disjoint component scopes, parallel viewport review, diagnostic-only inspection, or screenshot/regression review when the expected value beats coordination cost.
- Use main-only when the visual issue is tiny, tightly coupled, unsafe to split, blocked on one immediate browser step, mainly subjective, tooling is unavailable, or the user explicitly asks not to use workers.
- When selecting main-only for non-trivial visual QA, report `No-Worker Justification`.
- Tell workers they are not alone in the codebase and must not revert user or other-agent changes.
- Main Codex must decide the final visual result, integrate changes, and run final browser or screenshot verification.

## Rule Candidates

When visual QA reveals a repeated issue, record it as a future harness rule candidate:

- missing dev server command
- missing route or screen documentation
- missing responsive coverage
- recurring text overflow
- missing asset loading check
- brittle screenshot or browser setup
