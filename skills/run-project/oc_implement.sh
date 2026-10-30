#!/usr/bin/env bash
# Run an open model (via OpenCode) as a slice implementer, locked to the slice's owned paths.
# Usage: oc_implement.sh <model> <worktree> <slice spec path> <log file> <acceptance test file>... [-- <owned path>...]
# Owned paths default to the spec's `Owns:` line (read from the worktree); `--` paths override it.
# Writes <worktree>/opencode.json (git-excluded): edit allowed only on owned paths and the slice spec,
# acceptance tests denied, no shell, no web, nothing outside the worktree. The model never commits:
# the coordinator reviews, tests, commits, pushes and opens the PR. Prints the final report.
set -euo pipefail
model=$1 wt=$2 spec=$3 log=$4; shift 4
tests=(); owns=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do tests+=("$1"); shift; done
[ "${1:-}" = "--" ] && shift
owns=("$@")
if [ ${#owns[@]} -eq 0 ]; then
  [ -f "$wt/$spec" ] || { echo "spec not found: $wt/$spec" >&2; exit 2; }
  line=$(grep -m1 '^Owns:' "$wt/$spec" | sed 's/^Owns:[[:space:]]*//' || true)
  IFS=',' read -r -a owns <<<"$line"
  for i in "${!owns[@]}"; do owns[i]=$(echo "${owns[$i]}" | xargs); done
fi
[ ${#owns[@]} -gt 0 ] && [ -n "${owns[0]}" ] || { echo "no owned paths (no Owns: line in $spec)" >&2; exit 2; }
echo "owned paths: ${owns[*]}" >&2

python3 - "$wt/opencode.json" "$spec" "${#tests[@]}" "${tests[@]}" "${owns[@]}" <<'PY'
import json, sys
out, spec, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
tests, owns = sys.argv[4:4 + n], sys.argv[4 + n:]
edit = {"*": "deny"}
for p in owns:
    edit[p.rstrip("/") + "/*" if p.endswith("/") else p] = "allow"
edit[spec] = "allow"
for t in tests:  # last match wins: acceptance tests stay denied even inside an owned folder
    edit[t] = "deny"
cfg = {
    "$schema": "https://opencode.ai/config.json",
    "permission": {"*": "deny", "read": "allow", "glob": "allow", "grep": "allow", "list": "allow",
                   "edit": edit, "bash": "deny", "webfetch": "deny", "external_directory": "deny"},
}
json.dump(cfg, open(out, "w"), indent=2)
PY
excl="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
mkdir -p "$(dirname "$excl")"
grep -qx 'opencode.json' "$excl" 2>/dev/null || echo 'opencode.json' >> "$excl"

prompt="Implement the slice spec ${spec} in this repository. First read AGENTS.md, the project's architecture.md next to the spec, the code the spec names, and the acceptance tests (${tests[*]}), and follow the existing patterns exactly. Make the acceptance tests pass WITHOUT editing them. You may only edit: ${owns[*]} (and add a row under ## Decisions in ${spec} for any small default you choose). You have no shell, so you cannot run tests: check your code against every test by reading carefully. Do not touch git. End with a short report: files changed, which test each part satisfies, defaults chosen, anything you are unsure about."
[ -n "${OC_FINDINGS:-}" ] && prompt="$prompt Your previous attempt failed checks; fix these: ${OC_FINDINGS}"
prompt=${OC_PROMPT:-$prompt}  # override only for guard-rail tests
mkdir -p "$(dirname "$log")"
start=$(date +%s); status=0
stall=${OC_STALL_SECS:-600}  # no new log output this long = stalled (free tiers can hang)
(cd "$wt" && exec opencode run -m "$model" --title "$(basename "$wt")-oc" "$prompt") > "$log" 2>&1 &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  sleep 5
  kill -0 "$pid" 2>/dev/null || break
  if [ $(( $(date +%s) - $(stat -f %m "$log") )) -ge "$stall" ]; then
    pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true
    echo "$model stalled: no output for ${stall}s, killed" >&2; status=124; break
  fi
done
if [ $status -eq 124 ]; then wait "$pid" 2>/dev/null || true; else wait "$pid" || status=$?; fi
echo "$model exit=$status secs=$(( $(date +%s) - start )) log=$log" >&2
# Report = the text after the last tool line. A tool line is ESC[0m<symbol> ESC[0m<tool>; its output
# (e.g. an edit's diff) runs until the next bare ESC[0m separator line.
E="$(printf '\033')[0m"
awk -v E="$E" '
  $0 == E { skip = 0; next }
  index($0, E) == 1 { r = index(substr($0, 5), E); if (r > 0 && r < 6) { buf = ""; skip = 1; next } }
  !skip { buf = buf $0 "\n" }
  END { printf "%s", buf }' "$log" | sed "s/$(printf '\033')\[[0-9;]*m//g"
exit $status
