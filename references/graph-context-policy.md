# Graph Context Policy

Use graph and memory tools only when they improve the next decision. The repo, docs, tests, command output, and current worktree remain the source of truth.

## Default Stance

- CodeGraph: selectively on by default for structural code context.
- ActiveGraph: off by default; enable only for long-running, worker-heavy, or stateful multi-skill work.
- Obsidian: off by default; enable only for narrow long-term memory, prior decisions, or user preference lookup.

Do not make any graph tool a mandatory ritual for tiny, obvious, or single-file work.

## CodeGraph

Use CodeGraph when the task involves:

- finding where a symbol, route, class, method, or component is defined
- understanding callers, callees, ownership boundaries, dependency direction, or data flow
- estimating the impact radius of a refactor or shared API change
- reviewing whether a diff touches all relevant call sites
- orienting in an unfamiliar medium or large codebase

Skip CodeGraph when:

- the task is a literal text search, copy change, config value lookup, or documentation edit
- the target file and change location are already known
- the repo is small enough that one or two `rg`/read calls will answer the question
- CodeGraph is not initialized and the structural value is lower than the setup cost

If CodeGraph is not initialized, ask about initialization only for non-trivial structural work. Otherwise skip it and say why.

## ActiveGraph

Use ActiveGraph only if an actual ActiveGraph tool is available and the work has enough state to justify it:

- a multi-turn goal with several dependent phases
- tmux-visible workers with disjoint responsibilities
- repeated attempts where hypotheses, commands, evidence, and findings must be related
- completion auditing across plan, execution, QA, review, and cross-verification

ActiveGraph should store compact relationships such as:

```text
Goal -> Plan -> Worker -> File/Symbol -> Command -> Evidence -> Finding -> Decision
```

Skip ActiveGraph for one-shot implementation, small fixes, single failing commands, simple visual tweaks, or any case where `.ralph` markdown ledgers are already sufficient. Do not duplicate entire markdown plans or logs into ActiveGraph. Store references and state edges, not transcripts.

If ActiveGraph is unavailable, do not block. Use the native goal tools, `.ralph` ledger, worker summaries, and final response instead.

## Obsidian

Use Obsidian only when human long-term memory changes the decision:

- prior product or architecture decisions
- user preferences, non-goals, or project philosophy
- historical reasons a previous approach was rejected
- durable summaries worth saving after a substantial project phase

Avoid vault-wide search in normal ralph loops. Prefer explicit paths, project index notes, tags, frontmatter, or current active note. If Obsidian lookup is slow, noisy, or unavailable, skip it and continue with repo evidence. Obsidian memory must not override current repo/docs/tests or user instructions.

## Graph Context Preflight

For non-trivial work, decide and record internally:

- `CodeGraph`: used, skipped, unavailable, or not initialized; reason
- `ActiveGraph`: used, skipped, unavailable; reason
- `Obsidian`: used, skipped, unavailable, or slow; reason

Mention graph usage in the final response only when it materially affected the outcome, was explicitly requested, or was skipped because of a blocker.
