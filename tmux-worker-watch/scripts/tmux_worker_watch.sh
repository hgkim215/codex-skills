#!/usr/bin/env bash
set -u

pane_lines=80
session_name=""
status_dir=""
watch_all=0
json=0

usage() {
  cat <<'USAGE'
Usage:
  tmux_worker_watch.sh [--all] [--session NAME] [--pane-lines N]
                       [--status-dir DIR] [--json] [--help]

Read-only watcher for existing tmux worker panes and structured run status.

Options:
  --all             Inspect all tmux sessions.
  --session NAME    Inspect one tmux session.
  --pane-lines N    Capture the last N lines from each pane. Default: 80.
  --status-dir DIR  Inspect a run directory with run_summary.md, optional goal.md, status/, results/.
  --json            Emit a JSON object containing the text report.
  --help            Show this help.

Environment:
  TMUX_WORKER_WATCH_SOCKET  Optional tmux socket name for isolated tests.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

redact() {
  perl -pe 's/((?:token|secret|password|api[_ -]?key|access[_ -]?key|auth)[A-Za-z0-9_ -]*[=:][ \t]*)[^ \t\r\n]+/${1}[REDACTED]/ig'
}

json_escape() {
  local value
  value="$(cat)"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

tmux_run() {
  if [ -n "${TMUX_WORKER_WATCH_SOCKET:-}" ]; then
    tmux -L "$TMUX_WORKER_WATCH_SOCKET" "$@"
  else
    tmux "$@"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      watch_all=1
      shift
      ;;
    --session)
      [ "$#" -ge 2 ] || fail "--session requires a value"
      session_name="$2"
      shift 2
      ;;
    --pane-lines)
      [ "$#" -ge 2 ] || fail "--pane-lines requires a value"
      is_positive_int "$2" || fail "--pane-lines must be a positive integer"
      pane_lines="$2"
      shift 2
      ;;
    --status-dir)
      [ "$#" -ge 2 ] || fail "--status-dir requires a value"
      status_dir="$2"
      shift 2
      ;;
    --json)
      json=1
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

if [ -z "$session_name" ] && [ "$watch_all" -eq 0 ] && [ -z "$status_dir" ]; then
  watch_all=1
fi

result_state() {
  local file="$1"
  if [ ! -e "$file" ]; then
    printf 'missing'
  elif [ ! -s "$file" ]; then
    printf 'empty'
  else
    printf 'nonempty:%sB' "$(wc -c <"$file" | tr -d '[:space:]')"
  fi
}

file_value() {
  local file="$1"
  local fallback="$2"
  if [ -f "$file" ]; then
    head -n 1 "$file" | tr -d '\r' | redact
  else
    printf '%s' "$fallback"
  fi
}

duration_value() {
  local started_file="$1"
  local finished_file="$2"
  local start_epoch=""
  local finish_epoch=""
  if [ -f "$started_file" ] && [ -f "$finished_file" ]; then
    start_epoch="$(head -n 1 "$started_file" | tr -d '[:space:]')"
    finish_epoch="$(head -n 1 "$finished_file" | tr -d '[:space:]')"
    case "$start_epoch" in
      ''|*[!0-9]*) printf 'unknown'; return ;;
    esac
    case "$finish_epoch" in
      ''|*[!0-9]*) printf 'unknown'; return ;;
    esac
    if [ "$finish_epoch" -ge "$start_epoch" ] 2>/dev/null; then
      printf '%s' "$((finish_epoch - start_epoch))"
      return
    fi
  fi
  printf 'unknown'
}

report_status_dir() {
  local dir="$1"
  local status_root="$dir/status"
  local results_root="$dir/results"
  local summary="$dir/run_summary.md"
  local handoff_summary="$dir/worker_handoff_summary.md"
  local goal_file="$dir/goal.md"
  local workers_file="$dir/workers.tsv"
  local agents_list=""
  local cross_verify_like=0
  local ralph_worker_like=0
  local status_file
  local result_file
  local agent
  local expected

  printf '## Status Directory\n'
  printf 'path: %s\n' "$dir"

  if [ ! -d "$dir" ]; then
    printf 'state: missing\n\n'
    return
  fi

  if [ -f "$summary" ]; then
    printf 'run_summary: present\n'
    printf 'run_summary_excerpt:\n'
    sed -n '1,40p' "$summary" | redact | sed 's/^/  /'
  else
    printf 'run_summary: missing\n'
  fi

  if [ -f "$handoff_summary" ]; then
    printf 'worker_handoff_summary: present\n'
    printf 'worker_handoff_summary_excerpt:\n'
    sed -n '1,80p' "$handoff_summary" | redact | sed 's/^/  /'
  elif [ -f "$workers_file" ]; then
    printf 'worker_handoff_summary: missing\n'
  fi

  if [ -f "$goal_file" ]; then
    printf 'goal_context: present\n'
    printf 'goal_context_excerpt:\n'
    sed -n '1,40p' "$goal_file" | redact | sed 's/^/  /'
  else
    printf 'goal_context: missing\n'
  fi

  if [ -f "$workers_file" ]; then
    ralph_worker_like=1
    printf 'workers_tsv: present\n'
  fi

  if [ ! -d "$status_root" ]; then
    status_root="$dir"
  fi
  if [ ! -d "$results_root" ]; then
    results_root="$dir"
  fi

  add_agent() {
    local name="$1"
    [ -n "$name" ] || return
    if printf '%s' "$agents_list" | grep -Fxq "$name"; then
      return
    fi
    agents_list="${agents_list}${name}"$'\n'
  }

  if [ -f "$workers_file" ]; then
    while IFS="$(printf '\t')" read -r worker_id title prompt_file write_scope extra; do
      [ -n "$worker_id" ] || continue
      case "$worker_id" in \#*) continue ;; esac
      add_agent "$worker_id"
    done <"$workers_file"
  fi

  for status_file in "$status_root"/*.status; do
    [ -e "$status_file" ] || continue
    add_agent "$(basename "$status_file" .status)"
  done

  for result_file in "$results_root"/*.out; do
    [ -e "$result_file" ] || continue
    add_agent "$(basename "$result_file" .out)"
  done

  for expected in codex gemini copilot; do
    if [ -e "$status_root/$expected.status" ] || [ -e "$results_root/$expected.out" ]; then
      cross_verify_like=1
    fi
  done
  if [ -f "$summary" ] && grep -Eiq 'cross-verify|codex.*gemini.*copilot|gemini.*copilot' "$summary"; then
    cross_verify_like=1
  fi
  if [ -f "$summary" ] && grep -Eiq 'ralph worker|ralph-worker|Ralph Worker|ralph-execute' "$summary"; then
    ralph_worker_like=1
  fi
  if [ "$cross_verify_like" -eq 1 ]; then
    add_agent codex
    add_agent gemini
    add_agent copilot
  fi

  printf 'workers:\n'
  if [ -z "$agents_list" ]; then
    printf '  - none found\n'
    printf '\n'
    return
  fi

  printf '%s' "$agents_list" | while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    status_file="$status_root/$agent.status"
    status="$(file_value "$status_file" "missing")"
    timed_out="no"
    [ -f "$status_root/$agent.timed_out" ] && timed_out="yes"
    payload_state="$(file_value "$status_root/$agent.payload_state" "missing")"
    payload_reason="$(file_value "$status_root/$agent.payload_reason" "missing")"
    retry_count="$(file_value "$status_root/$agent.retry_count" "missing")"
    result="$(result_state "$results_root/$agent.out")"
    last_message="$(result_state "$results_root/$agent.last_message.md")"
    started_at="$(file_value "$status_root/$agent.started_at" "missing")"
    finished_at="$(file_value "$status_root/$agent.finished_at" "missing")"
    duration_seconds="$(duration_value "$status_root/$agent.started_at_epoch" "$status_root/$agent.finished_at_epoch")"

    progress="unknown"
    if [ "$timed_out" = "yes" ] || [ "$status" = "124" ]; then
      progress="timeout"
    elif [ "$payload_state" = "suspect" ]; then
      progress="suspect"
    elif [ "$status" = "0" ]; then
      progress="done"
    elif [ "$status" != "missing" ]; then
      progress="failed"
    fi

    if [ "$ralph_worker_like" -eq 1 ]; then
      printf '  - %s: progress=%s status=%s timed_out=%s duration_seconds=%s started=%s finished=%s result=%s last_message=%s\n' \
        "$agent" "$progress" "$status" "$timed_out" "$duration_seconds" "$started_at" "$finished_at" "$result" "$last_message"
    else
      printf '  - %s: progress=%s status=%s timed_out=%s payload=%s reason=%s retry=%s result=%s\n' \
        "$agent" "$progress" "$status" "$timed_out" "$payload_state" "$payload_reason" "$retry_count" "$result"
    fi
  done
  printf '\n'
}

session_names() {
  if [ -n "$session_name" ]; then
    tmux_run list-sessions -F '#{session_name}' 2>/dev/null | awk -v wanted="$session_name" '$0 == wanted { print }'
  else
    tmux_run list-sessions -F '#{session_name}' 2>/dev/null
  fi
}

session_header() {
  local name="$1"
  tmux_run list-sessions -F '#{session_name}	#{session_attached}	#{session_windows}	#{session_created_string}' 2>/dev/null |
    awk -F '\t' -v wanted="$name" '$1 == wanted { printf "session=%s attached=%s windows=%s created=%s\n", $1, $2, $3, $4 }'
}

report_tmux() {
  printf '## Tmux\n'

  if ! command -v tmux >/dev/null 2>&1; then
    printf 'state: tmux-not-found\n\n'
    return
  fi

  local names
  names="$(session_names)"
  if [ -z "$names" ]; then
    if [ -n "$session_name" ]; then
      printf 'state: session-not-found\n'
      printf 'session: %s\n\n' "$session_name"
    else
      printf 'state: no-sessions\n\n'
    fi
    return
  fi

  printf '%s\n' "$names" | while IFS= read -r sess; do
    [ -n "$sess" ] || continue
    printf '%s\n' "$(session_header "$sess")"
    tmux_run list-windows -t "$sess" -F '#{window_index}	#{window_name}	#{window_active}	#{window_panes}' 2>/dev/null |
      while IFS="$(printf '\t')" read -r window_index window_title window_active window_panes; do
        printf '  window=%s name=%s active=%s panes=%s\n' "$window_index" "$window_title" "$window_active" "$window_panes"
        tmux_run list-panes -t "$sess:$window_index" -F '#{pane_index}	#{pane_active}	#{pane_dead}	#{pane_current_command}	#{pane_current_path}	#{pane_pid}' 2>/dev/null |
          while IFS="$(printf '\t')" read -r pane_index pane_active pane_dead pane_command pane_path pane_pid; do
            target="$sess:$window_index.$pane_index"
            printf '    pane=%s active=%s dead=%s command=%s pid=%s path=%s\n' \
              "$target" "$pane_active" "$pane_dead" "$pane_command" "$pane_pid" "$pane_path"
            printf '    tail:\n'
            tmux_run capture-pane -p -t "$target" -S "-$pane_lines" 2>/dev/null | redact | sed 's/^/      /'
          done
      done
    printf '\n'
  done
}

generate_report() {
  printf '# tmux-worker-watch report\n\n'
  if [ -n "$status_dir" ]; then
    report_status_dir "$status_dir"
  fi
  if [ "$watch_all" -eq 1 ] || [ -n "$session_name" ]; then
    report_tmux
  fi
}

if [ "$json" -eq 1 ]; then
  report="$(generate_report)"
  printf '{"format":"tmux-worker-watch-v1","report":"%s"}\n' "$(printf '%s' "$report" | json_escape)"
else
  generate_report
fi
