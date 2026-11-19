#!/usr/bin/env bash
# PostToolUse hook: format/validate edited files by extension.
# Reads tool input JSON from stdin. A missing tool is skipped silently; a file that fails to
# parse is reported on stderr with exit 2, the only way a PostToolUse hook reaches Claude.

f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] || [ ! -f "$f" ] && exit 0

# run <tool> <cmd...>: skip if <tool> is missing; on failure, show its last lines to Claude.
run() {
  command -v "$1" >/dev/null 2>&1 || return 0
  local out
  out=$("${@:2}" 2>&1) && return 0
  printf 'format-on-edit: %s failed on %s:\n%s\n' "$1" "$f" "$(tail -n 5 <<<"$out")" >&2
  exit 2
}

case "$f" in
  *.tf|*.tfvars)
    run terraform terraform fmt "$f"
    ;;
  *.go)
    run gofmt gofmt -w "$f"
    ;;
  *.py)
    run ruff ruff format "$f"
    ;;
  *.yml|*.yaml)
    # PyYAML is not stdlib: no validation without it.
    python3 -c 'import yaml' 2>/dev/null \
      && run python3 python3 -c 'import sys, yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$f"
    ;;
esac

exit 0
