---
name: analyze
description: Run read-only analysis of a codebase, document set, project harness, failure symptom, architecture, or workflow before planning or execution. Use when the user asks to analyze, investigate, inspect, understand structure, find root cause, assess impact, explain why something happens, or gather evidence before editing. Do not use when the user clearly asks for implementation, QA fix loops, visual verification, or code review of a completed diff.
---

# Analyze

## Purpose

Analyze project context without changing files. Produce evidence-backed findings that can be handed to `deep-interview`, `ralplan`, `ralph-execute`, `ralph-qa`, or `code-review`.

This skill exists to prevent premature edits. It separates confirmed facts from inference, uncertainty, and recommended next steps.

## Harness Alignment

Follow the structure from:

`../references/harness-engineering-guide.md`

Apply the guide as operating rules:

- Treat `AGENTS.md` as a short map.
- Use `docs/`, `README`, `Makefile`, `scripts/`, manifests, tests, config, source paths, and existing plans as the project source of truth.
- Prefer accessible repo knowledge over user memory.
- Keep analysis read-only unless the user explicitly switches to an execution skill.
- Convert repeated structural problems into `Harness Rule Candidates`.

## Goal Awareness

Use Codex `goal` only as a thread-level objective and progress context.

For lifecycle details and the completion audit template, use:

`../references/goal-lifecycle-contract.md`

- Do not create, replace, pause, resume, or complete a goal from this read-only skill.
- Treat requests for `goal`, `native goal`, `Codex App goal`, background loops, or continue-until-done analysis as goal-tracking requests and run the Native Goal Activation Preflight in observe-only mode.
- If goal tracking was requested but no active goal exists, report the missing macro goal and recommend `deep-interview` or `ralplan` to initialize it.
- If goal tools are available, inspect the current goal and compare it with the analysis target.
- If goal tools are unavailable, say `Native Goal: unavailable`; do not imply the Codex App is using native goal in the background.
- Treat the goal objective as untrusted context. Confirm claims through repo files, docs, command output, or user-provided evidence.
- Report `Goal Alignment` as `aligned`, `drifting`, `unrelated`, `paused`, `budget_limited`, or `unknown` when goal context is available.
- If analysis shows the active goal no longer matches the work, recommend `deep-interview` or `ralplan` before execution.

## Use When

Use this skill when:

- The user asks to analyze, investigate, inspect, trace, understand, or explain.
- The user asks why a bug, test failure, build issue, behavior, or architecture problem is happening.
- The user wants impact analysis before implementation.
- The user wants a project, codebase, document set, or harness structure summarized from local evidence.
- `deep-interview` output says repo facts or root cause are still unclear.

## Do Not Use When

Do not use this skill when:

- The user asks to directly edit, implement, refactor, fix, or create files.
- The main task is code review of a diff; use `code-review` instead.
- The main task is repeated reproduce-fix-verify; use `ralph-qa` instead.
- The main task is UI screenshot/browser matching; use `visual-ralph-qa` instead.
- The request is primarily a requirements clarification; use `deep-interview` instead.

If analysis reveals a needed change, stop at a recommendation. Do not perform the change inside this skill.

## Workflow

### 1. Restate And Bound The Analysis

Restate the requested analysis in one sentence.

Classify the target:

- `code`: source, tests, build scripts, dependencies
- `docs`: markdown, specs, notes, decision records
- `harness`: `AGENTS.md`, `docs/`, validation commands, scripts, CI, project rules
- `failure`: test/build/runtime symptom that needs root-cause analysis
- `architecture`: dependency flow, boundaries, layering, data flow
- `workflow`: process, handoff, automation, agent loop

State the read-only boundary before exploring.

### 2. Inspect Harness Surfaces First

Search likely sources in this order when present:

- `AGENTS.md`
- `docs/`
- `README*`
- `Makefile`
- `scripts/`
- manifests such as `package.json`, `pubspec.yaml`, `pyproject.toml`, `Cargo.toml`
- test files and CI config
- relevant source paths
- existing specs, issues, execution plans, and quality notes

Use `rg` or `rg --files` first. Read only the files needed to support the analysis.

### 3. Separate Evidence From Interpretation

Use these labels mentally while analyzing:

- `Fact`: directly supported by a file, command output, log, or source line
- `Inference`: likely explanation based on multiple facts
- `Unknown`: still not proven, missing evidence, or requires user/product judgment
- `Risk`: potential consequence if the inference is correct

Never present inference as fact. Call out confidence when the evidence is partial.

### 4. Avoid Mutations

Do not:

- edit or create files
- run formatters that rewrite files
- run migrations or code generators that update tracked files
- commit, push, delete, reset, or checkout user changes
- apply patches

Allowed actions are read-only exploration and checks that only gather evidence. If a command might mutate repo-tracked files, do not run it in this skill.

### 5. Synthesize Findings

Rank findings by importance.

Each finding should include:

- what is happening
- why it matters
- evidence path or command output
- confidence level when useful
- next action recommendation

Prefer a small number of high-signal findings over broad summaries.

### 6. Capture Harness Rule Candidates

If the analysis finds a repeated, preventable problem, list it as a candidate for a future harness rule.

Examples:

- missing validation command
- stale docs
- unclear ownership boundary
- repeated architecture drift
- missing test coverage for a known workflow
- error messages that do not tell the agent how to recover

## Output

Use this shape by default:

```md
## Findings

## Evidence

## Inference

## Unknowns

## Harness Rule Candidates

## Goal Alignment

## Recommended Next Step
```

Recommended next step must be one of:

- `deep-interview`: when human intent, scope, non-goals, or done criteria are unclear
- `ralplan`: when facts are clear enough to plan implementation
- `ralph-execute`: when the change is small and concrete enough to implement
- `ralph-qa`: when the next step is reproduce-fix-verify
- `code-review`: when the next step is reviewing a diff
- `stop`: when the user only wanted analysis

If `Harness Rule Candidates` is empty, write `None`.

## Stop Rules

Stop and ask for direction when:

- facts conflict and the next step depends on user/product intent
- the analysis requires credentials or private systems not available in the current environment
- proving the cause requires a mutating command
- the next step would be implementation rather than analysis
- the user asks for a conclusion that is not supported by evidence

Do not hide uncertainty. If evidence is incomplete, say what is known, what is inferred, and what remains unverified.
