# deep-interview

Clarify vague or high-risk work before planning or implementation.

## Use When

- 목표, 범위, non-goals, 완료 기준이 불명확할 때
- 사용자 판단이 필요한 결정을 먼저 정리해야 할 때
- 바로 구현하면 추측이 많아질 가능성이 높을 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill deep-interview --agent codex --global --yes
```

Restart Codex after installation.

## Example

```text
$deep-interview 이 기능을 만들기 전에 요구사항을 정리해줘.
```

Expected output is a compact requirements artifact that can be handed to `$analyze`, `$ralplan`, or `$ralph-execute`.
