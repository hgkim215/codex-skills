#!/usr/bin/env bash
set -Eeuo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="codex"
keep=0

usage() {
  cat <<'USAGE'
Usage:
  e2e_ralph_release.sh [--codex|--deterministic] [--keep]

Runs an end-to-end Ralph worker orchestration check through tmux.

Options:
  --codex          Run a real Codex CLI worker. Default.
  --deterministic  Run a local deterministic worker command instead of Codex CLI.
  --keep           Keep the temporary workspace and run directory for inspection.
  --help           Show this help.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --codex)
      mode="codex"
      shift
      ;;
    --deterministic)
      mode="deterministic"
      shift
      ;;
    --keep)
      keep=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

command -v tmux >/dev/null 2>&1 || fail "tmux is required"
command -v git >/dev/null 2>&1 || fail "git is required"
if [[ "$mode" == "codex" ]]; then
  command -v codex >/dev/null 2>&1 || fail "codex CLI is required for --codex mode"
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/ralph-release-e2e.XXXXXX")"
socket="ralph-release-e2e-$$"
run_dir=""

cleanup() {
  tmux -L "$socket" kill-server >/dev/null 2>&1 || true
  if [[ "$keep" -eq 0 ]]; then
    rm -rf "$tmp_root"
  else
    printf 'KEEP_TMP=%s\n' "$tmp_root"
    if [[ -n "$run_dir" ]]; then
      printf 'KEEP_RUN_DIR=%s\n' "$run_dir"
    fi
  fi
}
trap cleanup EXIT

workdir="$tmp_root/work"
mkdir -p "$workdir"
git -C "$workdir" init -q
printf '# Ralph Release E2E\n' >"$workdir/README.md"
git -C "$workdir" add README.md
git -C "$workdir" -c user.name='Ralph E2E' -c user.email='ralph-e2e@example.invalid' commit -q -m 'seed e2e repo'

goal_file="$tmp_root/goal.md"
prompt_file="$tmp_root/worker.md"
workers_file="$tmp_root/workers.tsv"

cat >"$goal_file" <<'EOF'
# Ralph Release E2E Goal

Validate that a tmux-visible Ralph worker receives goal context, runs to completion, writes evidence, and can be summarized by tmux-worker-watch.
EOF

if [[ "$mode" == "codex" ]]; then
  cat >"$prompt_file" <<'EOF'
You are validating a public-release Ralph skill suite in a disposable git repository.

Task:
- Create or overwrite `e2e-worker-output.txt` in the current repository root.
- The file must contain exactly this text on one line: ralph-e2e-ok
- Do not modify files outside the repository root.
- Do not commit.

Final response requirements:
- Include `E2E_STATUS: ok`
- Include `E2E_CHANGED_PATHS: e2e-worker-output.txt`
EOF
else
  cat >"$prompt_file" <<'EOF'
Deterministic Ralph release worker smoke prompt.
EOF
fi

printf 'worker1\tRelease E2E Worker\t%s\t%s\n' "$prompt_file" "$workdir" >"$workers_file"

export RALPH_WORKER_TMUX_SOCKET="$socket"
export RALPH_WORKER_TIMEOUT_SECONDS="${RALPH_WORKER_TIMEOUT_SECONDS:-180}"
export RALPH_WORKER_WAIT_TIMEOUT_SECONDS="${RALPH_WORKER_WAIT_TIMEOUT_SECONDS:-240}"

if [[ "$mode" == "deterministic" ]]; then
  export RALPH_WORKER_TEST_COMMAND='printf "ralph-e2e-ok\n" > "$RALPH_WORKDIR/e2e-worker-output.txt"; printf "E2E_STATUS: ok\nE2E_CHANGED_PATHS: e2e-worker-output.txt\n" > "$RALPH_LAST_MESSAGE_FILE"; echo "deterministic worker ok"'
else
  unset RALPH_WORKER_TEST_COMMAND || true
fi

output="$(
  "$suite_root/ralph-execute/scripts/ralph_tmux_workers.sh" \
    --workdir "$workdir" \
    --workers-file "$workers_file" \
    --goal-file "$goal_file" \
    --run-name ralph-release-e2e \
    --no-open-terminal \
    --wait
)"
printf '%s\n' "$output"

run_dir="$(printf '%s\n' "$output" | awk -F= '/^RUN_DIR=/{print $2; exit}')"
[[ -n "$run_dir" && -d "$run_dir" ]] || fail "RUN_DIR was not produced"

[[ -f "$run_dir/goal.md" ]] || fail "goal.md was not copied to run dir"
[[ -f "$run_dir/status/worker1.status" ]] || fail "worker status was not written"
[[ "$(head -n 1 "$run_dir/status/worker1.status")" == "0" ]] || fail "worker exited non-zero"
[[ -f "$run_dir/status/worker1.started_at_epoch" ]] || fail "worker start epoch missing"
[[ -f "$run_dir/status/worker1.finished_at_epoch" ]] || fail "worker finish epoch missing"
[[ -f "$run_dir/run_summary.md" ]] || fail "run summary missing"
grep -q 'Goal context: present' "$run_dir/run_summary.md" || fail "run summary missing goal context"
grep -q 'Duration(s)' "$run_dir/run_summary.md" || fail "run summary missing duration column"
grep -q 'Goal Context (untrusted orientation)' "$run_dir/prompts/worker1.md" || fail "worker prompt missing goal context"

[[ -f "$workdir/e2e-worker-output.txt" ]] || fail "worker did not create e2e-worker-output.txt"
grep -qx 'ralph-e2e-ok' "$workdir/e2e-worker-output.txt" || fail "worker output file content mismatch"

watch_output="$(
  TMUX_WORKER_WATCH_SOCKET="$socket" \
    "$suite_root/tmux-worker-watch/scripts/tmux_worker_watch.sh" --status-dir "$run_dir"
)"
printf '\n--- tmux-worker-watch ---\n%s\n' "$watch_output"
printf '%s\n' "$watch_output" | grep -q 'goal_context: present' || fail "watch output missing goal context"
printf '%s\n' "$watch_output" | grep -q 'duration_seconds=' || fail "watch output missing duration"
printf '%s\n' "$watch_output" | grep -q 'worker1: progress=done status=0' || fail "watch output missing done worker"

printf '\nE2E_MODE=%s\n' "$mode"
printf 'E2E_WORKDIR=%s\n' "$workdir"
printf 'E2E_RUN_DIR=%s\n' "$run_dir"
printf 'E2E_RESULT=passed\n'
