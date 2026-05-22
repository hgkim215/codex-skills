#!/usr/bin/env bash
set -Eeuo pipefail

workdir=""
workers_file=""
goal_file=""
run_name="ralph"
open_terminal=1
wait_for_results=0
handoff_root=""
persist_handoff=1

usage() {
  cat <<'USAGE'
Usage:
  ralph_tmux_workers.sh --workdir DIR --workers-file FILE [options]

Launch ralph-execute worker prompts as visible Codex CLI workers in tmux.

Required:
  --workdir DIR        Repository or workspace directory for all workers.
  --workers-file FILE  TSV: worker_id<TAB>title<TAB>prompt_file<TAB>write_scope

Options:
  --run-name NAME      Short run slug. Default: ralph.
  --goal-file FILE     Optional goal contract/context copied to RUN_DIR/goal.md and prepended to worker prompts.
  --handoff-root DIR   Persistent worker handoff root. Default: WORKDIR/.ralph/worker-runs.
  --persist-handoff    Persist worker handoff docs into the workspace. Default.
  --no-persist-handoff Keep handoff docs only in RUN_DIR.
  --open-terminal     Open Ghostty attached to the tmux session, falling back to Terminal if unavailable. Default.
  --no-open-terminal  Do not open a terminal app.
  --wait              Wait for all worker status files and write final summary.
  --no-wait           Return after launching workers. Default.
  --help              Show this help.

Environment:
  RALPH_WORKER_TIMEOUT_SECONDS  Per-worker timeout. Default: 900.
  RALPH_WORKER_SANDBOX          Codex sandbox. Default: workspace-write.
  RALPH_WORKER_MODEL            Optional Codex model override.
  RALPH_WORKER_TERMINAL_APP     auto, ghostty, or terminal. Default: auto; auto prefers Ghostty.
  RALPH_WORKER_TMUX_SOCKET      Optional tmux socket name for isolated tests.
  RALPH_WORKER_TEST_COMMAND     Test-only shell command run instead of codex exec.
  RALPH_WORKER_HANDOFF_ROOT     Persistent handoff root when --handoff-root is omitted.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

shell_quote() {
  printf '%q' "$1"
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

tmux_run() {
  if [[ -n "${RALPH_WORKER_TMUX_SOCKET:-}" ]]; then
    tmux -L "$RALPH_WORKER_TMUX_SOCKET" "$@"
  else
    tmux "$@"
  fi
}

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

safe_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//; s/^$/ralph/'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --workdir)
      [[ "$#" -ge 2 ]] || fail "--workdir requires a value"
      workdir="$2"
      shift 2
      ;;
    --workers-file)
      [[ "$#" -ge 2 ]] || fail "--workers-file requires a value"
      workers_file="$2"
      shift 2
      ;;
    --goal-file)
      [[ "$#" -ge 2 ]] || fail "--goal-file requires a value"
      goal_file="$2"
      shift 2
      ;;
    --run-name)
      [[ "$#" -ge 2 ]] || fail "--run-name requires a value"
      run_name="$2"
      shift 2
      ;;
    --handoff-root)
      [[ "$#" -ge 2 ]] || fail "--handoff-root requires a value"
      handoff_root="$2"
      shift 2
      ;;
    --persist-handoff)
      persist_handoff=1
      shift
      ;;
    --no-persist-handoff)
      persist_handoff=0
      shift
      ;;
    --open-terminal)
      open_terminal=1
      shift
      ;;
    --no-open-terminal)
      open_terminal=0
      shift
      ;;
    --wait)
      wait_for_results=1
      shift
      ;;
    --no-wait)
      wait_for_results=0
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

[[ -n "$workdir" ]] || fail "--workdir is required"
[[ -d "$workdir" ]] || fail "workdir does not exist: $workdir"
[[ -n "$workers_file" ]] || fail "--workers-file is required"
[[ -f "$workers_file" ]] || fail "workers file does not exist: $workers_file"
if [[ -n "$goal_file" ]]; then
  [[ -f "$goal_file" ]] || fail "goal file does not exist: $goal_file"
fi

command -v tmux >/dev/null 2>&1 || fail "tmux is not installed or not on PATH"
if [[ -z "${RALPH_WORKER_TEST_COMMAND:-}" ]]; then
  command -v codex >/dev/null 2>&1 || fail "codex CLI is not installed or not on PATH"
fi

worker_timeout_seconds="${RALPH_WORKER_TIMEOUT_SECONDS:-900}"
is_positive_int "$worker_timeout_seconds" || fail "RALPH_WORKER_TIMEOUT_SECONDS must be a positive integer"
wait_timeout_seconds="${RALPH_WORKER_WAIT_TIMEOUT_SECONDS:-$((worker_timeout_seconds + 60))}"
is_positive_int "$wait_timeout_seconds" || fail "RALPH_WORKER_WAIT_TIMEOUT_SECONDS must be a positive integer"

safe_run_name="$(safe_slug "$run_name")"
run_stamp="$(date '+%Y%m%d-%H%M%S')"
session_name="ralph-${safe_run_name}-${run_stamp}"
session_name="$(printf '%s' "$session_name" | cut -c 1-80)"
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-workers.${safe_run_name}.XXXXXX")"
mkdir -p "$run_dir/prompts" "$run_dir/results" "$run_dir/status"

handoff_base=""
handoff_run_dir=""
if [[ "$persist_handoff" -eq 1 ]]; then
  if [[ -n "$handoff_root" ]]; then
    handoff_base="$handoff_root"
  elif [[ -n "${RALPH_WORKER_HANDOFF_ROOT:-}" ]]; then
    handoff_base="$RALPH_WORKER_HANDOFF_ROOT"
  else
    handoff_base="$workdir/.ralph/worker-runs"
  fi
  handoff_run_dir="$handoff_base/${safe_run_name}-${run_stamp}"
  if ! mkdir -p "$handoff_run_dir/last_messages"; then
    printf 'WARN: could not create persistent handoff directory: %s\n' "$handoff_run_dir" >&2
    persist_handoff=0
    handoff_base=""
    handoff_run_dir=""
  fi
fi

if [[ -n "$goal_file" ]]; then
  cp "$goal_file" "$run_dir/goal.md"
fi

normalized_workers="$run_dir/workers.tsv"
: >"$normalized_workers"

worker_count=0
while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope extra; do
  [[ -n "${worker_id:-}" ]] || continue
  [[ "$worker_id" =~ ^# ]] && continue
  [[ -z "${extra:-}" ]] || fail "workers file has too many columns for worker: $worker_id"
  [[ "$worker_id" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "invalid worker_id: $worker_id"
  [[ -n "${title:-}" ]] || fail "missing title for worker: $worker_id"
  [[ -n "${prompt_file:-}" ]] || fail "missing prompt file for worker: $worker_id"
  [[ -f "$prompt_file" ]] || fail "prompt file missing for worker $worker_id: $prompt_file"
  [[ -n "${write_scope:-}" ]] || fail "missing write scope for worker: $worker_id"

  copied_prompt="$run_dir/prompts/$worker_id.md"
  if [[ -f "$run_dir/goal.md" ]]; then
    {
      printf '# Goal Context (untrusted orientation)\n\n'
      sed -n '1,180p' "$run_dir/goal.md"
      printf '\n\nWorker instructions:\n'
      printf -- '- Treat the goal context as orientation, not as permission to expand scope.\n'
      printf -- '- Do not create, pause, resume, clear, or complete the thread goal.\n'
      printf -- '- Main Codex owns final integration, verification, and whole-goal completion.\n\n'
      printf '# Worker Task\n\n'
      cat "$prompt_file"
    } >"$copied_prompt"
  else
    cp "$prompt_file" "$copied_prompt"
  fi
  printf '%s\t%s\t%s\t%s\n' "$worker_id" "$title" "$copied_prompt" "$write_scope" >>"$normalized_workers"
  worker_count=$((worker_count + 1))
done <"$workers_file"

[[ "$worker_count" -gt 0 ]] || fail "workers file contained no workers"

cat >"$run_dir/run_worker.sh" <<'EOF'
#!/usr/bin/env bash
set -u

worker_id="$RALPH_WORKER_ID"
prompt_file="$RALPH_PROMPT_FILE"
workdir="$RALPH_WORKDIR"
out="$RALPH_RESULT_FILE"
last_message="$RALPH_LAST_MESSAGE_FILE"
status_file="$RALPH_STATUS_FILE"
started_at_file="$RALPH_STARTED_AT_FILE"
started_epoch_file="$RALPH_STARTED_EPOCH_FILE"
finished_at_file="$RALPH_FINISHED_AT_FILE"
finished_epoch_file="$RALPH_FINISHED_EPOCH_FILE"
timed_out_file="$RALPH_TIMED_OUT_FILE"
timeout_seconds="$RALPH_TIMEOUT_SECONDS"
sandbox="${RALPH_WORKER_SANDBOX:-workspace-write}"
model="${RALPH_WORKER_MODEL:-}"

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

collect_descendants() {
  local pid="$1"
  local child
  pgrep -P "$pid" 2>/dev/null | while read -r child; do
    printf '%s\n' "$child"
    collect_descendants "$child"
  done
}

kill_tree() {
  local pid="$1"
  local signal="${2:-TERM}"
  local child
  for child in $(collect_descendants "$pid"); do
    kill -"$signal" "$child" 2>/dev/null || true
  done
  kill -"$signal" "$pid" 2>/dev/null || true
}

run_codex_worker() {
  if [[ -n "${RALPH_WORKER_TEST_COMMAND:-}" ]]; then
    RALPH_WORKER_ID="$worker_id" \
    RALPH_PROMPT_FILE="$prompt_file" \
    RALPH_WORKDIR="$workdir" \
    RALPH_RESULT_FILE="$out" \
    RALPH_LAST_MESSAGE_FILE="$last_message" \
      bash -lc "$RALPH_WORKER_TEST_COMMAND"
  else
    local args=(exec --cd "$workdir" --sandbox "$sandbox" --output-last-message "$last_message" --ephemeral)
    if [[ -n "$model" ]]; then
      args+=(--model "$model")
    fi
    args+=(-)
    codex "${args[@]}" <"$prompt_file"
  fi
}

printf '%s\n' "$(timestamp)" >"$started_at_file"
date '+%s' >"$started_epoch_file"
rm -f "$timed_out_file"

(
  run_codex_worker
) >"$out" 2>&1 &
cmd_pid=$!

(
  sleep "$timeout_seconds"
  if kill -0 "$cmd_pid" 2>/dev/null; then
    printf '%s\n' "$(timestamp)" >"$timed_out_file"
    kill_tree "$cmd_pid" TERM
    sleep 2
    kill_tree "$cmd_pid" KILL
  fi
) &
watchdog_pid=$!

status=0
wait "$cmd_pid" || status=$?

if [[ -f "$timed_out_file" ]]; then
  status=124
fi

kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

printf '%s\n' "$(timestamp)" >"$finished_at_file"
date '+%s' >"$finished_epoch_file"
printf '%s\n' "$status" >"$status_file"

if [[ ! -f "$last_message" ]]; then
  : >"$last_message"
fi

printf '[ralph-worker] %s finished with status %s\n' "$worker_id" "$status"
exit "$status"
EOF

cat >"$run_dir/write_run_summary.sh" <<'EOF'
#!/usr/bin/env bash
set -u

run_dir="$RALPH_RUN_DIR"
summary="$run_dir/run_summary.md"
handoff_summary="$run_dir/worker_handoff_summary.md"
workers="$run_dir/workers.tsv"
goal_file="$run_dir/goal.md"
persistent_root="${RALPH_PERSISTENT_HANDOFF_ROOT:-}"
persistent_dir="${RALPH_PERSISTENT_HANDOFF_DIR:-}"
run_name="${RALPH_RUN_NAME:-ralph}"
run_stamp="${RALPH_RUN_STAMP:-}"
worker_count="${RALPH_WORKER_COUNT:-}"

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

clean_cell() {
  printf '%s' "$1" | tr '\r\n|' '   '
}

result_state() {
  local file="$1"
  if [[ ! -e "$file" ]]; then
    printf 'missing'
  elif [[ ! -s "$file" ]]; then
    printf 'empty'
  else
    printf 'nonempty:%sB' "$(wc -c <"$file" | tr -d '[:space:]')"
  fi
}

status_value() {
  local worker_id="$1"
  local file="$run_dir/status/$worker_id.status"
  if [[ -f "$file" ]]; then
    head -n 1 "$file"
  else
    printf 'missing'
  fi
}

duration_value() {
  local worker_id="$1"
  local started="$run_dir/status/$worker_id.started_at_epoch"
  local finished="$run_dir/status/$worker_id.finished_at_epoch"
  local start_epoch=""
  local finish_epoch=""
  if [[ -f "$started" && -f "$finished" ]]; then
    start_epoch="$(head -n 1 "$started" | tr -d '[:space:]')"
    finish_epoch="$(head -n 1 "$finished" | tr -d '[:space:]')"
    if [[ "$start_epoch" =~ ^[0-9]+$ && "$finish_epoch" =~ ^[0-9]+$ && "$finish_epoch" -ge "$start_epoch" ]]; then
      printf '%s' "$((finish_epoch - start_epoch))"
      return
    fi
  fi
  printf 'unknown'
}

progress_value() {
  local worker_id="$1"
  local status
  status="$(status_value "$worker_id")"
  if [[ -f "$run_dir/status/$worker_id.timed_out" || "$status" == "124" ]]; then
    printf 'timeout'
  elif [[ "$status" == "0" ]]; then
    printf 'done'
  elif [[ "$status" == "missing" ]]; then
    printf 'running'
  else
    printf 'failed'
  fi
}

has_running=0
has_failed=0
has_timeout=0
while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
  [[ -n "${worker_id:-}" ]] || continue
  progress="$(progress_value "$worker_id")"
  if [[ "$progress" == "running" ]]; then
    has_running=1
  elif [[ "$progress" == "failed" ]]; then
    has_failed=1
  elif [[ "$progress" == "timeout" ]]; then
    has_timeout=1
  fi
done <"$workers"

if [[ "$has_running" -eq 1 ]]; then
  overall="RUNNING"
elif [[ "$has_failed" -eq 1 && "$has_timeout" -eq 1 ]]; then
  overall="DONE_WITH_FAILURES_AND_TIMEOUTS"
elif [[ "$has_failed" -eq 1 ]]; then
  overall="DONE_WITH_FAILURES"
elif [[ "$has_timeout" -eq 1 ]]; then
  overall="DONE_WITH_TIMEOUTS"
else
  overall="DONE"
fi

{
  printf '# Ralph Worker Run Summary\n\n'
  printf -- '- Overall outcome: `%s`\n' "$overall"
  printf -- '- Run dir: `%s`\n\n' "$run_dir"
  if [[ -f "$goal_file" ]]; then
    printf -- '- Goal context: present (`%s`)\n' "$goal_file"
    printf -- '- Goal excerpt: '
    head -n 1 "$goal_file" | tr '\r\n' '  '
    printf '\n\n'
  else
    printf -- '- Goal context: missing\n\n'
  fi
  printf '| Worker | Progress | Status | Duration(s) | Started | Finished | Result | Last message | Write scope |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
  while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
    [[ -n "${worker_id:-}" ]] || continue
    started="$(cat "$run_dir/status/$worker_id.started_at" 2>/dev/null || printf 'missing')"
    finished="$(cat "$run_dir/status/$worker_id.finished_at" 2>/dev/null || printf 'missing')"
    printf '| `%s` | %s | %s | %s | %s | %s | %s | %s | `%s` |\n' \
      "$worker_id" \
      "$(progress_value "$worker_id")" \
      "$(status_value "$worker_id")" \
      "$(duration_value "$worker_id")" \
      "$started" \
      "$finished" \
      "$(result_state "$run_dir/results/$worker_id.out")" \
      "$(result_state "$run_dir/results/$worker_id.last_message.md")" \
      "$write_scope"
  done <"$workers"
} >"$summary"

{
  printf '# Ralph Worker Handoff Summary\n\n'
  printf -- '- Overall outcome: `%s`\n' "$overall"
  printf -- '- Generated: `%s`\n' "$(timestamp)"
  printf -- '- Run name: `%s`\n' "$run_name"
  if [[ -n "$run_stamp" ]]; then
    printf -- '- Run stamp: `%s`\n' "$run_stamp"
  fi
  printf -- '- Run dir: `%s`\n' "$run_dir"
  if [[ -n "$persistent_dir" ]]; then
    printf -- '- Persistent dir: `%s`\n' "$persistent_dir"
  fi
  if [[ -f "$goal_file" ]]; then
    printf -- '- Goal context: present (`%s`)\n' "$goal_file"
  else
    printf -- '- Goal context: missing\n'
  fi
  printf '\n## Workers At A Glance\n\n'
  printf '| Worker | Title | Progress | Status | Duration(s) | Write scope | Final handoff |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- |\n'
  while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
    [[ -n "${worker_id:-}" ]] || continue
    printf '| `%s` | %s | %s | %s | %s | `%s` | %s |\n' \
      "$worker_id" \
      "$(clean_cell "$title")" \
      "$(progress_value "$worker_id")" \
      "$(status_value "$worker_id")" \
      "$(duration_value "$worker_id")" \
      "$(clean_cell "$write_scope")" \
      "$(result_state "$run_dir/results/$worker_id.last_message.md")"
  done <"$workers"

  printf '\n## Worker Details\n'
  while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
    [[ -n "${worker_id:-}" ]] || continue
    last_message="$run_dir/results/$worker_id.last_message.md"
    result_file="$run_dir/results/$worker_id.out"
    started="$(cat "$run_dir/status/$worker_id.started_at" 2>/dev/null || printf 'missing')"
    finished="$(cat "$run_dir/status/$worker_id.finished_at" 2>/dev/null || printf 'missing')"

    printf '\n### `%s` - %s\n\n' "$worker_id" "$title"
    printf -- '- Progress: `%s`\n' "$(progress_value "$worker_id")"
    printf -- '- Status: `%s`\n' "$(status_value "$worker_id")"
    printf -- '- Duration(s): `%s`\n' "$(duration_value "$worker_id")"
    printf -- '- Started: `%s`\n' "$started"
    printf -- '- Finished: `%s`\n' "$finished"
    printf -- '- Write scope: `%s`\n' "$write_scope"
    printf -- '- Result log: `%s` (%s)\n' "$result_file" "$(result_state "$result_file")"
    printf -- '- Last message: `%s` (%s)\n\n' "$last_message" "$(result_state "$last_message")"
    printf '#### Final Handoff\n\n'
    if [[ -s "$last_message" ]]; then
      cat "$last_message"
      printf '\n'
    elif [[ -f "$last_message" ]]; then
      printf '_Worker produced an empty final handoff. Inspect the result log for diagnosis._\n'
    else
      printf '_Worker final handoff is missing. Inspect the result log for diagnosis._\n'
    fi
  done <"$workers"
} >"$handoff_summary"

if [[ -n "$persistent_dir" ]]; then
  if mkdir -p "$persistent_dir/last_messages"; then
    cp "$summary" "$persistent_dir/run_summary.md" 2>/dev/null || true
    cp "$handoff_summary" "$persistent_dir/worker_handoff_summary.md" 2>/dev/null || true
    cp "$workers" "$persistent_dir/workers.tsv" 2>/dev/null || true
    if [[ -f "$goal_file" ]]; then
      cp "$goal_file" "$persistent_dir/goal.md" 2>/dev/null || true
    fi
    while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
      [[ -n "${worker_id:-}" ]] || continue
      if [[ -f "$run_dir/results/$worker_id.last_message.md" ]]; then
        cp "$run_dir/results/$worker_id.last_message.md" "$persistent_dir/last_messages/$worker_id.md" 2>/dev/null || true
      fi
    done <"$workers"
    {
      printf 'generated_at\t%s\n' "$(timestamp)"
      printf 'run_name\t%s\n' "$run_name"
      printf 'run_stamp\t%s\n' "$run_stamp"
      printf 'overall\t%s\n' "$overall"
      printf 'workers\t%s\n' "$worker_count"
      printf 'run_dir\t%s\n' "$run_dir"
      printf 'handoff_summary\t%s\n' "$persistent_dir/worker_handoff_summary.md"
    } >"$persistent_dir/metadata.tsv"
  fi
fi

if [[ -n "$persistent_root" && -d "$persistent_root" ]]; then
  index_tmp="$persistent_root/INDEX.md.tmp.$$"
  {
    printf '# Ralph Worker Run Index\n\n'
    printf 'Cumulative worker handoff history for Ralph tmux-visible subagent runs.\n\n'
    printf '| Generated | Run | Outcome | Workers | Summary |\n'
    printf '| --- | --- | --- | --- | --- |\n'
    for metadata_file in "$persistent_root"/*/metadata.tsv; do
      [[ -f "$metadata_file" ]] || continue
      generated="$(awk -F '\t' '$1 == "generated_at" { print $2; exit }' "$metadata_file")"
      metadata_run_name="$(awk -F '\t' '$1 == "run_name" { print $2; exit }' "$metadata_file")"
      metadata_overall="$(awk -F '\t' '$1 == "overall" { print $2; exit }' "$metadata_file")"
      metadata_workers="$(awk -F '\t' '$1 == "workers" { print $2; exit }' "$metadata_file")"
      metadata_summary="$(awk -F '\t' '$1 == "handoff_summary" { print $2; exit }' "$metadata_file")"
      printf '| %s | `%s` | `%s` | %s | `%s` |\n' \
        "$(clean_cell "$generated")" \
        "$(clean_cell "$metadata_run_name")" \
        "$(clean_cell "$metadata_overall")" \
        "$(clean_cell "$metadata_workers")" \
        "$(clean_cell "$metadata_summary")"
    done
  } >"$index_tmp" && mv "$index_tmp" "$persistent_root/INDEX.md"
fi

printf '%s\n' "$summary"
EOF

cat >"$run_dir/watch_status.sh" <<'EOF'
#!/usr/bin/env bash
set -u

run_dir="$RALPH_RUN_DIR"
workers="$run_dir/workers.tsv"

while true; do
  clear 2>/dev/null || true
  echo "Ralph Worker Monitor"
  echo "Run dir: $run_dir"
  echo
  all_done=1
  while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
    [[ -n "${worker_id:-}" ]] || continue
    if [[ -f "$run_dir/status/$worker_id.status" ]]; then
      status="$(cat "$run_dir/status/$worker_id.status")"
      if [[ -f "$run_dir/status/$worker_id.timed_out" || "$status" == "124" ]]; then
        printf '%-16s timeout status=%s scope=%s\n' "$worker_id" "$status" "$write_scope"
      elif [[ "$status" == "0" ]]; then
        printf '%-16s done    status=%s scope=%s\n' "$worker_id" "$status" "$write_scope"
      else
        printf '%-16s failed  status=%s scope=%s\n' "$worker_id" "$status" "$write_scope"
      fi
    else
      all_done=0
      printf '%-16s running scope=%s\n' "$worker_id" "$write_scope"
    fi
  done <"$workers"
  echo
  echo "Results:"
  ls -1 "$run_dir/results" 2>/dev/null || true
  [[ "$all_done" -eq 1 ]] && break
  sleep 2
done

summary_path="$(RALPH_RUN_DIR="$run_dir" "$run_dir/write_run_summary.sh")"
echo
echo "[ralph-workers] Run summary: $summary_path"
EOF

chmod +x "$run_dir/run_worker.sh" "$run_dir/write_run_summary.sh" "$run_dir/watch_status.sh"

launch_worker_pane() {
  local target_session="$1"
  local first="$2"
  local worker_id="$3"
  local title="$4"
  local prompt_file="$5"
  local write_scope="$6"
  local env_prefix
  local cmd

  env_prefix="RALPH_RUN_DIR=$(shell_quote "$run_dir") RALPH_WORKER_ID=$(shell_quote "$worker_id") RALPH_PROMPT_FILE=$(shell_quote "$prompt_file") RALPH_WORKDIR=$(shell_quote "$workdir") RALPH_RESULT_FILE=$(shell_quote "$run_dir/results/$worker_id.out") RALPH_LAST_MESSAGE_FILE=$(shell_quote "$run_dir/results/$worker_id.last_message.md") RALPH_STATUS_FILE=$(shell_quote "$run_dir/status/$worker_id.status") RALPH_STARTED_AT_FILE=$(shell_quote "$run_dir/status/$worker_id.started_at") RALPH_STARTED_EPOCH_FILE=$(shell_quote "$run_dir/status/$worker_id.started_at_epoch") RALPH_FINISHED_AT_FILE=$(shell_quote "$run_dir/status/$worker_id.finished_at") RALPH_FINISHED_EPOCH_FILE=$(shell_quote "$run_dir/status/$worker_id.finished_at_epoch") RALPH_TIMED_OUT_FILE=$(shell_quote "$run_dir/status/$worker_id.timed_out") RALPH_TIMEOUT_SECONDS=$(shell_quote "$worker_timeout_seconds") RALPH_WORKER_SANDBOX=$(shell_quote "${RALPH_WORKER_SANDBOX:-workspace-write}") RALPH_WORKER_MODEL=$(shell_quote "${RALPH_WORKER_MODEL:-}") RALPH_WORKER_TEST_COMMAND=$(shell_quote "${RALPH_WORKER_TEST_COMMAND:-}")"
  cmd="$env_prefix bash $(shell_quote "$run_dir/run_worker.sh"); printf '\n[ralph worker $worker_id done]\n'; exec bash -l"

  if [[ "$first" -eq 1 ]]; then
    tmux_run new-session -d -s "$target_session" -n workers "$cmd"
  else
    tmux_run split-window -t "$target_session:workers" "$cmd"
  fi
  tmux_run select-pane -T "$title" >/dev/null 2>&1 || true
  printf '%s\t%s\t%s\t%s\n' "$worker_id" "$title" "$prompt_file" "$write_scope"
}

first=1
while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
  [[ -n "${worker_id:-}" ]] || continue
  launch_worker_pane "$session_name" "$first" "$worker_id" "$title" "$prompt_file" "$write_scope" >/dev/null
  first=0
done <"$normalized_workers"

tmux_run select-layout -t "$session_name:workers" tiled >/dev/null
tmux_run new-window -t "$session_name" -n monitor "RALPH_RUN_DIR=$(shell_quote "$run_dir") RALPH_PERSISTENT_HANDOFF_ROOT=$(shell_quote "$handoff_base") RALPH_PERSISTENT_HANDOFF_DIR=$(shell_quote "$handoff_run_dir") RALPH_RUN_NAME=$(shell_quote "$safe_run_name") RALPH_RUN_STAMP=$(shell_quote "$run_stamp") RALPH_WORKER_COUNT=$(shell_quote "$worker_count") bash $(shell_quote "$run_dir/watch_status.sh"); printf '\n[ralph monitor done]\n'; exec bash -l" >/dev/null
tmux_run select-window -t "$session_name:workers" >/dev/null

attach_command() {
  if [[ -n "${RALPH_WORKER_TMUX_SOCKET:-}" ]]; then
    printf 'tmux -L %s attach -t %s' "$(shell_quote "$RALPH_WORKER_TMUX_SOCKET")" "$(shell_quote "$session_name")"
  else
    printf 'tmux attach -t %s' "$(shell_quote "$session_name")"
  fi
}

open_attach_window() {
  local cmd
  local terminal_app
  cmd="$(attach_command)"
  terminal_app="${RALPH_WORKER_TERMINAL_APP:-auto}"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ "$terminal_app" == "auto" || "$terminal_app" == "ghostty" ]]; then
      local ghostty_app=""
      if [[ -d "/Applications/Ghostty.app" ]]; then
        ghostty_app="/Applications/Ghostty.app"
      elif [[ -d "$HOME/Applications/Ghostty.app" ]]; then
        ghostty_app="$HOME/Applications/Ghostty.app"
      elif open -Ra Ghostty >/dev/null 2>&1; then
        ghostty_app="Ghostty"
      fi

      if [[ -n "$ghostty_app" ]]; then
        if open -na "$ghostty_app" --args -e /bin/zsh -lc "$cmd" >/dev/null 2>&1; then
          echo "TERMINAL_APP=ghostty"
          return 0
        fi
        echo "WARN: failed to open Ghostty; falling back to Terminal." >&2
      elif [[ "$terminal_app" == "ghostty" ]]; then
        echo "WARN: Ghostty is not installed; falling back to Terminal." >&2
      fi
    fi

    if [[ "$terminal_app" == "auto" || "$terminal_app" == "terminal" || "$terminal_app" == "ghostty" ]]; then
      if command -v osascript >/dev/null 2>&1; then
        osascript >/dev/null <<EOF
tell application "Terminal"
  activate
  do script "$cmd"
end tell
EOF
        echo "TERMINAL_APP=terminal"
        return 0
      fi
    fi
  fi

  echo "Open a terminal and run: $cmd"
}

if [[ "$open_terminal" -eq 1 && "${CI:-}" != "true" && "${CI:-}" != "1" ]]; then
  open_attach_window
elif [[ "$open_terminal" -eq 1 ]]; then
  echo "TERMINAL_APP=skipped_ci"
fi

echo "TMUX_SESSION=$session_name"
echo "RUN_DIR=$run_dir"
echo "TMUX_WORKERS_WINDOW=workers"
echo "WORKER_PANE_COUNT=$worker_count"
if [[ -f "$run_dir/goal.md" ]]; then
  echo "GOAL_FILE=$run_dir/goal.md"
fi
echo "ATTACH_COMMAND=$(attach_command)"
echo "WORKERS=$worker_count"
echo "RUN_SUMMARY=$run_dir/run_summary.md"
echo "WORKER_HANDOFF_SUMMARY=$run_dir/worker_handoff_summary.md"
if [[ "$persist_handoff" -eq 1 ]]; then
  echo "PERSISTENT_HANDOFF_DIR=$handoff_run_dir"
  echo "PERSISTENT_HANDOFF_SUMMARY=$handoff_run_dir/worker_handoff_summary.md"
  echo "PERSISTENT_HANDOFF_INDEX=$handoff_base/INDEX.md"
fi

if [[ "$wait_for_results" -eq 1 ]]; then
  deadline=$((SECONDS + wait_timeout_seconds))
  while true; do
    all_done=1
    while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
      [[ -n "${worker_id:-}" ]] || continue
      if [[ ! -f "$run_dir/status/$worker_id.status" ]]; then
        all_done=0
      fi
    done <"$normalized_workers"
    [[ "$all_done" -eq 1 ]] && break
    if ((SECONDS >= deadline)); then
      echo "TIMEOUT: worker status files still missing after ${wait_timeout_seconds}s."
      RALPH_RUN_DIR="$run_dir" RALPH_PERSISTENT_HANDOFF_ROOT="$handoff_base" RALPH_PERSISTENT_HANDOFF_DIR="$handoff_run_dir" RALPH_RUN_NAME="$safe_run_name" RALPH_RUN_STAMP="$run_stamp" RALPH_WORKER_COUNT="$worker_count" "$run_dir/write_run_summary.sh" >/dev/null
      echo "RUN_SUMMARY=$run_dir/run_summary.md"
      echo "WORKER_HANDOFF_SUMMARY=$run_dir/worker_handoff_summary.md"
      if [[ "$persist_handoff" -eq 1 ]]; then
        echo "PERSISTENT_HANDOFF_SUMMARY=$handoff_run_dir/worker_handoff_summary.md"
      fi
      exit 124
    fi
    sleep 1
  done

  summary_path="$(RALPH_RUN_DIR="$run_dir" RALPH_PERSISTENT_HANDOFF_ROOT="$handoff_base" RALPH_PERSISTENT_HANDOFF_DIR="$handoff_run_dir" RALPH_RUN_NAME="$safe_run_name" RALPH_RUN_STAMP="$run_stamp" RALPH_WORKER_COUNT="$worker_count" "$run_dir/write_run_summary.sh")"
  echo "DONE: all worker status files are present."
  while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope; do
    [[ -n "${worker_id:-}" ]] || continue
    printf '  %s=%s\n' "$worker_id" "$(cat "$run_dir/status/$worker_id.status")"
  done <"$normalized_workers"
  echo "RUN_SUMMARY=$summary_path"
  echo "WORKER_HANDOFF_SUMMARY=$run_dir/worker_handoff_summary.md"
  if [[ "$persist_handoff" -eq 1 ]]; then
    echo "PERSISTENT_HANDOFF_SUMMARY=$handoff_run_dir/worker_handoff_summary.md"
  fi
else
  RALPH_RUN_DIR="$run_dir" RALPH_PERSISTENT_HANDOFF_ROOT="$handoff_base" RALPH_PERSISTENT_HANDOFF_DIR="$handoff_run_dir" RALPH_RUN_NAME="$safe_run_name" RALPH_RUN_STAMP="$run_stamp" RALPH_WORKER_COUNT="$worker_count" "$run_dir/write_run_summary.sh" >/dev/null
fi
