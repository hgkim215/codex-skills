# ralph-execute

Implement an approved plan or a concrete local change request, then verify the result.

## Use When

- `$ralplan`이 `Handoff: ralph-execute`로 끝났을 때
- 이미 목표, 파일, 수용 기준이 충분히 구체적인 변경을 적용할 때
- 독립 작업을 tmux-visible Codex CLI workers로 나누고 싶을 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill ralph-execute --agent codex --global --yes
```

Restart Codex after installation.

## Requirements

Main-only execution needs normal Codex file/tool access.

tmux-visible worker execution additionally needs:

- `tmux`
- Codex CLI
- Ghostty preferred for the visible worker window; Terminal fallback is used only if Ghostty is unavailable

## Example

```text
$ralph-execute 위 계획을 구현하고 검증까지 진행해줘.
```

For worker runs, the launcher writes:

- A Ghostty-attached tmux session with a `workers` window containing one tiled pane per subagent
- `RUN_DIR/worker_handoff_summary.md`: immediate user-facing summary of every worker
- `.ralph/worker-runs/<run-id>/worker_handoff_summary.md`: persistent copy inside the workspace
- `.ralph/worker-runs/INDEX.md`: cumulative index of worker-assisted runs

Use `$tmux-worker-watch` to summarize progress from the generated `RUN_DIR` or tmux session.
