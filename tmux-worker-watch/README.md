# tmux-worker-watch

Read existing tmux worker panes and status files, then summarize progress for the main Codex conversation.

## Use When

- `ralph-execute` worker run의 `RUN_DIR` 상태를 요약하고 싶을 때
- Ghostty/tmux에서 돌아가는 worker 진행 상황을 Codex App에서 보고 싶을 때
- cross-verify 또는 Ralph worker status files를 읽고 blockers를 정리하고 싶을 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill tmux-worker-watch --agent codex --global --yes
```

Restart Codex after installation.

## Requirements

- `tmux`
- A running tmux session or a status directory such as a Ralph worker `RUN_DIR`

For Ralph worker runs, the watcher prefers `worker_handoff_summary.md` when present and can point you to the persistent `.ralph/worker-runs/<run-id>/worker_handoff_summary.md` audit record.

## Example

```text
$tmux-worker-watch 이 RUN_DIR의 worker 진행 상황을 요약해줘: /tmp/ralph-workers.example
```

This skill is read-only. It does not start, stop, type into, or restart workers.
