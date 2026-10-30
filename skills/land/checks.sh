#!/usr/bin/env bash
# Mechanical risk checks for /land. Usage: checks.sh <pr> <owner/repo>
# Prints one "TRIGGER <kind>: <detail>" line per hit, "HARDBLOCK <kind>" for
# never-auto-merge categories, and "HEAD <sha>". Exit 0 always.
set -euo pipefail
pr=$1; repo=$2
owner=${repo%%/*}
here=$(cd "$(dirname "$0")" && pwd)
ghr() { "$here/../_forge/gh-rest.sh" "$1" "$repo" "${@:2}"; }

json=$(ghr pr "$pr")
pfiles=$(ghr pr-files "$pr" | jq -s 'add')
diff=$(ghr pr-diff "$pr")

echo "HEAD $(jq -r .head.sha <<<"$json")"
files=$(jq -r '.[].filename' <<<"$pfiles")
nfiles=$(jq 'length' <<<"$pfiles")
lines=$(jq '.additions + .deletions' <<<"$json")

hit() { grep -iE "$1" <<<"$files" | head -5 | paste -sd, - || true; }
trig() { [ -n "$2" ] && echo "TRIGGER $1: $2"; return 0; }
block() { [ -n "$2" ] && { echo "TRIGGER $1: $2"; echo "HARDBLOCK $1"; }; return 0; }

# Only the owner's own same-repo PRs can ever auto-merge.
author=$(jq -r .user.login <<<"$json")
[ "$author" != "$owner" ] && { echo "TRIGGER foreign-author: $author"; echo "HARDBLOCK foreign-author"; }
[ "$(jq -r .head.repo.full_name <<<"$json")" != "$repo" ] && { echo "TRIGGER fork: cross-repo PR"; echo "HARDBLOCK fork"; }

[ "$lines" -gt 400 ] || [ "$nfiles" -gt 15 ] && echo "TRIGGER size: $lines lines, $nfiles files"
trig migration "$(hit '(^|/)(migrations?|alembic|schema)(/|\.)|\.sql$|prisma/')"
trig ci "$(hit '^\.github/|(^|/)Dockerfile|\.pre-commit-config|(^|/)Makefile$|\.gitlab-ci|(^|/)(goreleaser|renovate|dependabot)')"
trig guardrails "$(hit '(^|/)(AGENTS|CLAUDE)\.md$|CODEOWNERS|\.golangci|eslint|ruff\.toml|pyproject\.toml|codecov|coverage')"
trig deps "$(hit '(^|/)(go\.(mod|sum)|package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.(toml|lock)|requirements.*\.txt|uv\.lock|poetry\.lock|Gemfile(\.lock)?)$')"
trig secrets "$(hit '(^|/)\.env|secret|credential|\.pem$|\.key$')"

# Whole path segments only; substrings like "plan" or "account" don't count.
seg() { echo "(^|/)($1)(/|[._-]|\$)"; }
block auth "$(hit "$(seg 'auth|authn|authz|login|sessions?|oauth|rbac|acl|permissions?|jwt|csrf|passwords?')")"
block billing "$(hit "$(seg 'billing|payments?|stripe|paddle|polar|lemonsqueezy|subscriptions?|invoices?|pricing|checkout|entitlements?')")"
block license "$(hit "$(seg 'licen[cs]e|licen[cs]ing')")"
block customer-data "$(hit "$(seg 'customers?|tenants?|pii|gdpr|user_?data')")"
# Agent kit and settings: an agent must never merge changes to its own guardrails.
block agent-kit "$(hit '^\.claude/|(^|/)(AGENTS|CLAUDE)\.md$')"

# Repo-declared sensitive paths, read from the BASE branch so a PR can't edit them away.
base=$(jq -r .base.ref <<<"$json")
agents=$(ghr file AGENTS.md "$base" 2>/dev/null || true)
sens=$(sed -n 's/^- Sensitive paths[^:]*: *//p' <<<"$agents" | tr ',' '\n' | tr -d '`' \
  | sed 's/^ *//; s/ *$//' | grep -v -e '^$' -e '^<' || true)
if [ -n "$sens" ]; then
  h=$(SENS="$sens" awk 'BEGIN{n=split(ENVIRON["SENS"],p,"\n")} {for(i=1;i<=n;i++) if(index($0,p[i])==1){print; next}}' <<<"$files" \
    | head -5 | paste -sd, - || true)
  block sensitive-path "$h"
fi

# Required checks (no branch protection on private free-plan repos): every name on the
# base branch's `Required checks:` line must have succeeded on this exact head SHA.
sha=$(jq -r .head.sha <<<"$json")
req=$(sed -n 's/^Required checks: *//p' <<<"$agents" | tr ',' '\n' | tr -d '`' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
if [ -z "$req" ]; then
  echo "TRIGGER required-checks: no 'Required checks:' line in AGENTS.md on $base"; echo "HARDBLOCK required-checks"
else
  runs=$(ghr checks "$sha")
  # Docs-only diffs match CI `paths-ignore` (`**/*.md`, `docs/**`): a check that never ran is fine, a failed one is not.
  docs_only=$(grep -vqE '(\.md$|^docs/)' <<<"$files" && echo 0 || echo 1)
  bad=$(while read -r name; do
    awk -v n="$name" '$1==n && $2=="completed" && $3=="success"{ok=1} END{exit !ok}' <<<"$runs" && continue
    [ "$docs_only" = 1 ] && ! awk -v n="$name" '$1==n{f=1} END{exit !f}' <<<"$runs" && continue
    echo "$name"
  done <<<"$req" | paste -sd, - || true)
  [ "$docs_only" = 1 ] && echo "TRIGGER required-checks: docs-only diff; checks without a run accepted"
  block required-checks "${bad:+not successful on $sha: $bad}"
fi

# Weakened tests
deleted_tests=$(jq -r '.[] | select(.additions==0 and .deletions>0) | .filename' <<<"$pfiles" \
  | grep -iE '(_test\.|\.test\.|\.spec\.|(^|/)tests?/)' | paste -sd, - || true)
trig weakened-tests "${deleted_tests:+deleted/emptied: $deleted_tests}"
rm_assert=$(grep -cE '^-[^-].*\b(assert|expect|require\.|t\.(Error|Fatal)|should)' <<<"$diff" || true)
add_assert=$(grep -cE '^\+[^+].*\b(assert|expect|require\.|t\.(Error|Fatal)|should)' <<<"$diff" || true)
[ "$rm_assert" -gt "$add_assert" ] && echo "TRIGGER weakened-tests: assertions -$rm_assert +$add_assert"
skips=$(grep -E '^\+[^+]' <<<"$diff" | grep -cE '\b(t\.Skip|\.skip\(|\.only\(|xit\(|xdescribe|@pytest\.mark\.(skip|xfail)|@Disabled|#\[ignore\]|nolint|eslint-disable|type: ?ignore|noqa)' || true)
[ "$skips" -gt 0 ] && echo "TRIGGER weakened-tests: $skips added skip/ignore/disable markers"
exit 0
