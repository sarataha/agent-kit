#!/usr/bin/env bash
# Install the kit into ~/.claude (skills/ and hooks/), filling {{OWNER}} and {{PROJECTS}} from the config.
# Usage: ./install.sh [config.json]   default config: ~/.config/agent-kit/config.json
# CLAUDE_DIR overrides the target (default ~/.claude). Re-running updates what this script installed;
# a skill folder it didn't install is skipped, and a different existing hook is kept as <name>.bak.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cfg=${1:-$HOME/.config/agent-kit/config.json}
[ -f "$cfg" ] || { echo "no config at $cfg: copy config.example.json there and edit it" >&2; exit 2; }
read_cfg() { python3 -c 'import json, os, sys; print(os.path.expanduser(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$cfg" "$1"; }
owner=$(read_cfg github_owner)
projects=$(read_cfg projects_dir)
dest=${CLAUDE_DIR:-$HOME/.claude}

mkdir -p "$dest/skills" "$dest/hooks"
for d in "$here"/skills/*/; do
  name=$(basename "$d")
  out="$dest/skills/$name"
  if [ -e "$out" ] && [ ! -f "$out/.agent-kit" ]; then
    echo "skip skill $name: $out exists and was not installed by agent-kit" >&2
    continue
  fi
  rm -rf "$out"
  cp -R "$d" "$out"
  touch "$out/.agent-kit"
  grep -rlE '\{\{(OWNER|PROJECTS)\}\}' "$out" | while read -r f; do
    OWNER=$owner PROJECTS=$projects perl -pi -e 's/\{\{OWNER\}\}/$ENV{OWNER}/g; s/\{\{PROJECTS\}\}/$ENV{PROJECTS}/g' "$f"
  done || true
  echo "skill $name"
done

for h in "$here"/hooks/*.sh; do
  out="$dest/hooks/$(basename "$h")"
  if [ -f "$out" ] && ! cmp -s "$h" "$out"; then cp "$out" "$out.bak"; fi
  cp "$h" "$out"
  chmod +x "$out"
  echo "hook $(basename "$h")"
done

echo "Done. Merge hooks/settings.example.json into $dest/settings.json to turn the hooks on."
