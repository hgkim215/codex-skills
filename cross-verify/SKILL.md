---
name: cross-verify
description: Cross-verify an answer, code review, design choice, bug analysis, or research conclusion by launching parallel Codex, Gemini, and Copilot reviewer agents in tmux, then synthesize consensus, unique findings, conflicts, and a final decision. Use when the user asks for cross verify, cross check, multi AI comparison, ask other AIs, 교차검증, 교차 검증, 다른 AI에도 물어봐, or 검증 에이전트.
allowed-tools: Bash(tmux:*), Bash(codex:*), Bash(gemini:*), Bash(copilot:*), Bash(git:*), Bash(mktemp:*), Bash(chmod:*), Bash(osascript:*), Bash(open:*), Bash(timeout:*), Bash(gtimeout:*)
metadata:
  short-description: Cross-check with Codex, Gemini, and Copilot
---

# Cross-Verify

Use this skill when the user wants an independent multi-agent check before the main Codex gives the final answer. The reviewers are advisory only; the main Codex decides the final recommendation.

## Graph Context

Read `../references/graph-context-policy.md` before preparing the verification prompt when structural code context, prior decisions, or multi-skill state materially affect the question.

- Include concise CodeGraph findings in the prompt for structural code reviews, impact analysis, or architecture decisions.
- Include ActiveGraph state only if available and relevant to goal/plan/evidence relationships.
- Include Obsidian notes only when a narrow prior-decision or user-preference lookup affects the judgment.
- Do not make reviewers depend on access to unavailable graph tools; pass bounded summaries and explicit file contents instead.

## Core Workflow

1. Prepare a focused verification prompt.
   - Restate the user's question or decision to verify.
   - Include success criteria, constraints, and any known uncertainty.
   - For code work, include the current goal plus relevant file paths, error logs, and a concise summary of local findings.
   - Include concise graph-context summaries only when they were cheap and materially relevant.
   - The helper script automatically adds `git status`, `git diff --stat`, and a bounded `git diff` when run inside a git repository.
2. Run the tmux helper:

```bash
export CROSS_VERIFY="${CROSS_VERIFY:-$HOME/.agents/skills/cross-verify/scripts/cross_verify_tmux.sh}"
"$CROSS_VERIFY" --workdir "$PWD" --prompt-file /path/to/verification-prompt.md
```

If no prompt file is available, pipe the prompt:

```bash
printf '%s\n' "Question and context to verify..." | "$CROSS_VERIFY" --workdir "$PWD"
```

For reviews that depend on specific files, include them explicitly so every reviewer sees the same bounded content:

```bash
"$CROSS_VERIFY" --workdir "$PWD" \
  --include-file path/to/file_a.dart \
  --include-file path/to/file_b.md \
  "Review this change for risks and missed edge cases."
```

3. Watch the Ghostty window that opens by default. If Ghostty is unavailable, the helper falls back to Terminal. Use `--no-open-terminal` only for automation or tests; `CI=true` also skips opening a local terminal.
4. Read the run summary first to understand execution state, then read the result files for the reviewers' actual findings:
   - `run_summary.md`
   - `results/codex.out`
   - `results/gemini.out`
   - `results/copilot.out`
5. Synthesize the final answer from the main Codex perspective.

## Reviewer Agents

- **Codex reviewer**: launched as a fresh `codex exec` process with `--sandbox workspace-write --ephemeral`, so tests/builds can run but the reviewer is instructed not to edit tracked files.
- **Gemini reviewer**: launched with `gemini-2.5-pro` by default, matching the local Gemini CLI default. Override with `CROSS_VERIFY_GEMINI_MODEL`. Gemini is instructed to rely on the prompt, git context, and explicit `--include-file` contents instead of trying to inspect the filesystem.
- **Copilot reviewer**: first tries `CROSS_VERIFY_COPILOT_MODEL` when set, then `claude-haiku-4.5` by default. If the preferred model fails with a model-specific unavailable/unsupported/not-found error, it falls back to `copilot --model auto` and writes a `COPILOT_FALLBACK_USED` label that includes preferred and fallback statuses.

The reviewer prompt forbids source edits. Inspection, builds, and tests are allowed when useful, but final implementation remains with the main Codex. Codex and Gemini receive large reviewer prompts over stdin to avoid shell argument-size failures; Copilot keeps a bounded prompt because its CLI uses `--prompt`. The Copilot prompt cap defaults to 60000 bytes and is hard-capped at 80000 bytes even when overridden; truncation state is reported in both `run_summary.md` and `results/copilot.out`.

Each reviewer output is also checked for payload quality. A zero-status output that looks like CLI/tool failure output in the early output is marked `suspect`, retried once by default, and still causes the overall outcome to become `DONE_WITH_SUSPECT_OUTPUT` if it remains suspect. Empty or whitespace-only reviewer output is treated as unusable rather than successful. When non-zero/empty/blank failures and suspect payloads are both present, the outcome is `DONE_WITH_FAILURES_AND_SUSPECT_OUTPUT`. `payload_reason` includes a coarse marker type and line number when possible, such as `cli_error_marker:cli_line_2`.

## Runtime Controls

- `CROSS_VERIFY_REVIEWER_TIMEOUT_SECONDS`: per-reviewer timeout. Defaults to `900`.
- `CROSS_VERIFY_REVIEWER_MAX_RETRIES`: retries for zero-status suspect reviewer output. Defaults to `1`; set `0` to disable.
- `CROSS_VERIFY_WAIT_TIMEOUT_SECONDS`: helper wait timeout. Defaults to reviewer timeout plus 60 seconds.
- `CROSS_VERIFY_INCLUDE_MAX_BYTES`: bytes included per `--include-file`. Defaults to `50000`.
- `CROSS_VERIFY_TERMINAL_APP`: `auto`, `ghostty`, or `terminal`. Defaults to `auto`.
- `CROSS_VERIFY_COPILOT_MODEL`: optional first Copilot model candidate. Defaults to trying `claude-haiku-4.5` when unset.
- `CROSS_VERIFY_COPILOT_MAX_PROMPT_BYTES`: bytes sent through Copilot `--prompt`. Defaults to `60000`; values above `80000` are capped to reduce shell argument-size risk.
- `CROSS_VERIFY_FORWARD_ENV_VARS`: space-separated env names forwarded into tmux panes through a private run-dir env file. Defaults to proxy variables only. Set it explicitly for token-based CLI auth; set it to an empty string to disable forwarding. The helper or monitor removes the env file after reviewers finish.

## Final Synthesis Format

Use this shape unless the user requested a different format:

```markdown
## Cross-Verification Results

### Run Summary
- Overall outcome, statuses, timeouts, result states, payload states/reasons, retries, selected/requested Copilot model, Copilot attempts, and fallback state from `run_summary.md`.
- Treat `run_summary.md` as execution metadata only; read `results/*.out` before judging consensus or reviewer findings.

### Consensus
- Points supported by multiple reviewers and local evidence.

### Unique Findings
- **Codex**:
- **Gemini**:
- **Copilot**:

### Conflicts
- Disagreement:
- Evidence:
- Main Codex judgment:

### Final Decision
- What to do or believe now.
- What remains uncertain, if anything.
```

## Failure Handling

- If a CLI is missing, keep the failure text in that model's result and synthesize with the remaining reviewers.
- If a reviewer times out, its status file should contain `124`; synthesize with the remaining reviewers.
- If Copilot cannot use Claude Haiku 4.5, accept `auto` fallback only when `COPILOT_FALLBACK_USED` is present and report the selected/requested model plus fallback status from `run_summary.md`. Do not claim `auto` is the resolved underlying model unless Copilot explicitly reports that.
- If the helper prints `DONE_WITH_FAILURES`, the tmux orchestration completed but at least one reviewer exited non-zero or returned an empty/blank/missing result, with no remaining suspect payload marker. For Copilot, check both the output file state and the `Reviewer body state`/`Reviewer payload state` fields because orchestration labels can make `results/copilot.out` nonempty even when Copilot returned no review body.
- If the helper prints `DONE_WITH_SUSPECT_OUTPUT`, all reviewer status files are present and statuses may be zero, but at least one reviewer output still looks contaminated by CLI/tool error text after the allowed retry. Treat that reviewer as potentially unusable until you inspect `Payload reason`, saved `*.suspect_attempt_*.out`, and the final `results/*.out`.
- If the helper prints `DONE_WITH_FAILURES_AND_SUSPECT_OUTPUT`, handle both branches: at least one reviewer failed or returned missing/empty/blank output, and at least one reviewer output remains suspect.
- If a reviewer returns unusable output, say so; do not invent its position.
- If all reviewer agents fail, report the failures and continue with the main Codex's own analysis.
