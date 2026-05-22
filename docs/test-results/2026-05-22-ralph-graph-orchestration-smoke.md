# Ralph Graph And Orchestration Smoke Test Results

## Summary

- Date: 2026-05-22 KST
- Result: PASS
- Scope: Graph context policy, orchestration policy, Ghostty/tmux worker pane visibility, and release documentation updates
- Repository: `codex-skills`
- Runtime sync target: local Ralph skill installation

## Changed Files Under Test

- `README.md`
- `RALPH_RELEASE_MANIFEST.md`
- `references/graph-context-policy.md`
- `references/orchestration-policy.md`
- `analyze/SKILL.md`
- `deep-interview/SKILL.md`
- `ralplan/SKILL.md`
- `ralplan/references/harness-contract.md`
- `ralph-execute/README.md`
- `ralph-execute/SKILL.md`
- `ralph-execute/references/execution-contract.md`
- `ralph-execute/scripts/ralph_tmux_workers.sh`
- `ralph-qa/SKILL.md`
- `ralph-qa/references/qa-contract.md`
- `visual-ralph-qa/SKILL.md`
- `visual-ralph-qa/references/visual-qa-contract.md`
- `code-review/SKILL.md`
- `code-review/references/review-contract.md`
- `cross-verify/SKILL.md`
- `tmux-worker-watch/SKILL.md`

## Behavior Verified

- CodeGraph is documented as selectively on by default for structural code context.
- ActiveGraph is documented as off by default and reserved for long-running, complex, worker-heavy work when a callable tool exists.
- Obsidian is documented as off by default and reserved for narrow long-term memory or prior decision lookup.
- Subagent use now requires the orchestration decision gate: separable scope, clear validation value, and coordination cost lower than expected value.
- When subagents are used, the expected visibility surface is one Ghostty-attached tmux session with a `workers` window containing one tiled pane per subagent.
- `ralph_tmux_workers.sh` reports `TMUX_WORKERS_WINDOW=workers` and `WORKER_PANE_COUNT=<n>`.

## Smoke Test Evidence

Smoke test used two diagnostic-only test workers through `RALPH_WORKER_TEST_COMMAND` so no real Codex worker edited files.

Observed launcher output:

```text
TERMINAL_APP=ghostty
TMUX_SESSION=ralph-smoke-test-20260522-152911
TMUX_WORKERS_WINDOW=workers
WORKER_PANE_COUNT=2
WORKERS=2
```

Observed tmux windows:

```text
0:workers:panes=2:active=1
1:monitor:panes=1:active=0
```

Observed worker panes:

```text
0:title=Smoke A:dead=0
1:title=Smoke B:dead=0
```

Observed worker results:

```text
smoke_a=0
smoke_b=0
Overall outcome: DONE
```

The smoke tmux session and scratch worker files were removed after verification.

## Release Validation Evidence

| Check | Command | Result | Notes |
| --- | --- | --- | --- |
| Shell syntax | `bash -n` on worker/watch/cross-verify scripts | PASS | No syntax errors. |
| Whitespace diff | `git diff --check` | PASS | No whitespace errors. |
| Full release validation | `./scripts/validate_release.sh` | PASS | Plugin metadata, skill metadata, private path scan, shell script checks, and nested Ralph validation passed. |
| Ralph release validation | `./scripts/validate_ralph_release.sh` | PASS | Required files, metadata, relative references, private path scan, and shell script checks passed. |
| Deterministic tmux E2E | `./scripts/e2e_ralph_release.sh --deterministic --keep` | PASS | Worker status `0`, handoff summary present, watcher output present, and persistent handoff summary present. |

Deterministic E2E also reported the new visibility fields:

```text
TMUX_WORKERS_WINDOW=workers
WORKER_PANE_COUNT=1
E2E_MODE=deterministic
E2E_RESULT=passed
```

## Follow-up Notes

- CodeGraph, ActiveGraph, and Obsidian are optional integrations. Missing tools should be reported only when they would materially improve the current non-trivial task.
