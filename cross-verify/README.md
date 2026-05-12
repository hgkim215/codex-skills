# cross-verify

Run Codex, Gemini, and Copilot reviewers in parallel through tmux, then synthesize their findings.

## Use When

- 릴리스 가능 여부를 여러 관점에서 확인하고 싶을 때
- 코드 리뷰, 설계 판단, 버그 분석, 답변 품질을 독립 검증하고 싶을 때
- 한 모델의 결론만 믿기 어려운 고위험 판단을 다룰 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill cross-verify --agent codex --global --yes
```

Restart Codex after installation.

## Requirements

- `tmux`
- `codex`
- `gemini`
- `copilot`
- Ghostty optional; Terminal fallback is supported on macOS.

## Example

```text
$cross-verify 이 변경을 릴리스해도 되는지 교차검증해줘.

검증할 것:
1. 실패했는데 성공처럼 보일 가능성
2. 운영 환경에서 깨질 가능성
3. 문서와 실제 동작 불일치
```

The run writes a summary and reviewer outputs under a temporary run directory.
