#!/usr/bin/env bash
# PreToolUse Edit|Write|MultiEdit|Bash: deny writes to acceptance tests listed in <repo>/.claude/ship-acceptance.json,
# and to the marker itself: only its `reviewed` field may change (Edit/Write); shell writes to it are denied, `rm` is not.
# Early warning only: /land takes the tests from git history, not from the marker, and diffs them.
input=$(cat)
deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}
tool=$(jq -r '.tool_name // empty' <<<"$input")
# Exit 0 when an Edit/Write/MultiEdit of the marker (argv[1]) leaves every field but `reviewed` unchanged.
MARKER_EDIT_OK='
import json, sys
inp = json.load(sys.stdin)
ti = inp.get("tool_input") or {}
cur = open(sys.argv[1], encoding="utf-8").read()
if inp.get("tool_name") == "Write":
    new = ti.get("content", "")
else:
    new = cur
    for e in ti.get("edits") or [ti]:
        old, rep = e.get("old_string", ""), e.get("new_string", "")
        if not old or old not in new:
            sys.exit(1)  # no exact match: the tool may still match loosely (e.g. curly quotes), so we cannot check it
        new = new.replace(old, rep) if e.get("replace_all") else new.replace(old, rep, 1)
try:
    a, b = json.loads(cur), json.loads(new)
except ValueError:
    sys.exit(1)
if not isinstance(b, dict):
    sys.exit(1)
sys.exit(0 if all(a.get(k) == b.get(k) for k in ("spec", "files", "runner", "cmd", "baseline")) else 1)
'

if [ "$tool" = "Bash" ]; then
  cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
  dir=$(jq -r '.cwd // empty' <<<"$input")
else
  f=$(jq -r '.tool_input.file_path // empty' <<<"$input")
  [ -z "$f" ] && exit 0
  dir=$(dirname "$f")
  while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do dir=$(dirname "$dir"); done
fi
root=$(git -C "${dir:-.}" rev-parse --show-toplevel 2>/dev/null)
# Bash may run from outside the repo (e.g. `cd <worktree> && ...`): also check the active build.
roots=()
[ -n "$root" ] && roots+=("$root")
# The pointer counts only for the session that wrote it (line 1: path, line 2: session=<id>).
ptr=$(cat ~/.claude/ship-active 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
sid=$(jq -r '.session_id // empty' <<<"$input")
active=""
[ -n "$sid" ] && [ "$(sed -n '2s/^session=[[:space:]]*//p' <<<"$ptr")" = "$sid" ] && active=$(sed -n 1p <<<"$ptr")
[ "$tool" = "Bash" ] && [ -n "$active" ] && [ "$active" != "$root" ] && roots+=("$active")
[ ${#roots[@]} -eq 0 ] && exit 0

for r in "${roots[@]}"; do
  marker="$r/.claude/ship-acceptance.json"
  [ -f "$marker" ] || continue
  files=$(jq -er '.files[]' "$marker" 2>/dev/null) || deny "$marker is unreadable. Restore it before editing; acceptance tests are unprotected until then."
  rootp=$(cd "$r" && pwd -P)
  if [ "$tool" = "Bash" ]; then
    # Running, viewing and diffing are fine; a redirect into a listed file or a file-writing command naming it is not.
    # Writer commands only count when the file is named in the same segment (split on ; & |).
    # shellcheck disable=SC2020  # character sets on purpose: each of ; & | becomes a newline
    writes=$(tr ';&|' '\n\n\n' <<<"$cmd" | grep -E '^[[:space:]]*(sudo[[:space:]]+)?(tee|mv|rm|cp|truncate|sed[[:space:]].*-i|perl[[:space:]].*-i|git[[:space:]]+(checkout|restore|rm|mv))([[:space:]]|$)')
    # Inline code (python -c, node -e, bash -c, python3 - <<EOF, /usr/bin/python3 -c'...') can write anywhere and holds
    # ; itself, so it counts when the whole command names the file and contains a write call.
    interp='(^|[;&|(`[:space:]/])(python[0-9.]*|node|ruby|perl|bash|sh|zsh)'
    inline=0
    grep -qE "${interp}[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*[ce]|-)([[:space:]\"']|$)|${interp}([[:space:]][^;&|]*)?<<" <<<"$cmd" \
      && grep -qE "open\([^)]*['\"][rbt]*[wax+]|write|unlink|remove|rename|truncate|shutil|copy|move|rmSync|os\.replace|(^|[^[:alnum:]_-])(cp|mv|tee|sed|rm|dd)[[:space:]]|>[[:space:]]*[^&[:space:]]" <<<"$cmd" \
      && inline=1
    # writes_to <regex> <removal_ok>: a writer segment writes a path matching <regex>. cp counts only for its
    # destination; with removal_ok, rm and moving the file away don't count either.
    writes_to() {
      local seg verb
      while IFS= read -r seg; do
        [ -z "$seg" ] && continue
        verb=$(sed -E 's/^[[:space:]]*(sudo[[:space:]]+)?(git[[:space:]]+)?([a-z]+).*/\3/' <<<"$seg")
        case "$verb" in
          cp) awk '{print $NF}' <<<"$seg" | grep -qE "$1" && return 0 ;;
          mv) if [ "$2" = 1 ]; then awk '{print $NF}' <<<"$seg" | grep -qE "$1" && return 0
              else grep -qE "$1" <<<"$seg" && return 0; fi ;;
          rm) [ "$2" = 1 ] || { grep -qE "$1" <<<"$seg" && return 0; } ;;
          *) grep -qE "$1" <<<"$seg" && return 0 ;;
        esac
      done <<<"$writes"
      return 1
    }
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      name=$(basename "$t" | sed 's/[][\.*^$/]/\\&/g')
      if grep -qE ">[[:space:]]*[^[:space:]]*$name" <<<"$cmd" || writes_to "$name" 0 || { [ "$inline" = 1 ] && grep -qE "$name" <<<"$cmd"; }; then
        deny "$t is an acceptance test for this spec. Do not change it, even from the shell. If it is wrong, stop and tell the owner."
      fi
    done <<<"$files"
    # The marker: removing it is fine (/land doesn't trust it); rewriting it from the shell is not.
    mre='ship-acceptance\.json'
    if grep -qE ">[[:space:]]*[^[:space:]]*$mre" <<<"$cmd" || writes_to "$mre" 1 || { [ "$inline" = 1 ] && grep -qE "$mre" <<<"$cmd"; }; then
      deny "$marker records what protects the acceptance tests. Do not rewrite it from the shell; change only \`reviewed\`, with the Edit tool."
    fi
  else
    abs="$(cd "$dir" && pwd -P)/${f#"$(dirname "$f")"/}"
    if [ "$abs" = "$rootp/.claude/ship-acceptance.json" ]; then
      python3 -c "$MARKER_EDIT_OK" "$abs" <<<"$input" \
        || deny "Only \`reviewed\` may change in $marker; spec, files, runner, cmd and baseline are fixed once the tests are committed. If one is wrong, stop and tell the owner."
      continue
    fi
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      case "$t" in /*) cand="$t" ;; *) cand="$rootp/$t" ;; esac
      cand_dir=$(dirname "$cand")
      if [ -d "$cand_dir" ]; then
        cand="$(cd "$cand_dir" && pwd -P)/$(basename "$cand")"
      fi
      [ "$abs" = "$cand" ] && deny "$t is an acceptance test for this spec. Do not edit it. If it is wrong, stop and tell the owner."
    done <<<"$files"
  fi
done
exit 0
