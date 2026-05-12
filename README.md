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

큰 작업에서 worker를 나누는 경우 `ralph-execute`는 Codex CLI worker를 tmux 세션으로 띄울 수 있고, `tmux-worker-watch`는 그 진행 상황을 Codex App 대화로 요약합니다.

Codex `goal` 기능은 선택 사항입니다. Ralph 스킬들은 goal을 per-skill checklist로 쓰지 않고 thread-level macro objective로만 다룹니다.

## Requirements

공통:

- Codex with local skill support
- `python3`
- `bash`
- `git`

tmux worker 기능:

- `tmux`
- Codex CLI
- Ghostty optional; 없으면 macOS Terminal 또는 수동 `tmux attach` 명령을 사용합니다.

`cross-verify`:

- `tmux`
- `codex`
- `gemini`
- `copilot`

`visual-ralph-qa`:

- Codex Browser, Playwright, 또는 사용 가능한 브라우저 자동화 표면

## Validation

Ralph suite 검증:

```bash
scripts/validate_release.sh
scripts/validate_ralph_release.sh
scripts/e2e_ralph_release.sh --deterministic --keep
scripts/e2e_ralph_release.sh --codex --keep
```

`validate_release.sh`는 전체 repo plugin metadata, 모든 skill folder, README, YAML, shell script를 확인합니다.

`--codex` E2E는 실제 Codex CLI worker를 tmux에서 실행해 임시 repo를 수정하고, run summary와 watcher 출력까지 검증합니다.

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
