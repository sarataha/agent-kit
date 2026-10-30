#!/usr/bin/env bash
# REST-only GitHub helpers for the forge skills (ship/guard/land).
# Cloud sessions block GraphQL, so `gh pr` / `gh issue` fail there; `gh api` REST works everywhere.
# Usage: gh-rest.sh <cmd> <owner/repo> [args]
set -euo pipefail
cmd=$1; repo=$2; shift 2
api() { gh api -H "Accept: application/vnd.github+json" "$@"; }

case $cmd in
  # get|GET <owner/repo> <path>: any read-only GET; path may be full (repos/...) or relative to the repo
  get|GET)          p=${1#/}; case $p in repos/*|users/*|search/*) ;; *) p="repos/$repo/$p" ;; esac; api --paginate "$p" ;;
  issue)            api "repos/$repo/issues/$1" ;;
  issue-comments)   api --paginate "repos/$repo/issues/$1/comments" ;;
  pr)               api "repos/$repo/pulls/$1" ;;
  pr-files)         api --paginate "repos/$repo/pulls/$1/files" ;;
  pr-diff)          gh api -H "Accept: application/vnd.github.diff" "repos/$repo/pulls/$1" ;;
  # pr-create <head> <base> <title> <body-file>
  pr-create)        api -X POST "repos/$repo/pulls" -f head="$1" -f base="$2" -f title="$3" -F body=@"$4" ;;
  pr-edit-body)     api -X PATCH "repos/$repo/pulls/$1" -F body=@"$2" ;;
  # comment <issue-or-pr> <body-file>
  comment)          api -X POST "repos/$repo/issues/$1/comments" -F body=@"$2" ;;
  review-comments)  api --paginate "repos/$repo/pulls/$1/comments" ;;
  # reply <pr> <comment-id> <body-file>
  reply)            api -X POST "repos/$repo/pulls/$1/comments/$2/replies" -F body=@"$3" ;;
  reviews)          api --paginate "repos/$repo/pulls/$1/reviews" ;;
  # checks <sha>: check runs + legacy statuses, one line each: <name> <status> <conclusion> <id>
  checks)           api --paginate "repos/$repo/commits/$1/check-runs" -q '.check_runs[] | "\(.name) \(.status) \(.conclusion // "-") \(.id)"'
                    api "repos/$repo/commits/$1/status" -q '.statuses[] | "\(.context) completed \(.state) -"' ;;
  job-log)          api "repos/$repo/actions/jobs/$1/logs" ;;
  run-of-job)       api "repos/$repo/actions/jobs/$1" -q .run_id ;;
  rerun-failed)     api -X POST "repos/$repo/actions/runs/$1/rerun-failed-jobs" ;;
  add-label)        api -X POST "repos/$repo/issues/$1/labels" -f "labels[]=$2" ;;
  file)             api "repos/$repo/contents/$1?ref=$2" -q .content | base64 -d ;;
  # merge <pr> <sha>: squash-merge only if head is still <sha>
  merge)            api -X PUT "repos/$repo/pulls/$1/merge" -f merge_method=squash -f sha="$2" ;;
  *) echo "unknown cmd: $cmd" >&2; exit 2 ;;
esac
