#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

skills=(
  cross-verify
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
  printf '[validate-release] %s\n' "$1"
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"

note "checking plugin and marketplace metadata"
python3 -m json.tool "$repo_root/.codex-plugin/plugin.json" >/dev/null
python3 -m json.tool "$repo_root/.agents/plugins/marketplace.json" >/dev/null

note "checking skill folders"
for skill in "${skills[@]}"; do
  [[ -f "$repo_root/$skill/SKILL.md" ]] || fail "missing $skill/SKILL.md"
  [[ -f "$repo_root/$skill/README.md" ]] || fail "missing $skill/README.md"
  [[ -f "$repo_root/$skill/agents/openai.yaml" ]] || fail "missing $skill/agents/openai.yaml"
done

note "checking skill metadata"
REPO_ROOT="$repo_root" python3 - <<'PY'
from pathlib import Path
import os
import re

root = Path(os.environ["REPO_ROOT"])
skills = [
    "cross-verify",
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
    skill_md = root / name / "SKILL.md"
    text = skill_md.read_text()
    match = re.match(r"---\n(.*?)\n---", text, re.S)
    if not match:
        raise SystemExit(f"{skill_md} missing frontmatter")
    frontmatter = parse_simple_mapping(match.group(1))
    if frontmatter.get("name") != name:
        raise SystemExit(f"{skill_md} name mismatch: {frontmatter.get('name')!r}")
    desc = frontmatter.get("description")
    if not isinstance(desc, str) or len(desc.strip()) < 60:
        raise SystemExit(f"{skill_md} description is too weak")

    openai_yaml = root / name / "agents" / "openai.yaml"
    interface = parse_openai_interface(openai_yaml.read_text())
    if not interface:
        raise SystemExit(f"{openai_yaml} missing interface")
    for key in ("display_name", "short_description", "default_prompt"):
        value = interface.get(key)
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"{openai_yaml} missing interface.{key}")

print("all skill metadata passed")
PY

note "checking release files for private local paths"
release_targets=(
  "$repo_root/.agents"
  "$repo_root/.codex-plugin"
  "$repo_root/README.md"
  "$repo_root/RALPH_RELEASE_MANIFEST.md"
  "$repo_root/references"
  "$repo_root/scripts"
)
for skill in "${skills[@]}"; do
  release_targets+=("$repo_root/$skill")
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
bash -n "$repo_root/cross-verify/scripts/cross_verify_tmux.sh"
bash -n "$repo_root/ralph-execute/scripts/ralph_tmux_workers.sh"
bash -n "$repo_root/tmux-worker-watch/scripts/tmux_worker_watch.sh"
bash -n "$repo_root/scripts/validate_ralph_release.sh"
bash -n "$repo_root/scripts/e2e_ralph_release.sh"

note "running Ralph release validation"
"$repo_root/scripts/validate_ralph_release.sh"

note "release validation passed"
