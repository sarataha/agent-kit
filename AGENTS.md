# agent-kit
My Claude Code skills and hooks.

## Layout
- `skills/`: one folder per skill (`SKILL.md` plus its scripts).
- `hooks/`: hook scripts and `settings.example.json` (the wiring for `~/.claude/settings.json`).
- `install.sh`: copies both into `~/.claude`, filling `{{OWNER}}` and `{{PROJECTS}}` from `~/.config/agent-kit/config.json`.
- `tests/`: unittest suites; `tests/fixtures/` holds sample plan specs.

## Commands
- Setup: `python3 -m pip install -r requirements-dev.txt && pre-commit install`
- Lint: `pre-commit run --all-files` (uses the pinned ruff; a different local `ruff` version can disagree with CI)
- Test: `python3 -m unittest discover -s tests`
- Run: `CLAUDE_DIR=$(mktemp -d) ./install.sh config.example.json`

## Exercise
Install into a temp dir (`CLAUDE_DIR=$(mktemp -d) ./install.sh config.example.json`), check no `{{OWNER}}` or `{{PROJECTS}}` is left in it, and run the changed script from there. Paste the output.

## Conventions
- Python 3 stdlib only; no runtime dependencies.
- No owner-specific values (GitHub user, home paths, employer) in shipped files: use `{{OWNER}}` and `{{PROJECTS}}`.
- Skills are instructions for agents: short, imperative, one place per rule.
- Editing this repo doesn't change the installed skills; rerun `./install.sh` to apply.

## Boundaries
- Sensitive paths (always human review): `hooks/` (they gate what agents may do), `skills/land/` (the merge-risk verdict).
- Test data: fixture specs in `tests/fixtures/` only. Never real customer data.

Required checks: lint, test
