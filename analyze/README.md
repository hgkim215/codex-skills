# analyze

Run read-only analysis before planning or editing.

## Use When

- 코드베이스 구조, 문서, 하네스, 장애 원인을 먼저 파악해야 할 때
- 구현 전에 근거, 추론, 불확실성을 분리하고 싶을 때
- 변경 영향 범위를 알고 싶지만 아직 파일을 수정하면 안 될 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill analyze --agent codex --global --yes
```

Restart Codex after installation.

## Example

```text
$analyze 이 레포의 인증 흐름과 변경 영향 범위를 읽기 전용으로 분석해줘.
```

Expected output includes findings, evidence, uncertainty, risk, and the recommended next skill.
