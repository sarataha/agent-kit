#!/usr/bin/env bash
# Stop: run the active build's acceptance tests; block the stop once if they fail.
# The build is found via the session's repo or ~/.claude/ship-active (written by /ship), so cwd does not matter.
# The pointer counts only for the session that wrote it (line 1: path, line 2: session=<id>).
input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input")
sid=$(jq -r '.session_id // empty' <<<"$input")
root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)
if [ ! -f "$root/.claude/ship-acceptance.json" ]; then
  root=""
  ptr=$(cat ~/.claude/ship-active 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$sid" ] && [ "$(sed -n '2s/^session=[[:space:]]*//p' <<<"$ptr")" = "$sid" ] && root=$(sed -n 1p <<<"$ptr")
fi
marker="$root/.claude/ship-acceptance.json"
[ -n "$root" ] && [ -f "$marker" ] || exit 0
again=$(jq -r '.stop_hook_active // false' <<<"$input")
cmd=$(jq -er '.cmd' "$marker" 2>/dev/null) || {
  # Block once, then let the session end so a broken marker can't trap it.
  [ "$again" = "true" ] && { jq -n --arg m "$marker" '{systemMessage: ("Acceptance marker unreadable: " + $m)}'; exit 0; }
  echo "Acceptance marker $marker is unreadable; restore it." >&2
  exit 2
}

out=$(cd "$root" && bash -c "$cmd" 2>&1) && exit 0
# Already blocked once this turn: let it stop, but say so.
if [ "$again" = "true" ]; then
  jq -n --arg r "$root" '{systemMessage: ("Acceptance tests still failing in " + $r + ".")}'
  exit 0
fi
printf 'Acceptance tests failing in %s (%s):\n%s\n' "$root" "$cmd" "$(tail -n 40 <<<"$out")" >&2
exit 2
