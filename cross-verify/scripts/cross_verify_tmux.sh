#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  cross_verify_tmux.sh [--workdir DIR] [--prompt-file FILE]
                       [--include-file FILE ...] [--session-name NAME]
                       [--no-open-terminal] [--no-wait]
                       [PROMPT...]

Runs Codex, Gemini, and Copilot reviewer agents in a tmux session and writes
their outputs to a temporary run directory.

Environment:
  CROSS_VERIFY_REVIEWER_TIMEOUT_SECONDS  Default: CROSS_VERIFY_TIMEOUT_SECONDS or 900
  CROSS_VERIFY_REVIEWER_MAX_RETRIES      Default: 1 for suspect zero-status output
  CROSS_VERIFY_WAIT_TIMEOUT_SECONDS      Default: reviewer timeout + 60
  CROSS_VERIFY_INCLUDE_MAX_BYTES         Default: 50000 per --include-file
  CROSS_VERIFY_MAX_DIFF_BYTES            Default: 120000
  CROSS_VERIFY_TERMINAL_APP              auto, ghostty, or terminal. Default: auto
  CROSS_VERIFY_GEMINI_MODEL              Default: gemini-2.5-pro
  CROSS_VERIFY_CODEX_MODEL               Optional model passed to codex exec
  CROSS_VERIFY_CODEX_SANDBOX             Default: workspace-write
  CROSS_VERIFY_COPILOT_MODEL             Optional first Copilot model candidate
  CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES  Default: 60000, hard-capped at 80000
  CROSS_VERIFY_FORWARD_ENV_VARS          Space-separated env names forwarded to tmux panes
EOF
}

workdir="$PWD"
prompt_file=""
session_name=""
open_terminal=1
wait_for_results=1
include_files=()
args=()

while (($#)); do
  case "$1" in
    --workdir)
      workdir="${2:-}"
      shift 2
      ;;
    --prompt-file)
      prompt_file="${2:-}"
      shift 2
      ;;
    --include-file)
      include_files+=("${2:-}")
      shift 2
      ;;
    --session-name)
      session_name="${2:-}"
      shift 2
      ;;
    --no-open-terminal)
      open_terminal=0
      shift
      ;;
    --no-wait)
      wait_for_results=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      args+=("$@")
      break
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ ! -d "$workdir" ]]; then
  echo "ERROR: workdir does not exist: $workdir" >&2
  exit 2
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "ERROR: tmux is not installed or not on PATH." >&2
  exit 2
fi

reviewer_timeout_seconds="${CROSS_VERIFY_REVIEWER_TIMEOUT_SECONDS:-${CROSS_VERIFY_TIMEOUT_SECONDS:-900}}"
if ! [[ "$reviewer_timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$reviewer_timeout_seconds" -eq 0 ]]; then
  echo "ERROR: CROSS_VERIFY_REVIEWER_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

wait_timeout_seconds="${CROSS_VERIFY_WAIT_TIMEOUT_SECONDS:-}"
if [[ -z "$wait_timeout_seconds" ]]; then
  wait_timeout_seconds=$((reviewer_timeout_seconds + 60))
fi
if ! [[ "$wait_timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$wait_timeout_seconds" -eq 0 ]]; then
  echo "ERROR: CROSS_VERIFY_WAIT_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

include_max_bytes="${CROSS_VERIFY_INCLUDE_MAX_BYTES:-50000}"
if ! [[ "$include_max_bytes" =~ ^[0-9]+$ ]] || [[ "$include_max_bytes" -eq 0 ]]; then
  echo "ERROR: CROSS_VERIFY_INCLUDE_MAX_BYTES must be a positive integer." >&2
  exit 2
fi

reviewer_max_retries="${CROSS_VERIFY_REVIEWER_MAX_RETRIES:-1}"
if ! [[ "$reviewer_max_retries" =~ ^[0-9]+$ ]]; then
  echo "ERROR: CROSS_VERIFY_REVIEWER_MAX_RETRIES must be a non-negative integer." >&2
  exit 2
fi

timeout_cmd="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"

timestamp="$(date +%Y%m%d-%H%M%S)"
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-cross-verify-${timestamp}.XXXXXX")"
mkdir -p "$run_dir/prompts" "$run_dir/results" "$run_dir/status"
user_prompt="$run_dir/user_prompt.md"

if [[ -n "$prompt_file" ]]; then
  if [[ ! -f "$prompt_file" ]]; then
    echo "ERROR: prompt file does not exist: $prompt_file" >&2
    exit 2
  fi
  cp "$prompt_file" "$user_prompt"
elif ((${#args[@]})); then
  printf '%s\n' "${args[@]}" >"$user_prompt"
elif [[ ! -t 0 ]]; then
  tee "$user_prompt" >/dev/null
else
  echo "ERROR: provide --prompt-file, stdin, or prompt arguments." >&2
  usage >&2
  exit 2
fi

if [[ ! -s "$user_prompt" ]]; then
  echo "ERROR: prompt is empty." >&2
  exit 2
fi

if [[ -z "$session_name" ]]; then
  session_name="cross-verify-$(basename "$run_dir" | sed 's/^codex-cross-verify-//')"
fi
session_name="${session_name//[^A-Za-z0-9_-]/-}"

resolve_include_path() {
  local raw="$1"
  if [[ "$raw" = /* ]]; then
    printf '%s' "$raw"
  elif [[ -e "$workdir/$raw" ]]; then
    printf '%s/%s' "$workdir" "$raw"
  else
    printf '%s' "$raw"
  fi
}

append_include_file() {
  local raw="$1"
  local path
  path="$(resolve_include_path "$raw")"

  printf '## `%s`\n\n' "$raw"
  printf -- '- Resolved path: `%s`\n' "$path"

  if [[ -z "$raw" ]]; then
    printf -- '- Status: skipped, empty path\n\n'
    return
  fi
  if [[ ! -e "$path" ]]; then
    printf -- '- Status: skipped, file does not exist\n\n'
    return
  fi
  if [[ ! -f "$path" ]]; then
    printf -- '- Status: skipped, not a regular file\n\n'
    return
  fi
  if [[ ! -r "$path" ]]; then
    printf -- '- Status: skipped, file is not readable\n\n'
    return
  fi
  if [[ -s "$path" ]] && ! LC_ALL=C grep -Iq . "$path"; then
    printf -- '- Status: skipped, binary-looking content\n\n'
    return
  fi

  local bytes
  bytes="$(wc -c <"$path" | tr -d ' ')"
  printf -- '- Bytes: `%s`\n' "$bytes"
  if ((bytes > include_max_bytes)); then
    printf -- '- Status: included first `%s` bytes only\n\n' "$include_max_bytes"
  else
    printf -- '- Status: included full file\n\n'
  fi

  printf '````text\n'
  if ((bytes > include_max_bytes)); then
    head -c "$include_max_bytes" "$path" || true
    printf '\n[TRUNCATED: file exceeded %s bytes]\n' "$include_max_bytes"
  else
    cat "$path"
  fi
  printf '\n````\n\n'
}

context_file="$run_dir/context.md"
included_context_file="$run_dir/included_files.md"
max_diff_bytes="${CROSS_VERIFY_MAX_DIFF_BYTES:-120000}"

{
  printf '# Cross-Verify Context\n\n'
  printf -- '- Workdir: `%s`\n' "$workdir"
  printf -- '- Timestamp: `%s`\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf -- '- Reviewer timeout seconds: `%s`\n' "$reviewer_timeout_seconds"
  printf -- '- Timeout mode: shell watchdog per reviewer'
  if [[ -n "$timeout_cmd" ]]; then
    printf ' (external `%s` also available)\n\n' "$timeout_cmd"
  else
    printf '\n\n'
  fi

  if git -C "$workdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_root="$(git -C "$workdir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$workdir")"
    printf '## Git\n\n'
    printf -- '- Git root: `%s`\n\n' "$git_root"
    printf '### git status --short\n\n```text\n'
    git -C "$workdir" status --short 2>&1 || true
    printf '```\n\n'
    printf '### git diff --stat\n\n```text\n'
    git -C "$workdir" diff --stat 2>&1 || true
    printf '```\n\n'
    printf '### git diff (bounded to %s bytes)\n\n```diff\n' "$max_diff_bytes"
    git -C "$workdir" diff --no-ext-diff 2>&1 | head -c "$max_diff_bytes" || true
    printf '\n```\n'
  else
    printf '## Git\n\nNot inside a git repository.\n'
  fi
} >"$context_file"

{
  printf '# Included Files\n\n'
  if ((${#include_files[@]} == 0)); then
    printf 'No explicit `--include-file` entries were provided.\n'
  else
    for include_file in "${include_files[@]}"; do
      append_include_file "$include_file"
    done
  fi
} >"$included_context_file"

write_reviewer_prompt() {
  local reviewer="$1"
  local output="$2"
  {
    printf '# Cross-Verification Reviewer Prompt\n\n'
    printf 'You are the %s reviewer in a multi-agent cross-verification workflow.\n\n' "$reviewer"
    if [[ "$reviewer" == "Gemini" ]]; then
      cat <<'EOF'
Rules:
- Be independent and critical. Do not just agree with the prompt.
- Do not modify source files or tracked project files.
- Do not use shell commands, file tools, or filesystem inspection. The Gemini CLI tool surface may not support them reliably in this workflow.
- Base your review on the user request, git context, and included file contents below.
- If a needed file is not included or context is insufficient, state that limitation instead of trying to read it.
- Do not judge whether other reviewers completed. The main Codex determines cross-verify run state from status/* and run_summary.md.
- Prioritize concrete evidence, reproducible checks, edge cases, and failure modes.
- Return concise Markdown in the user's language when obvious from the prompt.

EOF
    else
      cat <<'EOF'
Rules:
- Be independent and critical. Do not just agree with the prompt.
- Do not modify source files or tracked project files.
- You may inspect files and run tests/builds/checks if useful. Build artifacts or caches are acceptable.
- Prefer the included file contents below before reading files yourself.
- Prioritize concrete evidence, reproducible checks, edge cases, and failure modes.
- Do not inspect tmux sessions, status files, or other reviewer outputs to decide whether the cross-verify run completed. The main Codex determines run state from status/* and run_summary.md.
- If context is insufficient, state the missing evidence briefly and return instead of broad filesystem or session exploration.
- Return concise Markdown in the user's language when obvious from the prompt.

EOF
    fi
    cat <<'EOF'
Required output:
1. Verdict
2. Key findings
3. Risks or missed edge cases
4. Evidence or checks used
5. Confidence

EOF
    printf '## User Request\n\n'
    cat "$user_prompt"
    printf '\n\n'
    cat "$context_file"
    printf '\n\n'
    cat "$included_context_file"
  } >"$output"
}

write_reviewer_prompt "Codex" "$run_dir/prompts/codex.md"
write_reviewer_prompt "Gemini" "$run_dir/prompts/gemini.md"
write_reviewer_prompt "Copilot" "$run_dir/prompts/copilot.md"

shell_quote() {
  printf "%q" "$1"
}

codex_cmd="$(command -v codex 2>/dev/null || printf 'codex')"
gemini_cmd="$(command -v gemini 2>/dev/null || printf 'gemini')"
copilot_cmd="$(command -v copilot 2>/dev/null || printf 'copilot')"

forward_env_file="$run_dir/forwarded_env.sh"
: >"$forward_env_file"
chmod 600 "$forward_env_file"
default_forward_env_vars="HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy"
if [[ "${CROSS_VERIFY_FORWARD_ENV_VARS+x}" ]]; then
  forward_env_vars="$CROSS_VERIFY_FORWARD_ENV_VARS"
else
  forward_env_vars="$default_forward_env_vars"
fi
for env_name in $forward_env_vars; do
  if [[ "$env_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [[ -n "${!env_name+x}" ]]; then
    printf 'export %s=%q\n' "$env_name" "${!env_name}" >>"$forward_env_file"
  fi
done

cat >"$run_dir/run_codex.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

agent="codex"
out="$CV_RUN_DIR/results/${agent}.out"
status_file="$CV_RUN_DIR/status/${agent}.status"
prompt="$CV_RUN_DIR/prompts/${agent}.md"
status_written=0

if [[ -n "${CV_ENV_FILE:-}" && -f "$CV_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CV_ENV_FILE"
fi

record_status() {
  local status="$1"
  if [[ "$status_written" -eq 0 ]]; then
    printf '%s\n' "$status" >"$status_file"
    status_written=1
  fi
}

on_exit() {
  local status=$?
  if [[ "$status_written" -eq 0 ]]; then
    record_status "$status"
  fi
}

trap on_exit EXIT
trap 'record_status 143; exit 143' INT TERM

reviewer_attempt="${CV_REVIEWER_ATTEMPT:-0}"
reviewer_max_retries="${CV_REVIEWER_MAX_RETRIES:-1}"
if [[ "$reviewer_attempt" -eq 0 ]]; then
  printf 'no\n' >"$CV_RUN_DIR/status/${agent}.retry_used"
  printf '0\n' >"$CV_RUN_DIR/status/${agent}.retry_count"
fi

payload_reason_for_file() {
  local file="$1"
  local match
  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return
  fi
  if [[ ! -s "$file" ]]; then
    printf 'empty'
    return
  fi
  if ! LC_ALL=C grep -q '[^[:space:]]' "$file" 2>/dev/null; then
    printf 'blank'
    return
  fi
  match="$(sed -n '1,80p' "$file" 2>/dev/null | grep -Einm1 '^[[:space:]]*((Error stating path|UnhandledPromiseRejection|Traceback \(most recent call last\):|panic:|Killed: 9)([[:space:]:-]|$)|([[:alnum:]_./-]+:[[:space:]]*)?Segmentation fault([[:space:]]*\(|:|$))' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:runtime_line_%s' "${match%%:*}"
    return
  fi
  match="$(sed -n '1,80p' "$file" 2>/dev/null | grep -Einm1 '(^|[[:space:]:])(ENAMETOOLONG:|E2BIG:|argument list too long|name too long, stat)' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:argument_line_%s' "${match%%:*}"
    return
  fi
  match="$(sed -n '1,40p' "$file" 2>/dev/null | grep -Einm1 '^[[:space:]]*((error|fatal)[[:space:]:-]+.*(authentication failed|unauthorized|permission denied|login required|not logged in|rate limit|rate limited|quota exceeded|insufficient quota|network error|request timeout|request timed out|timed out|timeout error|api key|invalid api key|no api key|http 40[13]|http 429|codex_[A-Z_]+|gemini_[A-Z_]+|copilot_[A-Z_]+)|(authentication failed|unauthorized|permission denied|login required|not logged in|rate limited|rate limit exceeded|quota exceeded|insufficient quota|network error|request timeout|request timed out|timeout error|invalid api key|no api key|http 40[13]|http 429|codex_[A-Z_]+|gemini_[A-Z_]+|copilot_[A-Z_]+)([[:space:]:-]|$))' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:cli_line_%s' "${match%%:*}"
    return
  fi
  printf 'clean'
}

record_payload_state_from_file() {
  local file="$1"
  local reason
  local state
  local bytes
  reason="$(payload_reason_for_file "$file")"
  case "$reason" in
    clean)
      state="clean"
      reason="none"
      ;;
    missing)
      state="missing"
      ;;
    empty)
      state="empty"
      ;;
    blank)
      state="empty"
      ;;
    *)
      state="suspect"
      ;;
  esac
  if [[ -f "$file" ]]; then
    bytes="$(wc -c <"$file" | tr -d ' ')"
  else
    bytes="missing"
  fi
  printf '%s\n' "$state" >"$CV_RUN_DIR/status/${agent}.payload_state"
  printf '%s\n' "$reason" >"$CV_RUN_DIR/status/${agent}.payload_reason"
  printf '%s\n' "$bytes" >"$CV_RUN_DIR/status/${agent}.response_bytes"
}

maybe_retry_suspect() {
  local status="$1"
  local archive_source="${2:-$out}"
  local payload_state
  local payload_reason
  local next_attempt
  payload_state="$(cat "$CV_RUN_DIR/status/${agent}.payload_state" 2>/dev/null || printf 'missing')"
  payload_reason="$(cat "$CV_RUN_DIR/status/${agent}.payload_reason" 2>/dev/null || printf 'missing')"
  if [[ "$status" -eq 0 && "$payload_state" == "suspect" && "$reviewer_attempt" -lt "$reviewer_max_retries" ]]; then
    next_attempt=$((reviewer_attempt + 1))
    cp "$archive_source" "$CV_RUN_DIR/results/${agent}.suspect_attempt_${next_attempt}.out" 2>/dev/null || true
    printf 'yes\n' >"$CV_RUN_DIR/status/${agent}.retry_used"
    printf '%s\n' "$next_attempt" >"$CV_RUN_DIR/status/${agent}.retry_count"
    echo "[cross-verify] ${agent} reviewer output looked suspect (${payload_reason}); retrying ${next_attempt}/${reviewer_max_retries}."
    CV_REVIEWER_ATTEMPT="$next_attempt" exec "$0"
  fi
}

collect_descendants() {
  local pid="$1"
  local child
  while read -r child; do
    [[ -n "$child" ]] || continue
    printf '%s\n' "$child"
    collect_descendants "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
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

run_streamed_to() {
  local target="$1"
  shift
  local timed_out_file="$CV_RUN_DIR/status/${agent}.timed_out"
  rm -f "$timed_out_file"
  : >"$target"

  tail -n +1 -f "$target" &
  local tail_pid=$!

  if [[ -n "${CV_RUN_STREAM_INPUT:-}" ]]; then
    if [[ -n "${CV_RUN_STDERR_TARGET:-}" ]]; then
      "$@" <"$CV_RUN_STREAM_INPUT" >>"$target" 2>>"$CV_RUN_STDERR_TARGET" &
    else
      "$@" <"$CV_RUN_STREAM_INPUT" >>"$target" 2>&1 &
    fi
  else
    if [[ -n "${CV_RUN_STDERR_TARGET:-}" ]]; then
      "$@" >>"$target" 2>>"$CV_RUN_STDERR_TARGET" &
    else
      "$@" >>"$target" 2>&1 &
    fi
  fi
  local cmd_pid=$!

  (
    elapsed=0
    while ((elapsed < CV_REVIEWER_TIMEOUT_SECONDS)); do
      sleep 1
      elapsed=$((elapsed + 1))
      kill -0 "$cmd_pid" 2>/dev/null || exit 0
    done
    if kill -0 "$cmd_pid" 2>/dev/null; then
      echo "[cross-verify] ${agent} reviewer timed out after ${CV_REVIEWER_TIMEOUT_SECONDS}s" >>"$target"
      : >"$timed_out_file"
      timeout_descendants="$(collect_descendants "$cmd_pid" | tr '\n' ' ')"
      kill_tree "$cmd_pid" TERM
      sleep 1
      for child in $timeout_descendants; do
        kill -KILL "$child" 2>/dev/null || true
      done
      kill -KILL "$cmd_pid" 2>/dev/null || true
    fi
  ) &
  local watchdog_pid=$!

  set +e
  wait "$cmd_pid"
  local status=$?

  if [[ -f "$timed_out_file" ]]; then
    wait "$watchdog_pid" 2>/dev/null || true
  else
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  sleep 0.2
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true

  if [[ -f "$timed_out_file" ]]; then
    return 124
  fi
  return "$status"
}

cd "$CV_WORKDIR"
echo "[cross-verify] Codex reviewer started at $(date '+%Y-%m-%dT%H:%M:%S%z')"
: >"$out"

if ! command -v "$CV_CODEX_CMD" >/dev/null 2>&1; then
  echo "CODEX_NOT_INSTALLED: codex CLI is not installed" | tee "$out"
  record_payload_state_from_file "$out"
  record_status 127
  exit 0
fi

set +e
if [[ -n "${CV_CODEX_MODEL:-}" ]]; then
  CV_RUN_STREAM_INPUT="$prompt" run_streamed_to "$out" "$CV_CODEX_CMD" exec --sandbox "$CV_CODEX_SANDBOX" --ephemeral --skip-git-repo-check -C "$CV_WORKDIR" -m "$CV_CODEX_MODEL" -
else
  CV_RUN_STREAM_INPUT="$prompt" run_streamed_to "$out" "$CV_CODEX_CMD" exec --sandbox "$CV_CODEX_SANDBOX" --ephemeral --skip-git-repo-check -C "$CV_WORKDIR" -
fi
status=$?
set -e

record_payload_state_from_file "$out"
maybe_retry_suspect "$status" "$out"
record_status "$status"
echo "[cross-verify] Codex reviewer exited with status $status at $(date '+%Y-%m-%dT%H:%M:%S%z')"
exit 0
EOF

cat >"$run_dir/run_gemini.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

agent="gemini"
out="$CV_RUN_DIR/results/${agent}.out"
status_file="$CV_RUN_DIR/status/${agent}.status"
prompt="$CV_RUN_DIR/prompts/${agent}.md"
status_written=0

if [[ -n "${CV_ENV_FILE:-}" && -f "$CV_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CV_ENV_FILE"
fi

record_status() {
  local status="$1"
  if [[ "$status_written" -eq 0 ]]; then
    printf '%s\n' "$status" >"$status_file"
    status_written=1
  fi
}

on_exit() {
  local status=$?
  if [[ "$status_written" -eq 0 ]]; then
    record_status "$status"
  fi
}

trap on_exit EXIT
trap 'record_status 143; exit 143' INT TERM

reviewer_attempt="${CV_REVIEWER_ATTEMPT:-0}"
reviewer_max_retries="${CV_REVIEWER_MAX_RETRIES:-1}"
if [[ "$reviewer_attempt" -eq 0 ]]; then
  printf 'no\n' >"$CV_RUN_DIR/status/${agent}.retry_used"
  printf '0\n' >"$CV_RUN_DIR/status/${agent}.retry_count"
fi

payload_reason_for_file() {
  local file="$1"
  local match
  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return
  fi
  if [[ ! -s "$file" ]]; then
    printf 'empty'
    return
  fi
  if ! LC_ALL=C grep -q '[^[:space:]]' "$file" 2>/dev/null; then
    printf 'blank'
    return
  fi
  match="$(sed -n '1,80p' "$file" 2>/dev/null | grep -Einm1 '^[[:space:]]*((Error stating path|UnhandledPromiseRejection|Traceback \(most recent call last\):|panic:|Killed: 9)([[:space:]:-]|$)|([[:alnum:]_./-]+:[[:space:]]*)?Segmentation fault([[:space:]]*\(|:|$))' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:runtime_line_%s' "${match%%:*}"
    return
  fi
  match="$(sed -n '1,80p' "$file" 2>/dev/null | grep -Einm1 '(^|[[:space:]:])(ENAMETOOLONG:|E2BIG:|argument list too long|name too long, stat)' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:argument_line_%s' "${match%%:*}"
    return
  fi
  match="$(sed -n '1,40p' "$file" 2>/dev/null | grep -Einm1 '^[[:space:]]*((error|fatal)[[:space:]:-]+.*(authentication failed|unauthorized|permission denied|login required|not logged in|rate limit|rate limited|quota exceeded|insufficient quota|network error|request timeout|request timed out|timed out|timeout error|api key|invalid api key|no api key|http 40[13]|http 429|codex_[A-Z_]+|gemini_[A-Z_]+|copilot_[A-Z_]+)|(authentication failed|unauthorized|permission denied|login required|not logged in|rate limited|rate limit exceeded|quota exceeded|insufficient quota|network error|request timeout|request timed out|timeout error|invalid api key|no api key|http 40[13]|http 429|codex_[A-Z_]+|gemini_[A-Z_]+|copilot_[A-Z_]+)([[:space:]:-]|$))' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:cli_line_%s' "${match%%:*}"
    return
  fi
  printf 'clean'
}

record_payload_state_from_file() {
  local file="$1"
  local reason
  local state
  local bytes
  reason="$(payload_reason_for_file "$file")"
  case "$reason" in
    clean)
      state="clean"
      reason="none"
      ;;
    missing)
      state="missing"
      ;;
    empty)
      state="empty"
      ;;
    blank)
      state="empty"
      ;;
    *)
      state="suspect"
      ;;
  esac
  if [[ -f "$file" ]]; then
    bytes="$(wc -c <"$file" | tr -d ' ')"
  else
    bytes="missing"
  fi
  printf '%s\n' "$state" >"$CV_RUN_DIR/status/${agent}.payload_state"
  printf '%s\n' "$reason" >"$CV_RUN_DIR/status/${agent}.payload_reason"
  printf '%s\n' "$bytes" >"$CV_RUN_DIR/status/${agent}.response_bytes"
}

maybe_retry_suspect() {
  local status="$1"
  local archive_source="${2:-$out}"
  local payload_state
  local payload_reason
  local next_attempt
  payload_state="$(cat "$CV_RUN_DIR/status/${agent}.payload_state" 2>/dev/null || printf 'missing')"
  payload_reason="$(cat "$CV_RUN_DIR/status/${agent}.payload_reason" 2>/dev/null || printf 'missing')"
  if [[ "$status" -eq 0 && "$payload_state" == "suspect" && "$reviewer_attempt" -lt "$reviewer_max_retries" ]]; then
    next_attempt=$((reviewer_attempt + 1))
    cp "$archive_source" "$CV_RUN_DIR/results/${agent}.suspect_attempt_${next_attempt}.out" 2>/dev/null || true
    printf 'yes\n' >"$CV_RUN_DIR/status/${agent}.retry_used"
    printf '%s\n' "$next_attempt" >"$CV_RUN_DIR/status/${agent}.retry_count"
    echo "[cross-verify] ${agent} reviewer output looked suspect (${payload_reason}); retrying ${next_attempt}/${reviewer_max_retries}."
    CV_REVIEWER_ATTEMPT="$next_attempt" exec "$0"
  fi
}

collect_descendants() {
  local pid="$1"
  local child
  while read -r child; do
    [[ -n "$child" ]] || continue
    printf '%s\n' "$child"
    collect_descendants "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
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

run_streamed_to() {
  local target="$1"
  shift
  local timed_out_file="$CV_RUN_DIR/status/${agent}.timed_out"
  rm -f "$timed_out_file"
  : >"$target"

  tail -n +1 -f "$target" &
  local tail_pid=$!

  if [[ -n "${CV_RUN_STREAM_INPUT:-}" ]]; then
    if [[ -n "${CV_RUN_STDERR_TARGET:-}" ]]; then
      "$@" <"$CV_RUN_STREAM_INPUT" >>"$target" 2>>"$CV_RUN_STDERR_TARGET" &
    else
      "$@" <"$CV_RUN_STREAM_INPUT" >>"$target" 2>&1 &
    fi
  else
    if [[ -n "${CV_RUN_STDERR_TARGET:-}" ]]; then
      "$@" >>"$target" 2>>"$CV_RUN_STDERR_TARGET" &
    else
      "$@" >>"$target" 2>&1 &
    fi
  fi
  local cmd_pid=$!

  (
    elapsed=0
    while ((elapsed < CV_REVIEWER_TIMEOUT_SECONDS)); do
      sleep 1
      elapsed=$((elapsed + 1))
      kill -0 "$cmd_pid" 2>/dev/null || exit 0
    done
    if kill -0 "$cmd_pid" 2>/dev/null; then
      echo "[cross-verify] ${agent} reviewer timed out after ${CV_REVIEWER_TIMEOUT_SECONDS}s" >>"$target"
      : >"$timed_out_file"
      timeout_descendants="$(collect_descendants "$cmd_pid" | tr '\n' ' ')"
      kill_tree "$cmd_pid" TERM
      sleep 1
      for child in $timeout_descendants; do
        kill -KILL "$child" 2>/dev/null || true
      done
      kill -KILL "$cmd_pid" 2>/dev/null || true
    fi
  ) &
  local watchdog_pid=$!

  set +e
  wait "$cmd_pid"
  local status=$?

  if [[ -f "$timed_out_file" ]]; then
    wait "$watchdog_pid" 2>/dev/null || true
  else
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  sleep 0.2
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true

  if [[ -f "$timed_out_file" ]]; then
    return 124
  fi
  return "$status"
}

cd "$CV_WORKDIR"
echo "[cross-verify] Gemini reviewer started at $(date '+%Y-%m-%dT%H:%M:%S%z')"
: >"$out"

if ! command -v "$CV_GEMINI_CMD" >/dev/null 2>&1; then
  echo "GEMINI_NOT_INSTALLED: gemini CLI is not installed" | tee "$out"
  record_payload_state_from_file "$out"
  record_status 127
  exit 0
fi

set +e
CV_RUN_STREAM_INPUT="$prompt" run_streamed_to "$out" env GEMINI_CLI_TRUST_WORKSPACE=true "$CV_GEMINI_CMD" -m "$CV_GEMINI_MODEL" -o text -p ""
status=$?
set -e

record_payload_state_from_file "$out"
maybe_retry_suspect "$status" "$out"
record_status "$status"
echo "[cross-verify] Gemini reviewer exited with status $status at $(date '+%Y-%m-%dT%H:%M:%S%z')"
exit 0
EOF

cat >"$run_dir/run_copilot.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

agent="copilot"
out="$CV_RUN_DIR/results/${agent}.out"
status_file="$CV_RUN_DIR/status/${agent}.status"
prompt="$CV_RUN_DIR/prompts/${agent}.md"
status_written=0

if [[ -n "${CV_ENV_FILE:-}" && -f "$CV_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CV_ENV_FILE"
fi

record_status() {
  local status="$1"
  if [[ "$status_written" -eq 0 ]]; then
    printf '%s\n' "$status" >"$status_file"
    status_written=1
  fi
}

on_exit() {
  local status=$?
  if [[ "$status_written" -eq 0 ]]; then
    record_status "$status"
  fi
}

trap on_exit EXIT
trap 'record_status 143; exit 143' INT TERM

reviewer_attempt="${CV_REVIEWER_ATTEMPT:-0}"
reviewer_max_retries="${CV_REVIEWER_MAX_RETRIES:-1}"
if [[ "$reviewer_attempt" -eq 0 ]]; then
  printf 'no\n' >"$CV_RUN_DIR/status/${agent}.retry_used"
  printf '0\n' >"$CV_RUN_DIR/status/${agent}.retry_count"
fi

payload_reason_for_file() {
  local file="$1"
  local match
  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return
  fi
  if [[ ! -s "$file" ]]; then
    printf 'empty'
    return
  fi
  if ! LC_ALL=C grep -q '[^[:space:]]' "$file" 2>/dev/null; then
    printf 'blank'
    return
  fi
  match="$(sed -n '1,80p' "$file" 2>/dev/null | grep -Einm1 '^[[:space:]]*((Error stating path|UnhandledPromiseRejection|Traceback \(most recent call last\):|panic:|Killed: 9)([[:space:]:-]|$)|([[:alnum:]_./-]+:[[:space:]]*)?Segmentation fault([[:space:]]*\(|:|$))' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:runtime_line_%s' "${match%%:*}"
    return
  fi
  match="$(sed -n '1,80p' "$file" 2>/dev/null | grep -Einm1 '(^|[[:space:]:])(ENAMETOOLONG:|E2BIG:|argument list too long|name too long, stat)' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:argument_line_%s' "${match%%:*}"
    return
  fi
  match="$(sed -n '1,40p' "$file" 2>/dev/null | grep -Einm1 '^[[:space:]]*((error|fatal)[[:space:]:-]+.*(authentication failed|unauthorized|permission denied|login required|not logged in|rate limit|rate limited|quota exceeded|insufficient quota|network error|request timeout|request timed out|timed out|timeout error|api key|invalid api key|no api key|http 40[13]|http 429|codex_[A-Z_]+|gemini_[A-Z_]+|copilot_[A-Z_]+)|(authentication failed|unauthorized|permission denied|login required|not logged in|rate limited|rate limit exceeded|quota exceeded|insufficient quota|network error|request timeout|request timed out|timeout error|invalid api key|no api key|http 40[13]|http 429|codex_[A-Z_]+|gemini_[A-Z_]+|copilot_[A-Z_]+)([[:space:]:-]|$))' || true)"
  if [[ -n "$match" ]]; then
    printf 'cli_error_marker:cli_line_%s' "${match%%:*}"
    return
  fi
  printf 'clean'
}

record_payload_state_from_file() {
  local file="$1"
  local reason
  local state
  local bytes
  reason="$(payload_reason_for_file "$file")"
  case "$reason" in
    clean)
      state="clean"
      reason="none"
      ;;
    missing)
      state="missing"
      ;;
    empty)
      state="empty"
      ;;
    blank)
      state="empty"
      ;;
    *)
      state="suspect"
      ;;
  esac
  if [[ -f "$file" ]]; then
    bytes="$(wc -c <"$file" | tr -d ' ')"
  else
    bytes="missing"
  fi
  printf '%s\n' "$state" >"$CV_RUN_DIR/status/${agent}.payload_state"
  printf '%s\n' "$reason" >"$CV_RUN_DIR/status/${agent}.payload_reason"
  printf '%s\n' "$bytes" >"$CV_RUN_DIR/status/${agent}.response_bytes"
}

maybe_retry_suspect() {
  local status="$1"
  local archive_source="${2:-$out}"
  local payload_state
  local payload_reason
  local next_attempt
  payload_state="$(cat "$CV_RUN_DIR/status/${agent}.payload_state" 2>/dev/null || printf 'missing')"
  payload_reason="$(cat "$CV_RUN_DIR/status/${agent}.payload_reason" 2>/dev/null || printf 'missing')"
  if [[ "$status" -eq 0 && "$payload_state" == "suspect" && "$reviewer_attempt" -lt "$reviewer_max_retries" ]]; then
    next_attempt=$((reviewer_attempt + 1))
    cp "$archive_source" "$CV_RUN_DIR/results/${agent}.suspect_attempt_${next_attempt}.out" 2>/dev/null || true
    printf 'yes\n' >"$CV_RUN_DIR/status/${agent}.retry_used"
    printf '%s\n' "$next_attempt" >"$CV_RUN_DIR/status/${agent}.retry_count"
    echo "[cross-verify] ${agent} reviewer output looked suspect (${payload_reason}); retrying ${next_attempt}/${reviewer_max_retries}."
    CV_REVIEWER_ATTEMPT="$next_attempt" exec "$0"
  fi
}

collect_descendants() {
  local pid="$1"
  local child
  while read -r child; do
    [[ -n "$child" ]] || continue
    printf '%s\n' "$child"
    collect_descendants "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
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

run_streamed_to() {
  local target="$1"
  shift
  local timed_out_file="$CV_RUN_DIR/status/${agent}.timed_out"
  rm -f "$timed_out_file"
  : >"$target"

  tail -n +1 -f "$target" &
  local tail_pid=$!

  if [[ -n "${CV_RUN_STREAM_INPUT:-}" ]]; then
    if [[ -n "${CV_RUN_STDERR_TARGET:-}" ]]; then
      "$@" <"$CV_RUN_STREAM_INPUT" >>"$target" 2>>"$CV_RUN_STDERR_TARGET" &
    else
      "$@" <"$CV_RUN_STREAM_INPUT" >>"$target" 2>&1 &
    fi
  else
    if [[ -n "${CV_RUN_STDERR_TARGET:-}" ]]; then
      "$@" >>"$target" 2>>"$CV_RUN_STDERR_TARGET" &
    else
      "$@" >>"$target" 2>&1 &
    fi
  fi
  local cmd_pid=$!

  (
    elapsed=0
    while ((elapsed < CV_REVIEWER_TIMEOUT_SECONDS)); do
      sleep 1
      elapsed=$((elapsed + 1))
      kill -0 "$cmd_pid" 2>/dev/null || exit 0
    done
    if kill -0 "$cmd_pid" 2>/dev/null; then
      echo "[cross-verify] ${agent} reviewer timed out after ${CV_REVIEWER_TIMEOUT_SECONDS}s" >>"$target"
      : >"$timed_out_file"
      timeout_descendants="$(collect_descendants "$cmd_pid" | tr '\n' ' ')"
      kill_tree "$cmd_pid" TERM
      sleep 1
      for child in $timeout_descendants; do
        kill -KILL "$child" 2>/dev/null || true
      done
      kill -KILL "$cmd_pid" 2>/dev/null || true
    fi
  ) &
  local watchdog_pid=$!

  set +e
  wait "$cmd_pid"
  local status=$?

  if [[ -f "$timed_out_file" ]]; then
    wait "$watchdog_pid" 2>/dev/null || true
  else
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  sleep 0.2
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true

  if [[ -f "$timed_out_file" ]]; then
    return 124
  fi
  return "$status"
}

cd "$CV_WORKDIR"
echo "[cross-verify] Copilot reviewer started at $(date '+%Y-%m-%dT%H:%M:%S%z')"
: >"$out"

if ! command -v "$CV_COPILOT_CMD" >/dev/null 2>&1; then
  echo "COPILOT_NOT_INSTALLED: copilot CLI is not installed" | tee "$out"
  record_payload_state_from_file "$out"
  record_status 127
  exit 0
fi

max_prompt_default_bytes=60000
max_prompt_hard_cap_bytes=80000
max_prompt_bytes="${CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES:-$max_prompt_default_bytes}"
if ! [[ "$max_prompt_bytes" =~ ^[0-9]+$ ]] || [[ "$max_prompt_bytes" -eq 0 ]]; then
  echo "WARN: invalid CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES=$max_prompt_bytes; using $max_prompt_default_bytes" | tee -a "$out"
  max_prompt_bytes="$max_prompt_default_bytes"
fi
if [[ "$max_prompt_bytes" -gt "$max_prompt_hard_cap_bytes" ]]; then
  echo "WARN: CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES=$max_prompt_bytes exceeds safe cap $max_prompt_hard_cap_bytes; using $max_prompt_hard_cap_bytes" | tee -a "$out"
  max_prompt_bytes="$max_prompt_hard_cap_bytes"
fi

prompt_original_bytes="$(wc -c <"$prompt" | tr -d ' ')"
prompt_truncated="no"
if [[ "$prompt_original_bytes" -gt "$max_prompt_bytes" ]]; then
  prompt_truncated="yes"
  if command -v iconv >/dev/null 2>&1; then
    prompt_body="$(head -c "$max_prompt_bytes" "$prompt" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true)"
  else
    prompt_body="$(head -c "$max_prompt_bytes" "$prompt")"
  fi
  prompt_body="$prompt_body

[TRUNCATED_FOR_COPILOT: prompt exceeded $max_prompt_bytes bytes]"
else
  prompt_body="$(cat "$prompt")"
fi
printf '%s\n' "$prompt_original_bytes" >"$CV_RUN_DIR/status/copilot.prompt_bytes"
printf '%s\n' "$max_prompt_bytes" >"$CV_RUN_DIR/status/copilot.prompt_limit_bytes"
printf '%s\n' "$prompt_truncated" >"$CV_RUN_DIR/status/copilot.prompt_truncated"
if [[ "$prompt_truncated" == "yes" ]]; then
  echo "COPILOT_PROMPT_TRUNCATED: prompt was $prompt_original_bytes bytes; sent first $max_prompt_bytes bytes to Copilot." | tee -a "$out"
fi
instruction="Review the following cross-verification prompt. Do not modify files. If you inspect or run checks, keep them non-destructive. Return only the requested Markdown review.

$prompt_body"

is_model_unavailable_error() {
  local file="$1"
  grep -Eqi "model_not_supported|unknown[[:space:]_-]+model|invalid[[:space:]_-]+model|unsupported[[:space:]_-]+model|no[[:space:]_-]+such[[:space:]_-]+model|requested[[:space:]_-]+model([^[:space:]]*[[:space:]]+){0,4}does[[:space:]_-]+not[[:space:]_-]+exist|model[[:space:]_-]+(not[[:space:]_-]+found|not[[:space:]_-]+supported)|model([[:space:]_-]+id)?[[:space:]_-]*:?[[:space:]]+[\`\"'][^\`\"']+[\`\"']([^[:space:]]*[[:space:]]+){0,6}(is[[:space:]_-]+)?(not[[:space:]_-]+currently[[:space:]_-]+available|not[[:space:]_-]+available|unavailable|not[[:space:]_-]+supported|not[[:space:]_-]+found|does[[:space:]_-]+not[[:space:]_-]+exist)|model[[:space:]_-]+[^[:space:]]*[-0-9:/][^[:space:]]*([^[:space:]]*[[:space:]]+){0,6}(is[[:space:]_-]+)?(not[[:space:]_-]+currently[[:space:]_-]+available|not[[:space:]_-]+available|unavailable|not[[:space:]_-]+supported|not[[:space:]_-]+found|does[[:space:]_-]+not[[:space:]_-]+exist)" "$file"
}

early_output_has_cli_error() {
  local file="$1"
  sed -n '1,40p' "$file" 2>/dev/null | grep -Eiq '^[[:space:]]*((error|fatal)[[:space:]:-]+.*(authentication failed|unauthorized|permission denied|login required|not logged in|rate limit|rate limited|quota exceeded|insufficient quota|network error|request timeout|request timed out|timed out|timeout error|api key|invalid api key|no api key|http 40[13]|http 429|copilot_[A-Z_]+)|(authentication failed|unauthorized|permission denied|login required|not logged in|rate limited|rate limit exceeded|quota exceeded|insufficient quota|network error|request timeout|request timed out|timeout error|invalid api key|no api key|http 40[13]|http 429|copilot_[A-Z_]+)([[:space:]:-]|$))'
}

early_output_has_error_prefix() {
  local file="$1"
  sed -n '1,40p' "$file" 2>/dev/null | grep -Eiq '^[[:space:]]*(error|fatal)[[:space:]:-]'
}

early_output_has_model_error_line() {
  local file="$1"
  sed -n '1,40p' "$file" 2>/dev/null | grep -Eiq "^[[:space:]]*(model_not_supported|unknown[[:space:]_-]+model|invalid[[:space:]_-]+model|unsupported[[:space:]_-]+model|no[[:space:]_-]+such[[:space:]_-]+model|(the[[:space:]_-]+)?requested[[:space:]_-]+model|model([[:space:]_-]+id)?[[:space:]_-]*:?|model[[:space:]_-]+[^[:space:]]).*(not[[:space:]_-]+currently[[:space:]_-]+available|not[[:space:]_-]+available|unavailable|not[[:space:]_-]+supported|not[[:space:]_-]+found|does[[:space:]_-]+not[[:space:]_-]+exist|model_not_supported)"
}

default_claude_model="claude-haiku-4.5"
fallback_model="auto"
candidates=()
if [[ -n "${CV_COPILOT_MODEL:-}" ]]; then
  candidates+=("$CV_COPILOT_MODEL")
fi
if [[ "${CV_COPILOT_MODEL:-}" != "$default_claude_model" ]]; then
  candidates+=("$default_claude_model")
fi
tmp="$CV_RUN_DIR/results/copilot.attempt.tmp"
tmp_err="$CV_RUN_DIR/results/copilot.attempt.err.tmp"
tmp_combined="$CV_RUN_DIR/results/copilot.attempt.combined.tmp"
attempts_file="$CV_RUN_DIR/status/copilot.attempts.tsv"
if [[ "$reviewer_attempt" -eq 0 ]]; then
  : >"$attempts_file"
fi
copilot_attempt_seq=0
if [[ -f "$attempts_file" ]]; then
  copilot_attempt_seq="$(wc -l <"$attempts_file" | tr -d ' ')"
fi
status=1
used_model=""
preferred_model=""
preferred_status=""
fallback_status="not_applicable"
final_response_bytes="missing"
final_response_state="missing"

body_state_for_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return
  fi
  if [[ ! -s "$file" ]]; then
    printf 'empty'
    return
  fi
  if ! LC_ALL=C grep -q '[^[:space:]]' "$file" 2>/dev/null; then
    printf 'blank'
    return
  fi
  printf 'nonempty'
}

record_copilot_attempt() {
  local kind="$1"
  local model="$2"
  local attempt_status="$3"
  local response_bytes="$4"
  local response_state="$5"
  copilot_attempt_seq=$((copilot_attempt_seq + 1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$copilot_attempt_seq" "$kind" "$model" "$attempt_status" "$response_bytes" "$response_state" >>"$attempts_file"
}

for model in "${candidates[@]}"; do
  echo "[cross-verify] Trying Copilot model: $model" | tee -a "$out"
  : >"$tmp_err"
  : >"$tmp_combined"
  set +e
  CV_RUN_STDERR_TARGET="$tmp_err" run_streamed_to "$tmp" "$CV_COPILOT_CMD" -p "$instruction" --model "$model" --no-custom-instructions --disable-builtin-mcps --no-remote --no-auto-update -s --output-format text
  status=$?
  set -e
  cat "$tmp_err" "$tmp" >"$tmp_combined"
  attempt_response_bytes="$(wc -c <"$tmp" | tr -d ' ')"
  final_response_bytes="$attempt_response_bytes"
  final_response_state="$(body_state_for_file "$tmp")"
  preferred_model="$model"
  preferred_status="$status"
  if [[ -s "$tmp_err" ]]; then
    tee -a "$out" <"$tmp_err"
  fi
  cat "$tmp" >>"$out"
  if [[ "$status" -eq 0 ]] && is_model_unavailable_error "$tmp_combined" && { early_output_has_error_prefix "$tmp_combined" || early_output_has_model_error_line "$tmp_combined"; }; then
    echo "COPILOT_MODEL_ERROR_WITH_ZERO_STATUS: model '$model' exited 0 but emitted a model-unavailable error; treating as failure." | tee -a "$out"
    status=2
    preferred_status="$status"
  elif [[ "$status" -eq 0 ]] && early_output_has_cli_error "$tmp_combined"; then
    if is_model_unavailable_error "$tmp_combined"; then
      echo "COPILOT_MODEL_ERROR_WITH_ZERO_STATUS: model '$model' exited 0 but emitted a model-unavailable error; treating as failure." | tee -a "$out"
      status=2
    else
      echo "COPILOT_ERROR_WITH_ZERO_STATUS: model '$model' exited 0 but emitted a CLI error; treating as failure." | tee -a "$out"
      status=1
    fi
    preferred_status="$status"
  fi
  if [[ "$status" -eq 0 ]]; then
    used_model="$model"
    if [[ "$final_response_state" != "nonempty" ]]; then
      echo "COPILOT_EMPTY_RESULT: model '$model' exited 0 but returned no usable reviewer body ($final_response_state)." | tee -a "$out"
      status=125
      preferred_status="$status"
      record_copilot_attempt "candidate" "$model" "$status" "$attempt_response_bytes" "$final_response_state"
    else
      record_copilot_attempt "candidate" "$model" "$status" "$attempt_response_bytes" "$final_response_state"
      break
    fi
    break
  fi
  used_model="$model"
  record_copilot_attempt "candidate" "$model" "$status" "$attempt_response_bytes" "$final_response_state"
  if ! is_model_unavailable_error "$tmp_combined"; then
    break
  fi
done

if [[ "$status" -ne 0 ]] && is_model_unavailable_error "$tmp_combined"; then
  failed_preferred_model="$preferred_model"
  failed_preferred_status="$preferred_status"
  echo "[cross-verify] Copilot Claude Haiku candidate failed; falling back to model: $fallback_model" | tee -a "$out"
  : >"$tmp_err"
  : >"$tmp_combined"
  set +e
  CV_RUN_STDERR_TARGET="$tmp_err" run_streamed_to "$tmp" "$CV_COPILOT_CMD" -p "$instruction" --model "$fallback_model" --no-custom-instructions --disable-builtin-mcps --no-remote --no-auto-update -s --output-format text
  status=$?
  set -e
  cat "$tmp_err" "$tmp" >"$tmp_combined"
  fallback_response_bytes="$(wc -c <"$tmp" | tr -d ' ')"
  final_response_bytes="$fallback_response_bytes"
  final_response_state="$(body_state_for_file "$tmp")"
  if [[ "$status" -eq 0 ]] && is_model_unavailable_error "$tmp_combined" && { early_output_has_error_prefix "$tmp_combined" || early_output_has_model_error_line "$tmp_combined"; }; then
    echo "COPILOT_MODEL_ERROR_WITH_ZERO_STATUS: fallback model '$fallback_model' exited 0 but emitted a model-unavailable error; treating as failure." | tee -a "$out"
    status=2
  elif [[ "$status" -eq 0 ]] && early_output_has_cli_error "$tmp_combined"; then
    if is_model_unavailable_error "$tmp_combined"; then
      echo "COPILOT_MODEL_ERROR_WITH_ZERO_STATUS: fallback model '$fallback_model' exited 0 but emitted a model-unavailable error; treating as failure." | tee -a "$out"
      status=2
    else
      echo "COPILOT_ERROR_WITH_ZERO_STATUS: fallback model '$fallback_model' exited 0 but emitted a CLI error; treating as failure." | tee -a "$out"
      status=1
    fi
  fi
  if [[ "$status" -eq 0 && "$final_response_state" != "nonempty" ]]; then
    echo "COPILOT_EMPTY_RESULT: fallback model '$fallback_model' exited 0 but returned no usable reviewer body ($final_response_state)." | tee -a "$out"
    status=125
  fi
  fallback_status="$status"
  record_copilot_attempt "fallback" "$fallback_model" "$status" "$fallback_response_bytes" "$final_response_state"
  : >"$CV_RUN_DIR/status/copilot.fallback_used"
  {
    echo
    echo "COPILOT_FALLBACK_USED: preferred model '$failed_preferred_model' failed with status $failed_preferred_status; selected model '$fallback_model' finished with status $fallback_status."
  } | tee -a "$out"
  if [[ -s "$tmp_err" ]]; then
    tee -a "$out" <"$tmp_err"
  fi
  cat "$tmp" >>"$out"
  used_model="$fallback_model"
fi

record_payload_state_from_file "$tmp"
maybe_retry_suspect "$status" "$out"
rm -f "$tmp" "$tmp_err" "$tmp_combined"
printf '%s\n' "${preferred_model:-missing}" >"$CV_RUN_DIR/status/copilot.preferred_model"
printf '%s\n' "${preferred_status:-missing}" >"$CV_RUN_DIR/status/copilot.preferred_status"
printf '%s\n' "$used_model" >"$CV_RUN_DIR/status/copilot.model"
printf '%s\n' "$used_model" >"$CV_RUN_DIR/status/copilot.selected_model"
printf '%s\n' "$fallback_status" >"$CV_RUN_DIR/status/copilot.fallback_status"
printf '%s\n' "$final_response_bytes" >"$CV_RUN_DIR/status/copilot.response_bytes"
printf '%s\n' "$final_response_state" >"$CV_RUN_DIR/status/copilot.response_state"
record_status "$status"
echo "[cross-verify] Copilot reviewer exited with status $status using model '$used_model' at $(date '+%Y-%m-%dT%H:%M:%S%z')"
exit 0
EOF

cat >"$run_dir/write_run_summary.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

run_dir="${CV_RUN_DIR:?}"
summary="$run_dir/run_summary.md"
summary_tmp="$summary.$$"

status_value() {
  local agent="$1"
  local file="$run_dir/status/$agent.status"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    printf 'missing'
  fi
}

timed_out_value() {
  local agent="$1"
  if [[ -f "$run_dir/status/$agent.timed_out" ]]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

result_bytes() {
  local agent="$1"
  local file="$run_dir/results/$agent.out"
  if [[ -f "$file" ]]; then
    wc -c <"$file" | tr -d ' '
  else
    printf 'missing'
  fi
}

result_state() {
  local agent="$1"
  local file="$run_dir/results/$agent.out"
  local bytes
  if [[ ! -f "$file" ]]; then
    printf 'missing'
    return
  fi
  bytes="$(wc -c <"$file" | tr -d ' ')"
  if [[ "$bytes" -eq 0 ]]; then
    printf 'empty'
  elif ! LC_ALL=C grep -q '[^[:space:]]' "$file" 2>/dev/null; then
    printf 'blank'
  else
    printf 'nonempty'
  fi
}

payload_state_value() {
  local agent="$1"
  local file="$run_dir/status/$agent.payload_state"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    printf 'missing'
  fi
}

payload_reason_value() {
  local agent="$1"
  local file="$run_dir/status/$agent.payload_reason"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    printf 'missing'
  fi
}

response_bytes_value() {
  local agent="$1"
  local file="$run_dir/status/$agent.response_bytes"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    printf 'missing'
  fi
}

retry_value() {
  local agent="$1"
  local file="$run_dir/status/$agent.retry_count"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    printf '0'
  fi
}

overall_outcome() {
  local agent
  local status
  local state
  local payload_state
  local has_failure=0
  local has_suspect=0
  if [[ -n "${CV_ORCHESTRATOR_OUTCOME:-}" ]]; then
    printf '%s' "$CV_ORCHESTRATOR_OUTCOME"
    return
  fi
  for agent in codex gemini copilot; do
    if [[ ! -f "$run_dir/status/$agent.status" ]]; then
      printf 'RUNNING_OR_INCOMPLETE'
      return
    fi
    status="$(cat "$run_dir/status/$agent.status")"
    if [[ "$status" != "0" ]]; then
      has_failure=1
    fi
    state="$(result_state "$agent")"
    if [[ "$state" != "nonempty" ]]; then
      has_failure=1
    fi
  done
  for agent in codex gemini copilot; do
    payload_state="$(payload_state_value "$agent")"
    if [[ "$payload_state" == "suspect" || "$payload_state" == "missing" ]]; then
      has_suspect=1
    fi
  done
  if [[ "$has_failure" -eq 1 && "$has_suspect" -eq 1 ]]; then
    printf 'DONE_WITH_FAILURES_AND_SUSPECT_OUTPUT'
    return
  fi
  if [[ "$has_failure" -eq 1 ]]; then
    printf 'DONE_WITH_FAILURES'
    return
  fi
  if [[ "$has_suspect" -eq 1 ]]; then
    printf 'DONE_WITH_SUSPECT_OUTPUT'
    return
  fi
  printf 'DONE'
}

fallback_used="no"
if [[ -f "$run_dir/status/copilot.fallback_used" ]] || grep -q '^COPILOT_FALLBACK_USED:' "$run_dir/results/copilot.out" 2>/dev/null; then
  fallback_used="yes"
fi

copilot_preferred_model="missing"
if [[ -f "$run_dir/status/copilot.preferred_model" ]]; then
  copilot_preferred_model="$(cat "$run_dir/status/copilot.preferred_model")"
fi

copilot_preferred_status="missing"
if [[ -f "$run_dir/status/copilot.preferred_status" ]]; then
  copilot_preferred_status="$(cat "$run_dir/status/copilot.preferred_status")"
fi

copilot_selected_model="missing"
if [[ -f "$run_dir/status/copilot.selected_model" ]]; then
  copilot_selected_model="$(cat "$run_dir/status/copilot.selected_model")"
elif [[ -f "$run_dir/status/copilot.model" ]]; then
  copilot_selected_model="$(cat "$run_dir/status/copilot.model")"
fi

copilot_fallback_status="not_applicable"
if [[ -f "$run_dir/status/copilot.fallback_status" ]]; then
  copilot_fallback_status="$(cat "$run_dir/status/copilot.fallback_status")"
fi

copilot_prompt_bytes="missing"
if [[ -f "$run_dir/status/copilot.prompt_bytes" ]]; then
  copilot_prompt_bytes="$(cat "$run_dir/status/copilot.prompt_bytes")"
fi

copilot_prompt_limit_bytes="missing"
if [[ -f "$run_dir/status/copilot.prompt_limit_bytes" ]]; then
  copilot_prompt_limit_bytes="$(cat "$run_dir/status/copilot.prompt_limit_bytes")"
fi

copilot_prompt_truncated="missing"
if [[ -f "$run_dir/status/copilot.prompt_truncated" ]]; then
  copilot_prompt_truncated="$(cat "$run_dir/status/copilot.prompt_truncated")"
fi

copilot_response_state="missing"
if [[ -f "$run_dir/status/copilot.response_state" ]]; then
  copilot_response_state="$(cat "$run_dir/status/copilot.response_state")"
fi

copilot_response_bytes="missing"
if [[ -f "$run_dir/status/copilot.response_bytes" ]]; then
  copilot_response_bytes="$(cat "$run_dir/status/copilot.response_bytes")"
fi

{
  printf '# Cross-Verify Run Summary\n\n'
  printf -- '- Run dir: `%s`\n' "$run_dir"
  printf -- '- Workdir: `%s`\n' "${CV_WORKDIR:-unknown}"
  printf -- '- Generated at: `%s`\n\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf -- '- Overall outcome: `%s`\n\n' "$(overall_outcome)"
  printf '| Reviewer | Status | Timed out | Result state | Payload state | Payload reason | Retries | Result bytes | Payload bytes |\n'
  printf '| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: |\n'
  for agent in codex gemini copilot; do
    printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$agent" "$(status_value "$agent")" "$(timed_out_value "$agent")" "$(result_state "$agent")" "$(payload_state_value "$agent")" "$(payload_reason_value "$agent")" "$(retry_value "$agent")" "$(result_bytes "$agent")" "$(response_bytes_value "$agent")"
  done
  printf '\n## Copilot\n\n'
  printf -- '- Default Claude candidate: `claude-haiku-4.5`\n'
  printf -- '- Preferred model: `%s`\n' "$copilot_preferred_model"
  printf -- '- Preferred status: `%s`\n' "$copilot_preferred_status"
  printf -- '- Selected/requested model: `%s`\n' "$copilot_selected_model"
  printf -- '- Fallback used: `%s`\n' "$fallback_used"
  printf -- '- Fallback status: `%s`\n' "$copilot_fallback_status"
  printf -- '- Prompt bytes: `%s`\n' "$copilot_prompt_bytes"
  printf -- '- Prompt limit bytes: `%s`\n' "$copilot_prompt_limit_bytes"
  printf -- '- Prompt truncated: `%s`\n' "$copilot_prompt_truncated"
  printf -- '- Reviewer body state: `%s`\n' "$copilot_response_state"
  printf -- '- Reviewer payload state: `%s`\n' "$(payload_state_value copilot)"
  printf -- '- Reviewer payload reason: `%s`\n' "$(payload_reason_value copilot)"
  printf -- '- Reviewer payload bytes: `%s`\n' "$copilot_response_bytes"
  if [[ -f "$run_dir/status/copilot.attempts.tsv" ]]; then
    printf '\n### Copilot Attempts\n\n'
    printf '| # | Kind | Model | Status | Body bytes | Body state |\n'
    printf '| ---: | --- | --- | --- | ---: | --- |\n'
    while IFS="$(printf '\t')" read -r seq kind model attempt_status response_bytes response_state; do
      [[ -n "$seq" ]] || continue
      printf '| %s | %s | `%s` | %s | %s | %s |\n' "$seq" "$kind" "$model" "$attempt_status" "$response_bytes" "$response_state"
    done <"$run_dir/status/copilot.attempts.tsv"
  fi
} >"$summary_tmp"
mv "$summary_tmp" "$summary"

printf '%s\n' "$summary"
EOF

cat >"$run_dir/watch_status.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
run_dir="$CV_RUN_DIR"
echo "[cross-verify] Run dir: $run_dir"
echo "[cross-verify] Waiting for reviewer status files..."
while true; do
  clear 2>/dev/null || true
  echo "Cross-Verify Monitor"
  echo "Run dir: $run_dir"
  echo
  for agent in codex gemini copilot; do
    if [[ -f "$run_dir/status/$agent.status" ]]; then
      payload_state="pending"
      if [[ -f "$run_dir/status/$agent.payload_state" ]]; then
        payload_state="$(cat "$run_dir/status/$agent.payload_state")"
      fi
      printf '%-8s done  status=%s payload=%s\n' "$agent" "$(cat "$run_dir/status/$agent.status")" "$payload_state"
    else
      printf '%-8s running\n' "$agent"
    fi
  done
  echo
  echo "Result files:"
  ls -1 "$run_dir/results" 2>/dev/null || true
  [[ -f "$run_dir/status/codex.status" && -f "$run_dir/status/gemini.status" && -f "$run_dir/status/copilot.status" ]] && break
  sleep 2
done
echo
summary_path="$("$run_dir/write_run_summary.sh")"
completion_outcome="$(sed -n 's/^- Overall outcome: `\([^`]*\)`.*/\1/p' "$summary_path" | head -1)"
if [[ -z "$completion_outcome" ]]; then
  completion_outcome="UNKNOWN"
fi
echo "[cross-verify] $completion_outcome: all reviewer status files are present."
rm -f "${CV_ENV_FILE:-}"
echo "[cross-verify] Run summary: $run_dir/run_summary.md"
EOF

chmod +x "$run_dir"/run_*.sh "$run_dir/watch_status.sh" "$run_dir/write_run_summary.sh"

cv_env_prefix="CV_RUN_DIR=$(shell_quote "$run_dir") CV_WORKDIR=$(shell_quote "$workdir") CV_ENV_FILE=$(shell_quote "$forward_env_file") CV_TIMEOUT_CMD=$(shell_quote "$timeout_cmd") CV_REVIEWER_TIMEOUT_SECONDS=$(shell_quote "$reviewer_timeout_seconds") CV_REVIEWER_MAX_RETRIES=$(shell_quote "$reviewer_max_retries") CV_CODEX_CMD=$(shell_quote "$codex_cmd") CV_CODEX_MODEL=$(shell_quote "${CROSS_VERIFY_CODEX_MODEL:-}") CV_CODEX_SANDBOX=$(shell_quote "${CROSS_VERIFY_CODEX_SANDBOX:-workspace-write}") CV_GEMINI_CMD=$(shell_quote "$gemini_cmd") CV_GEMINI_MODEL=$(shell_quote "${CROSS_VERIFY_GEMINI_MODEL:-gemini-2.5-pro}") CV_COPILOT_CMD=$(shell_quote "$copilot_cmd") CV_COPILOT_MODEL=$(shell_quote "${CROSS_VERIFY_COPILOT_MODEL:-}") CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES=$(shell_quote "${CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES:-}")"

tmux new-session -d -s "$session_name" -n reviewers "$cv_env_prefix bash $(shell_quote "$run_dir/run_codex.sh"); printf '\n[codex pane done]\n'; exec bash -l"
tmux split-window -t "$session_name:reviewers" -h "$cv_env_prefix bash $(shell_quote "$run_dir/run_gemini.sh"); printf '\n[gemini pane done]\n'; exec bash -l"
tmux split-window -t "$session_name:reviewers" -v "$cv_env_prefix bash $(shell_quote "$run_dir/run_copilot.sh"); printf '\n[copilot pane done]\n'; exec bash -l"
tmux select-layout -t "$session_name:reviewers" tiled >/dev/null
tmux new-window -t "$session_name" -n monitor "$cv_env_prefix bash $(shell_quote "$run_dir/watch_status.sh"); printf '\n[monitor done]\n'; exec bash -l"
tmux select-window -t "$session_name:reviewers" >/dev/null

open_attach_window() {
  local attach_command="tmux attach -t $(shell_quote "$session_name")"
  local terminal_app="${CROSS_VERIFY_TERMINAL_APP:-auto}"

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
        if open -na "$ghostty_app" --args -e /bin/zsh -lc "$attach_command" >/dev/null 2>&1; then
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
  do script "$attach_command"
end tell
EOF
        echo "TERMINAL_APP=terminal"
        return 0
      fi
    fi
  fi

  echo "Open a terminal and run: tmux attach -t $session_name"
}

if [[ "$open_terminal" -eq 1 && "${CI:-}" != "true" && "${CI:-}" != "1" ]]; then
  open_attach_window
elif [[ "$open_terminal" -eq 1 ]]; then
  echo "TERMINAL_APP=skipped_ci"
fi

echo "TMUX_SESSION=$session_name"
echo "RUN_DIR=$run_dir"
echo "ATTACH_COMMAND=tmux attach -t $session_name"
echo "RESULTS:"
echo "  $run_dir/results/codex.out"
echo "  $run_dir/results/gemini.out"
echo "  $run_dir/results/copilot.out"
echo "  $run_dir/run_summary.md"

if [[ "$wait_for_results" -eq 1 ]]; then
  deadline=$((SECONDS + wait_timeout_seconds))
  while [[ ! -f "$run_dir/status/codex.status" || ! -f "$run_dir/status/gemini.status" || ! -f "$run_dir/status/copilot.status" ]]; do
    if ((SECONDS >= deadline)); then
      echo "TIMEOUT: reviewer status files still missing after ${wait_timeout_seconds}s."
      echo "PARTIAL_STATUSES:"
      for agent in codex gemini copilot; do
        if [[ -f "$run_dir/status/$agent.status" ]]; then
          printf '  %s=%s\n' "$agent" "$(cat "$run_dir/status/$agent.status")"
        else
          printf '  %s=missing\n' "$agent"
        fi
      done
      CV_RUN_DIR="$run_dir" CV_WORKDIR="$workdir" CV_ORCHESTRATOR_OUTCOME="WAIT_TIMEOUT" "$run_dir/write_run_summary.sh" >/dev/null
      rm -f "$forward_env_file"
      echo "RUN_SUMMARY=$run_dir/run_summary.md"
      exit 124
    fi
    sleep 2
  done
  summary_path="$(CV_RUN_DIR="$run_dir" CV_WORKDIR="$workdir" "$run_dir/write_run_summary.sh")"
  completion_outcome="$(sed -n 's/^- Overall outcome: `\([^`]*\)`.*/\1/p' "$summary_path" | head -1)"
  if [[ -z "$completion_outcome" ]]; then
    completion_outcome="UNKNOWN"
  fi
  echo "$completion_outcome: all reviewer status files are present."
  rm -f "$forward_env_file"
  echo "STATUSES:"
  for agent in codex gemini copilot; do
    printf '  %s=%s\n' "$agent" "$(cat "$run_dir/status/$agent.status")"
  done
  echo "RUN_SUMMARY=$run_dir/run_summary.md"
else
  CV_RUN_DIR="$run_dir" CV_WORKDIR="$workdir" "$run_dir/write_run_summary.sh" >/dev/null
fi
