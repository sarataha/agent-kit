#!/usr/bin/env bash
# Ensure the `keep dev` ruleset on <owner/repo>: dev can't be deleted or force-pushed.
# Not "require PR": the coordinator pushes specs and release records to dev directly.
# Usage: protect_dev.sh <owner/repo>. Prints created / updated / ok.
set -euo pipefail
repo=$1
body='{"name":"keep dev","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/dev"],"exclude":[]}},
 "rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "keep dev") | .id' | head -1)
if [ -z "$id" ]; then
  gh api -X POST "repos/$repo/rulesets" --input - <<<"$body" >/dev/null && echo created
  exit 0
fi
have=$(gh api "repos/$repo/rulesets/$id" --jq '[.enforcement, ([.rules[].type] | sort | join(","))] | join(" ")')
if [ "$have" = "active deletion,non_fast_forward" ]; then echo ok; exit 0; fi
gh api -X PUT "repos/$repo/rulesets/$id" --input - <<<"$body" >/dev/null && echo "updated (was: $have)"
