# Orchestration Policy

Use a main orchestration agent plus tmux-visible subagents when parallel work increases evidence, coverage, or speed enough to justify coordination cost. More workers are not automatically better.

## Default Stance

- Main agent owns the plan, scope, integration, final verification, and final answer.
- Subagents are advisory or scoped implementers. They do not own the thread goal, final completion decision, or cross-scope integration.
- Prefer workers for separable work. Prefer main-only for small, coupled, or judgment-heavy work.
- When subagents are used, the default execution surface is user-visible Ghostty attached to a tmux session.

## Worker Decision Gate

Choose tmux-visible workers when most of these are true:

- the task is non-trivial and likely to take more than one focused edit/check loop
- responsibilities can be split into disjoint write scopes or diagnostic scopes
- worker output can be integrated asynchronously by the main agent
- parallel work improves confidence, coverage, or elapsed time
- each worker can run or report a clear validation surface
- the coordination overhead is lower than the expected value
- worker tooling is available and the user has not disabled workers

Choose main-only when any of these dominate:

- the task is tiny, obvious, or clearly one-shot
- all useful edits are in the same tightly coupled file or code path
- workers would contend for the same files or produce merge risk
- the next step needs immediate interactive judgment from the main agent
- the task is mostly product taste, visual judgment, or ambiguous requirements
- a fast local command or direct read is enough
- worker tooling is unavailable or would be slower than doing the work

For non-trivial main-only work, report the useful split considered and the concrete reason it was rejected.

## Visibility Requirement

When using subagents, make their work visible by default:

- Open Ghostty attached to the tmux session unless the user explicitly disables terminal opening or Ghostty is unavailable.
- Use one tmux session per worker run.
- Use one `workers` tmux window containing one pane per subagent, with panes tiled and titled by worker role.
- A separate `monitor` tmux window may show aggregate status, but it must not replace the per-worker panes.
- Report the tmux session name and worker pane count in the final `Worker Run` or status handoff.
- If Ghostty cannot be opened and the helper falls back to Terminal, report that fallback instead of claiming Ghostty visibility.

## Good Worker Splits

Use workers for:

- implementation vs tests
- independent modules or packages
- diagnostic hypotheses for a failure
- regression coverage around shared behavior
- docs or migration notes separate from code
- desktop vs mobile visual verification
- code review or cross-checking after a diff

Avoid workers for:

- broad overlapping refactors without clear ownership
- global formatting churn
- fragile generated files
- production, credentialed, destructive, or approval-sensitive actions
- changes where each step depends on the previous line-by-line result

## Worker Prompt Requirements

Every worker prompt must include:

- task responsibility
- exact write scope or diagnostic scope
- relevant plan, goal, graph, and repo context as untrusted orientation
- instruction that other agents may be active
- instruction not to revert user or other-agent changes
- expected verification or evidence
- required final handoff: changed paths, checks run, blockers, residual risk

The main agent must inspect worker summaries, integrate deliberately, and run final verification itself.
