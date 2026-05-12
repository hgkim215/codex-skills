# ralplan

Create an execution-ready plan from clarified requirements and repo evidence.

## Use When

- 구현 전에 접근 방식, 검증, 위험, worker 분할 여부를 결정해야 할 때
- `$deep-interview` 또는 `$analyze` 이후 실행 계획이 필요할 때
- 큰 작업을 main-only로 할지 tmux-visible worker로 나눌지 정해야 할 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill ralplan --agent codex --global --yes
```

Restart Codex after installation.

## Example

```text
$ralplan 위 분석을 바탕으로 구현 계획과 검증 계획을 만들어줘.
```

The plan should include a handoff target, validation checks, assumptions, risks, and worker visibility decision.
