# code-review

Review completed diffs or QA outputs for bugs, regressions, architecture drift, and missing tests.

## Use When

- 구현 후 릴리스 전 diff를 리뷰하고 싶을 때
- `$ralph-qa` 또는 `$visual-ralph-qa` 결과를 리뷰 findings로 바꾸고 싶을 때
- 버그 리스크, 테스트 공백, 하네스 rule candidate를 찾고 싶을 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill code-review --agent codex --global --yes
```

Restart Codex after installation.

## Example

```text
$code-review 현재 변경 diff를 릴리스 전 관점으로 리뷰해줘.
```

Findings come first. If no issues are found, the output still calls out residual risk and test gaps.
