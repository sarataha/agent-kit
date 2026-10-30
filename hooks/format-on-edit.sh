#!/usr/bin/env bash
# PostToolUse hook: format/validate edited files by extension.
# Reads tool input JSON from stdin; failures are silent.

f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] || [ ! -f "$f" ] && exit 0

case "$f" in
  *.tf|*.tfvars)
    terraform fmt "$f" >/dev/null 2>&1
    ;;
  *.go)
    gofmt -w "$f" 2>/dev/null
    ;;
  *.py)
    ruff format "$f" >/dev/null 2>&1
    ;;
  *.yml|*.yaml)
    python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$f" 2>&1
    ;;
esac

exit 0
