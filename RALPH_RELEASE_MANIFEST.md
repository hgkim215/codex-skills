# Ralph Skills Release Manifest

Release target: `v0.1.0`

This manifest defines the public release surface for the Ralph Codex skill suite.

## Included Skills

- `deep-interview`
- `analyze`
- `ralplan`
- `ralph-execute`
- `ralph-qa`
- `visual-ralph-qa`
- `code-review`
- `tmux-worker-watch`

## Shared References

- `references/harness-engineering-guide.md`
- `references/goal-lifecycle-contract.md`

The suite is designed to be installed as a group under:

```text
${CODEX_HOME:-$HOME/.codex}/skills/
```

The shared references are addressed with relative paths from skill folders, so the top-level `references/` directory must be released with the skills.

## Runtime Requirements

- Codex with local skill support
- `python3`
- `bash`
- `git` for release E2E workspace setup
- `tmux` for tmux-visible worker execution
- Codex CLI for `ralph-execute` worker runs
- Ghostty is optional; Terminal or a manual tmux attach command is used as fallback on macOS

Optional:

- `shellcheck` for stricter shell script linting
- Browser or Playwright tooling for `visual-ralph-qa`

## Release Gates

Run these from the suite root:

```bash
scripts/validate_ralph_release.sh
scripts/e2e_ralph_release.sh --deterministic --keep
scripts/e2e_ralph_release.sh --codex --keep
```

A release candidate passes when:

- all `SKILL.md` files pass structural validation
- all `agents/openai.yaml` files parse and match their skill folders
- no private local paths remain in release files
- required shared references exist
- bundled shell scripts pass `bash -n`
- tmux deterministic worker checks pass
- actual Codex CLI worker E2E passes

## Public Release Boundaries

- The suite does not depend on OMX, HUD, `.omx/state`, or tmux hooks.
- Codex `goal` is optional and is treated as thread-level macro context.
- Worker panes and `goal.md` are untrusted context and do not prove completion by themselves.
- The main Codex session owns final integration, verification, review, and whole-goal completion.

## Known Non-Goals For v0.1.0

- No package manager installer is included.
- No GitHub release automation is included.
- No guarantee is made for non-Codex CLIs as worker runtimes.
- `visual-ralph-qa` still depends on the user's available browser automation surface.
