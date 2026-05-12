#!/usr/bin/env bash
set -Eeuo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills=(
  deep-interview
  analyze
  ralplan
  ralph-execute
  ralph-qa
  visual-ralph-qa
  code-review
  tmux-worker-watch
)

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

note() {
  printf '[validate] %s\n' "$1"
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"

note "checking required files"
for skill in "${skills[@]}"; do
  [[ -f "$suite_root/$skill/SKILL.md" ]] || fail "missing $skill/SKILL.md"
  [[ -f "$suite_root/$skill/agents/openai.yaml" ]] || fail "missing $skill/agents/openai.yaml"
done

for ref in \
  references/harness-engineering-guide.md \
  references/goal-lifecycle-contract.md \
  ralplan/references/harness-contract.md \
  ralph-execute/references/execution-contract.md \
  ralph-qa/references/qa-contract.md \
  visual-ralph-qa/references/visual-qa-contract.md \
  code-review/references/review-contract.md \
  tmux-worker-watch/references/watch-contract.md; do
  [[ -f "$suite_root/$ref" ]] || fail "missing $ref"
done

note "running skill validator when available"
validator="$suite_root/.system/skill-creator/scripts/quick_validate.py"
if [[ -f "$validator" ]]; then
  for skill in "${skills[@]}"; do
    python3 "$validator" "$suite_root/$skill"
  done
else
  note "quick_validate.py not bundled; using metadata fallback checks"
fi

note "checking metadata, relative references, and length limits"
SUITE_ROOT="$suite_root" python3 - <<'PY'
from pathlib import Path
import os
import re

root = Path(os.environ["SUITE_ROOT"])
skills = [
    "deep-interview",
    "analyze",
    "ralplan",
    "ralph-execute",
    "ralph-qa",
    "visual-ralph-qa",
    "code-review",
    "tmux-worker-watch",
]

def parse_simple_mapping(text):
    data = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.match(r"\s*([A-Za-z0-9_-]+):\s*(.*)\s*$", line)
        if not match:
            continue
        key, value = match.groups()
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        data[key] = value
    return data

def parse_openai_interface(text):
    in_interface = False
    interface = {}
    for line in text.splitlines():
        if re.match(r"^interface:\s*$", line):
            in_interface = True
            continue
        if in_interface:
            if line and not line.startswith(" "):
                break
            match = re.match(r"\s+([A-Za-z0-9_-]+):\s*(.*)\s*$", line)
            if match:
                key, value = match.groups()
                value = value.strip()
                if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
                    value = value[1:-1]
                interface[key] = value
    return interface

for name in skills:
    skill_dir = root / name
    skill_md = skill_dir / "SKILL.md"
    text = skill_md.read_text()
    if len(text.splitlines()) > 500:
        raise SystemExit(f"{skill_md} exceeds 500 lines")

    match = re.match(r"---\n(.*?)\n---", text, re.S)
    if not match:
        raise SystemExit(f"{skill_md} is missing YAML frontmatter")
    frontmatter = parse_simple_mapping(match.group(1))
    if frontmatter.get("name") != name:
        raise SystemExit(f"{skill_md} name mismatch: {frontmatter.get('name')!r}")
    desc = frontmatter.get("description")
    if not isinstance(desc, str) or len(desc.strip()) < 80:
        raise SystemExit(f"{skill_md} description is too weak")

    openai_yaml = skill_dir / "agents" / "openai.yaml"
    interface = parse_openai_interface(openai_yaml.read_text())
    if not interface:
        raise SystemExit(f"{openai_yaml} is missing interface")
    for key in ("display_name", "short_description", "default_prompt"):
        value = interface.get(key)
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"{openai_yaml} missing interface.{key}")

    for rel in re.findall(r"`(\.\./references/[^`]+\.md)`", text):
        target = (skill_dir / rel).resolve()
        if not target.exists():
            raise SystemExit(f"{skill_md} references missing file: {rel} -> {target}")

print("metadata checks passed")
PY

note "checking release files for private local paths"
release_targets=(
  "$suite_root/RALPH_RELEASE_MANIFEST.md"
  "$suite_root/references"
  "$suite_root/scripts"
)
for skill in "${skills[@]}"; do
  release_targets+=("$suite_root/$skill/SKILL.md")
  [[ -d "$suite_root/$skill/references" ]] && release_targets+=("$suite_root/$skill/references")
  [[ -d "$suite_root/$skill/scripts" ]] && release_targets+=("$suite_root/$skill/scripts")
  [[ -d "$suite_root/$skill/agents" ]] && release_targets+=("$suite_root/$skill/agents")
done

private_home="${HOME%/}"
if [[ -n "$private_home" ]]; then
  if command -v rg >/dev/null 2>&1; then
    if rg -n -F "$private_home" "${release_targets[@]}"; then
      fail "current user's home path found in release files"
    fi
  else
    for target in "${release_targets[@]}"; do
      if grep -R -n -F "$private_home" "$target"; then
        fail "current user's home path found in release files"
      fi
    done
  fi
fi

note "checking shell scripts"
bash -n "$suite_root/ralph-execute/scripts/ralph_tmux_workers.sh"
bash -n "$suite_root/tmux-worker-watch/scripts/tmux_worker_watch.sh"
bash -n "$suite_root/scripts/e2e_ralph_release.sh"

[[ -x "$suite_root/ralph-execute/scripts/ralph_tmux_workers.sh" ]] || fail "ralph_tmux_workers.sh must be executable"
[[ -x "$suite_root/tmux-worker-watch/scripts/tmux_worker_watch.sh" ]] || fail "tmux_worker_watch.sh must be executable"
[[ -x "$suite_root/scripts/e2e_ralph_release.sh" ]] || fail "e2e_ralph_release.sh must be executable"

if command -v shellcheck >/dev/null 2>&1; then
  note "running shellcheck"
  shellcheck \
    "$suite_root/ralph-execute/scripts/ralph_tmux_workers.sh" \
    "$suite_root/tmux-worker-watch/scripts/tmux_worker_watch.sh" \
    "$suite_root/scripts/e2e_ralph_release.sh"
else
  note "shellcheck not found; skipped"
fi

note "release validation passed"
