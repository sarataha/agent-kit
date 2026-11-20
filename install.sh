#!/usr/bin/env bash
# Install the kit into ~/.claude (skills/ and hooks/), filling {{OWNER}} and {{PROJECTS}} from the config.
# Usage: ./install.sh [--wire-hooks] [config.json]   default config: ~/.config/agent-kit/config.json
# CLAUDE_DIR overrides the target (default ~/.claude). Re-running updates what this script installed;
# a skill folder it didn't install is skipped, and a different existing hook is kept as <name>.bak.
# --wire-hooks also merges hooks/settings.example.json into <target>/settings.json (old file kept as
# settings.json.bak-<time>); a hook already wired under any path to the same script is not added again.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
wire=0
cfg=""
for a in "$@"; do
  case "$a" in
    --wire-hooks) wire=1 ;;
    -*) echo "unknown option $a. Usage: ./install.sh [--wire-hooks] [config.json]" >&2; exit 2 ;;
    *) [ -z "$cfg" ] || { echo "one config file only. Usage: ./install.sh [--wire-hooks] [config.json]" >&2; exit 2; }
       cfg=$a ;;
  esac
done
cfg=${cfg:-$HOME/.config/agent-kit/config.json}
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

if [ "$wire" = 0 ]; then
  echo "Done. Run again with --wire-hooks (or merge hooks/settings.example.json into $dest/settings.json) to turn the hooks on."
  exit 0
fi
# Add each hook group whose scripts aren't already wired for that event; leave everything else as it is.
# Commands point at the hooks in $dest: `$HOME/.claude` stays as written for the default target.
python3 - "$here/hooks/settings.example.json" "$dest" <<'PY'
import json, os, shlex, shutil, sys, time
src, dest = sys.argv[1], sys.argv[2]
dst = os.path.join(dest, "settings.json")
default = os.path.realpath(os.path.expanduser("~/.claude"))
def script(cmd):
    try:
        return os.path.basename(shlex.split(cmd)[0])
    except (ValueError, IndexError):
        return cmd
def target(cmd):
    p = "$HOME/.claude/"
    if cmd.startswith(p) and os.path.realpath(dest) != default:
        return shlex.quote(os.path.join(os.path.abspath(dest), cmd[len(p):]))
    return cmd
want = json.load(open(src))["hooks"]
have = json.load(open(dst)) if os.path.exists(dst) else {}
hooks = have.setdefault("hooks", {})
added = 0
for event, groups in want.items():
    cur = hooks.setdefault(event, [])
    wired = {script(h.get("command", "")) for g in cur for h in g.get("hooks", [])}
    for g in groups:
        if {script(h["command"]) for h in g["hooks"]} <= wired:
            continue
        g = {**g, "hooks": [{**h, "command": target(h["command"])} for h in g["hooks"]]}
        cur.append(g)
        added += 1
if not added:
    print("settings.json: hooks already wired")
    sys.exit(0)
if os.path.exists(dst):
    bak = f"{dst}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy(dst, bak)
    print(f"settings.json: old file kept as {bak}")
with open(dst, "w") as f:
    json.dump(have, f, indent=2)
    f.write("\n")
print(f"settings.json: {added} hook group(s) added")
PY
echo "Done."
