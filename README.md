# Codex Skills by Hyeongi Kim

Hyeongi Kim이 직접 사용하는 Codex 스킬 모음입니다.

첫 번째 공개 스킬은 `cross-verify`입니다. 하나의 검증 프롬프트를 Codex, Gemini, Copilot reviewer에게 병렬로 보내고, 각 reviewer의 결과와 실행 상태를 요약해 최종 판단을 돕습니다.

## 포함된 스킬

### cross-verify

답변, 코드 리뷰, 설계 선택, 버그 분석, 릴리즈 판단처럼 한 번 더 독립 검증이 필요한 상황에서 사용합니다.

`cross-verify`는 tmux 세션에서 reviewer들을 병렬 실행하고, 기본적으로 Ghostty 창을 열어 진행 상황을 볼 수 있게 합니다. 실행 후에는 아래 파일을 생성합니다.

- `run_summary.md`
- `results/codex.out`
- `results/gemini.out`
- `results/copilot.out`

`run_summary.md`에는 reviewer별 status, timeout 여부, payload 품질, retry 횟수, Copilot 모델 시도 이력, fallback 여부, 결과 파일 크기가 기록됩니다.

## 사전 준비

`cross-verify`를 제대로 사용하려면 로컬에 아래 CLI가 설치되고 인증되어 있어야 합니다.

- `tmux`
- `codex`
- `gemini`
- `copilot`

Ghostty는 필수는 아니지만 권장합니다. Ghostty가 없으면 macOS Terminal로 fallback됩니다. 자동화나 테스트에서는 `--no-open-terminal` 옵션을 사용할 수 있습니다.

## 사용하는 방법

### 1. 레포에서 사용 가능한 스킬 확인

먼저 이 레포에서 설치할 수 있는 스킬 목록을 확인합니다.

```bash
npx skills@latest add hgkim215/codex-skills --list
```

현재는 `cross-verify`가 표시됩니다.

### 2. 원하는 스킬을 Codex에 설치

`cross-verify`를 Codex 전역 스킬로 설치합니다.

```bash
npx skills@latest add hgkim215/codex-skills --skill cross-verify --agent codex --global --yes
```

설치 후 새 Codex 세션에서 `$cross-verify` 트리거로 사용할 수 있습니다.

### 3. Codex plugin marketplace로 등록

Codex plugin marketplace 방식으로도 이 레포를 등록할 수 있습니다.

```bash
codex plugin marketplace add hgkim215/codex-skills
```

이미 등록한 뒤 최신 버전으로 갱신하려면 아래 명령을 사용합니다.

```bash
codex plugin marketplace upgrade hgkim-codex-skills
```

이 방식은 Codex가 이 레포를 plugin marketplace source로 인식하게 하는 경로입니다. 현재 Codex CLI에는 별도의 `codex plugin install` 또는 `codex plugin list` 명령은 없고, marketplace `add`, `upgrade`, `remove` 흐름을 사용합니다.

## 사용 예시

Codex에게 아래처럼 요청합니다.

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

실행이 끝나면 main Codex는 먼저 `run_summary.md`를 확인하고, 그 다음 `results/*.out`을 읽어 reviewer들의 공통 의견, 고유 지적, 충돌 지점, 최종 판단을 종합합니다.

## 레포 구조

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

## 라이선스

MIT
