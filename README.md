# HG Codex Skills

Public Codex skill collection by Hyeongi Kim.

The first released skill is `cross-verify`, a tmux-based multi-reviewer workflow that asks Codex, Gemini, and Copilot to inspect the same prompt in parallel, then produces run metadata for final synthesis.

## Skills

### cross-verify

Use `cross-verify` when you want an independent review of an answer, code change, design choice, bug analysis, or release decision.

The skill launches reviewer agents in tmux, opens the tmux session in Ghostty by default when available, and writes:

- `run_summary.md`
- `results/codex.out`
- `results/gemini.out`
- `results/copilot.out`

The summary records reviewer status, timeout state, payload quality, retry count, Copilot model attempts, fallback state, and result sizes.

## Requirements

`cross-verify` expects these CLIs to be installed and authenticated on the local machine:

- `tmux`
- `codex`
- `gemini`
- `copilot`

Ghostty is optional but recommended. If Ghostty is unavailable, the helper falls back to Terminal. Automation can pass `--no-open-terminal`.

## Install

List available skills:

```bash
npx skills@latest add hgkim215/codex-skills --list
```

Install `cross-verify` for Codex:

```bash
npx skills@latest add hgkim215/codex-skills --skill cross-verify --agent codex --global --yes
```

When Codex plugin marketplace installation is available in your environment, add this repo as a marketplace:

```bash
codex plugin marketplace add hgkim215/codex-skills
```

## Usage

Ask Codex with the skill trigger:

```text
$cross-verify 이 변경을 릴리즈해도 되는지 교차검증해줘.

상황:
- 변경 요약을 여기에 적는다.
- 검증해야 할 리스크를 적는다.

검증할 것:
1. 실패했는데 성공처럼 보일 가능성
2. 운영 환경에서 깨질 가능성
3. 문서와 실제 동작 불일치

각 reviewer는 P0/P1/P2로 심각도를 나누고, 근거가 있는 항목만 제시해줘.
```

The main Codex should read `run_summary.md` first, then inspect `results/*.out` before giving the final synthesis.

## Repository Layout

```text
.
├── .agents/plugins/marketplace.json
├── .codex-plugin/plugin.json
├── cross-verify/
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   └── scripts/cross_verify_tmux.sh
└── README.md
```

## License

MIT
