#!/usr/bin/env bash
# PreToolUse Edit|Write|MultiEdit|Bash: deny writes to acceptance tests listed in <repo>/.claude/ship-acceptance.json.
# Early warning only; /land's baseline diff is the real check.
input=$(cat)
deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}
tool=$(jq -r '.tool_name // empty' <<<"$input")

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
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      name=$(basename "$t" | sed 's/[][\.*^$/]/\\&/g')
      if grep -qE ">[[:space:]]*[^[:space:]]*$name" <<<"$cmd" || grep -qE "$name" <<<"$writes"; then
        deny "$t is an acceptance test for this spec. Do not change it, even from the shell. If it is wrong, stop and tell the owner."
      fi
    done <<<"$files"
  else
    abs="$(cd "$dir" && pwd -P)/${f#"$(dirname "$f")"/}"
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
