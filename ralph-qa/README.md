# ralph-qa

Reproduce, fix, and verify a failure-centered loop.

## Use When

- 테스트, 빌드, 린트, 타입체크, 런타임 오류가 실패할 때
- 같은 실패 명령을 재실행해 수정 여부를 확인해야 할 때
- 일반 구현보다 원인 재현과 회귀 확인이 중심일 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill ralph-qa --agent codex --global --yes
```

Restart Codex after installation.

## Example

```text
$ralph-qa npm test 실패를 재현하고 고친 뒤 같은 명령으로 검증해줘.
```

Expected output includes reproduction, cause, fix, verification, regression checks, and residual risk.
