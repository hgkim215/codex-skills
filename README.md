# Codex Skills by Hyeongi Kim

Codex에서 반복적으로 쓰는 작업 흐름을 스킬로 묶은 공개 저장소입니다.

현재 포함된 축은 두 가지입니다.

- `cross-verify`: Codex, Gemini, Copilot reviewer를 tmux에서 병렬 실행해 결론을 교차검증
- Ralph suite: 요구사항 정리, 분석, 계획, 실행, QA, 시각 검증, 코드 리뷰, worker 진행상황 관찰을 나눈 Codex-native workflow

## Skills

| Skill | When to use |
| --- | --- |
| [`cross-verify`](./cross-verify/) | 중요한 답변, 설계, 리뷰, 릴리스 판단을 여러 reviewer로 교차검증할 때 |
| [`deep-interview`](./deep-interview/) | 요구사항, 범위, 완료 기준이 불명확한 작업을 시작할 때 |
| [`analyze`](./analyze/) | 수정 전에 코드베이스, 문서, 장애 원인, 하네스를 읽기 전용으로 분석할 때 |
| [`ralplan`](./ralplan/) | 구현 전에 실행 가능한 계획과 worker 분할 여부를 정할 때 |
| [`ralph-execute`](./ralph-execute/) | 승인된 계획이나 구체적 변경 요청을 실제로 구현할 때 |
| [`ralph-qa`](./ralph-qa/) | 실패한 테스트, 빌드, 런타임 오류를 재현-수정-검증할 때 |
| [`visual-ralph-qa`](./visual-ralph-qa/) | UI, 화면, 레이아웃, 반응형, 스크린샷 기반 검증이 필요할 때 |
| [`code-review`](./code-review/) | 완료된 diff나 QA 결과를 릴리스 전 리뷰할 때 |
| [`tmux-worker-watch`](./tmux-worker-watch/) | tmux/Ghostty에서 도는 worker 진행 상황을 읽고 요약할 때 |

## Quick Install

### Install all skills for Codex

```bash
npx skills@latest add hgkim215/codex-skills --skill '*' --agent codex --global --yes
```

이 명령은 현재 저장소의 설치 가능한 모든 스킬을 Codex용 global skill로 한 번에 설치합니다.
`*`는 shell glob 확장을 피하려고 따옴표로 감싸야 합니다.

### Install one skill

```bash
npx skills@latest add hgkim215/codex-skills --skill ralph-execute --agent codex --global --yes
```

다른 스킬을 설치하려면 `ralph-execute` 자리에 원하는 폴더명을 넣습니다.
이 명령은 Codex용 skill을 기본적으로 `~/.agents/skills/<skill-name>`에 복사합니다.

### List installable skills

```bash
npx skills@latest add hgkim215/codex-skills --list
```

### Install all skills for all supported agents

Codex뿐 아니라 감지 가능한 모든 agent에 설치하려면:

```bash
npx skills@latest add hgkim215/codex-skills --all --global
```

`--all`은 `--skill '*' --agent '*' --yes`의 축약입니다.

### Register as a Codex plugin marketplace source

```bash
codex plugin marketplace add hgkim215/codex-skills
```

이미 등록한 뒤 최신 버전으로 갱신하려면:

```bash
codex plugin marketplace upgrade hgkim-codex-skills
```

설치 후에는 Codex를 재시작해야 새 스킬이 인식됩니다.

## Ralph Workflow

Ralph suite는 한 번에 모든 일을 시키기보다 작업 단계를 분리합니다.

```text
$deep-interview -> $analyze -> $ralplan -> $ralph-execute -> $ralph-qa / $visual-ralph-qa -> $code-review
```

큰 작업에서 worker를 나누는 경우 `ralph-execute`는 Codex CLI worker를 tmux 세션으로 띄울 수 있고, `tmux-worker-watch`는 그 진행 상황을 Codex App 대화로 요약합니다. worker를 쓰면 기본적으로 Ghostty가 열리고, 하나의 tmux session 안의 `workers` window에 subagent 수만큼 tiled pane이 만들어집니다. `monitor` window는 aggregate status를 보여주는 보조 창입니다. 각 worker run은 즉시 확인용 `worker_handoff_summary.md`를 만들고, 기본적으로 `.ralph/worker-runs/` 아래에 누적 handoff bundle과 `INDEX.md`를 남깁니다.

Codex `goal` 기능은 선택 사항입니다. Ralph 스킬들은 goal을 per-skill checklist로 쓰지 않고 thread-level macro objective로만 다룹니다. 사용자가 `goal`, `native goal`, `Codex App goal`, 백그라운드 루프, 또는 완료될 때까지 계속 진행을 요청하면 native goal tool preflight를 먼저 시도합니다. native tool이 없으면 goal이 활성화됐다고 주장하지 않고, 명시적으로 Ralph ledger fallback 여부를 나눠서 보고합니다.

## Optional Graph And Memory Integrations

Ralph suite can use graph and memory tools when they are available, but they are not hard requirements. The default policy is:

```text
CodeGraph: selectively on by default for structural code context
ActiveGraph: off by default; use only for long-running, complex, worker-heavy work
Obsidian: off by default; use only for narrow long-term memory or prior decisions
```

These integrations should never block a small edit, a local test fix, or a direct answer. If a tool is unavailable, Ralph skills continue with repo files, docs, tests, command output, `.ralph` ledgers, and final handoff summaries.

### CodeGraph

Use CodeGraph for structural code questions: symbol lookup, callers/callees, route or component ownership, architecture boundaries, and blast-radius checks. Skip it for literal text search, docs-only work, config edits, or already-localized fixes.

Install/enable guidance:

- Install or enable a CodeGraph MCP/CLI provider in your Codex environment.
- Initialize CodeGraph per project when the repo has enough structural complexity to justify it.
- If the `codegraph` CLI is available, initialize from the target repo with:

```bash
codegraph init -i
```

- Add project-level guidance such as `AGENTS.md` so agents know when to prefer CodeGraph over raw search.
- If CodeGraph is missing or not initialized, Ralph skills should ask about initialization only for non-trivial structural work.

### ActiveGraph

ActiveGraph is treated as an optional state graph, not a required runtime. Use it only if an actual ActiveGraph MCP/tool is installed and the task needs machine-readable relationships across goal, plan, workers, files, symbols, commands, evidence, findings, and decisions.

Install/enable guidance:

- Install or enable the ActiveGraph MCP/tool in the Codex environment if your setup provides one.
- Confirm the tool is callable before relying on it.
- Do not duplicate full markdown plans or logs into ActiveGraph. Store compact references and relationships.
- If ActiveGraph is unavailable, use native goal tools, `.ralph/goals/<goal-slug>/`, `.ralph/worker-runs/`, and final summaries instead.

### Obsidian

Obsidian is for human long-term memory: prior decisions, user preferences, non-goals, project philosophy, and historical notes. It should not be used as a broad search engine during normal execution loops.

Install/enable guidance:

- Install Obsidian and configure a vault.
- Enable an Obsidian MCP connector or local REST/API bridge that exposes read/search/patch tools to Codex.
- Prefer explicit project notes, index files, tags, or frontmatter over vault-wide search.
- If Obsidian lookup is slow, noisy, or unavailable, skip it and continue with repo evidence.

## Requirements

공통:

- Codex with local skill support
- `python3`
- `bash`
- `git`

tmux worker 기능:

- `tmux`
- Codex CLI
- Ghostty preferred for visible worker panes. If Ghostty is unavailable, macOS Terminal or a manual `tmux attach` command is used as fallback.

선택적 graph/memory 기능:

- CodeGraph MCP/CLI for structural code context
- ActiveGraph MCP/tool for durable state relationships in complex worker-heavy tasks
- Obsidian MCP/API connector for narrow long-term memory lookup

`cross-verify`:

- `tmux`
- `codex`
- `gemini`
- `copilot`

`visual-ralph-qa`:

- Codex Browser, Playwright, 또는 사용 가능한 브라우저 자동화 표면

## Update Log

### v0.3.0 - 2026-05-22

- Graph context policy 추가: CodeGraph는 구조/영향도 중심으로 선택적 기본 사용, ActiveGraph는 장기/복잡/worker-heavy 작업에서만 사용, Obsidian은 좁은 장기기억 조회에만 사용하도록 정리했습니다.
- Orchestration policy 추가: subagent는 coordination cost를 이길 때만 사용하고, main agent가 최종 통합/검증/완료 판단을 소유하도록 명시했습니다.
- Ghostty/tmux visibility 강화: subagent 사용 시 Ghostty-attached tmux session, `workers` window, subagent별 tiled pane, optional `monitor` window를 기본 기대 동작으로 문서화했습니다.
- `ralph_tmux_workers.sh` 출력에 `TMUX_WORKERS_WINDOW`와 `WORKER_PANE_COUNT`를 추가해 worker run 가시성 검증이 쉬워졌습니다.
- CodeGraph, ActiveGraph, Obsidian 설치/활성화 가이드를 README에 추가했습니다. 세 도구는 optional integration이며 미설치 시 Ralph 흐름을 막지 않습니다.
- 검증 로그 추가: graph/orchestration policy와 Ghostty/tmux worker pane smoke test 결과를 `docs/test-results/`에 기록했습니다.

### v0.2.0 - 2026-05-16

- Ralph goal 흐름 강화: Goal Readiness Gate, Goal Scorecard, progress ledger 구조를 추가해 목표가 불명확할 때 바로 실행하지 않고 필요한 정보를 먼저 요구하도록 정리했습니다.
- Codex App native goal preflight 추가: Composer Command에 `/goal`이 없더라도 내부 `get_goal`/`create_goal`/`update_goal` tool이 노출된 세션에서는 먼저 native goal 상태를 확인하고, 명확한 macro goal이 없으면 실행 전에 사용자에게 요구하도록 정리했습니다.
- Subagent/worker 사용 범위 확대: `ralplan`, `ralph-execute`, `ralph-qa`, `visual-ralph-qa`가 non-trivial 작업에서 worker-first 판단을 수행하고, main-only 선택 시 사유를 남기도록 업데이트했습니다.
- Worker handoff 누적 기록 추가: tmux-visible worker run마다 `worker_handoff_summary.md`를 생성하고 `.ralph/worker-runs/` 아래에 누적 기록과 `INDEX.md`를 남기도록 구현했습니다.
- Watcher/E2E 검증 강화: `tmux-worker-watch`가 handoff summary를 우선 읽고, E2E가 persistent handoff bundle과 index 생성까지 검증하도록 확장했습니다.
- 검증 결과 문서화: goal hardening과 worker handoff persistence 검증 결과를 `docs/test-results/`에 기록했습니다.

## Validation

Ralph suite 검증:

```bash
scripts/validate_release.sh
scripts/validate_ralph_release.sh
scripts/e2e_ralph_release.sh --deterministic --keep
scripts/e2e_ralph_release.sh --codex --keep
```

`validate_release.sh`는 전체 repo plugin metadata, 모든 skill folder, README, YAML, shell script를 확인합니다.

`--codex` E2E는 실제 Codex CLI worker를 tmux에서 실행해 임시 repo를 수정하고, run summary, worker handoff summary, persistent handoff index, watcher 출력까지 검증합니다.

## Repository Structure

```text
.
├── .agents/plugins/marketplace.json
├── .codex-plugin/plugin.json
├── cross-verify/
├── deep-interview/
├── analyze/
├── ralplan/
├── ralph-execute/
├── ralph-qa/
├── visual-ralph-qa/
├── code-review/
├── tmux-worker-watch/
├── references/
├── scripts/
├── RALPH_RELEASE_MANIFEST.md
└── README.md
```

## License

MIT
