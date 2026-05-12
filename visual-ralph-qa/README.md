# visual-ralph-qa

Verify and fix UI issues with browser, screenshot, viewport, DOM, or console evidence.

## Use When

- blank screen, layout overflow, text overlap, missing image, broken interaction을 확인해야 할 때
- UI 변경 후 desktop/mobile viewport 검증이 필요할 때
- screenshot-backed visual evidence가 필요한 작업일 때

## Install

```bash
npx skills@latest add hgkim215/codex-skills --skill visual-ralph-qa --agent codex --global --yes
```

Restart Codex after installation.

## Requirements

- Codex Browser, Playwright, or another available browser automation surface
- A local or reachable target URL when browser verification is needed

## Example

```text
$visual-ralph-qa localhost 화면에서 모바일/데스크톱 레이아웃 깨짐을 확인하고 수정해줘.
```

Expected output includes target, viewports, visual checks, issues, fixes, evidence, and remaining risk.
