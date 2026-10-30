#!/usr/bin/env bash
# Can this repo use an open-model implementer via OpenCode? Prints OK, or NO lines with reasons (exit 1).
# Usage: oc_check.sh <model> <repo path>   e.g. oc_check.sh opencode/glm-5.3-flash-free {{PROJECTS}}/notes
set -uo pipefail
model=$1
repo=$(cd "$2" && pwd -P) || { echo "NO repo path not found: $2"; exit 1; }
fail=0
no() { echo "NO $*"; fail=1; }

# Only models listed in oc_models.txt (each passed your own model eval) are allowed.
approved=$(dirname "$0")/oc_models.txt
grep -qx "$model" <(sed 's/[[:space:]]*#.*//' "$approved" 2>/dev/null) || no "model not in $approved (run the model eval first): $model"

case "$repo" in "{{PROJECTS}}/"*) ;; *) no "repo is not under {{PROJECTS}} (personal repos only): $repo" ;; esac
remote=$(git -C "$repo" remote get-url origin 2>/dev/null)
case "$remote" in *"github.com:{{OWNER}}/"* | *"github.com/{{OWNER}}/"*) ;; *) no "origin is not a {{OWNER}} repo: ${remote:-none}" ;; esac

command -v opencode >/dev/null || no "opencode not installed"
if command -v opencode >/dev/null; then
  opencode models 2>/dev/null | grep -qx "$model" || no "model $model not listed by opencode (free period may have ended)"
fi

# The model reads the whole worktree and sends it to the provider: refuse if tracked secrets are present.
secrets=$(git -C "$repo" ls-files 2>/dev/null | grep -E '(^|/)\.env(\.[a-z]+)?$|\.(pem|key|p12|pfx)$|(^|/)id_(rsa|ed25519|ecdsa)$|(^|/)credentials\.json$|(^|/)service-account[^/]*\.json$' | grep -vE '\.env\.(example|template|sample)$')
[ -z "$secrets" ] || no "tracked files that look secret: $(echo "$secrets" | tr '\n' ' ')"

if [ $fail -eq 0 ]; then
  d=$(mktemp -d); start=$(date +%s)
  (cd "$d" && opencode run -m "$model" "Reply with exactly: OK" > "$d/out" 2>&1) &
  pid=$!
  while kill -0 $pid 2>/dev/null && [ $(( $(date +%s) - start )) -lt 60 ]; do sleep 2; done
  if kill -0 $pid 2>/dev/null; then kill $pid 2>/dev/null; no "$model did not answer within 60s (stalled or rate-limited)"
  elif ! grep -q '^OK' "$d/out"; then no "$model answered unexpectedly: $(tail -1 "$d/out")"
  fi
fi

[ $fail -eq 0 ] && echo OK
exit $fail
