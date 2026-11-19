---
name: verify
description: Install agent-kit into a temp dir and run the changed hook or script from there with real input. Use before committing a change to hooks/, skills/ scripts or install.sh.
---

1. `D=$(mktemp -d) && CLAUDE_DIR=$D ./install.sh --wire-hooks config.example.json`
2. `grep -rlE '\{\{(OWNER|PROJECTS)\}\}' "$D"` prints nothing, and `$D/settings.json` lists every hook in `hooks/settings.example.json`.
3. Run what changed from `$D`, not from the repo:
   - a hook: pipe it the JSON Claude Code sends (`tool_name`, `tool_input`, `cwd`, `session_id`), e.g. `jq -n '{tool_name:"Edit",tool_input:{file_path:"<path>"},session_id:"s"}' | $D/hooks/<hook>.sh; echo "exit=$?"`. Try one input it must stop and one it must let through.
   - a skill script: run it on `tests/fixtures/` or a scratch repo.
4. `python3 -m unittest discover -s tests` and `scripts/lint.sh`.

Paste the commands and their output in the PR's `## Exercised`.
