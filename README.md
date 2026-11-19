# agent-kit

Experimental Claude Code setup for running coding agents mostly on their own.

## Flow

Small changes:

```
/shape <idea>          validate, spar on scope, write specs/<slug>.md
/ship <repo> <slug>    acceptance tests by a separate agent, implement, exercise, PR, independent review
/guard <repo>#<pr>     loop on CI, review comments and rebases until green
/land <repo>#<pr>      mechanical checks + fresh-context risk verdict
```

Multi-slice projects:

```
/plan-project <repo> <project>   grill, architecture, slice specs with dependencies and file ownership
/run-project <repo> <project>    parallel slice agents in worktrees, PRs into dev, integration check
                                 after each merge, one release PR dev → main
```

`/new-project` scaffolds a repo with AGENTS.md, CI (actions pinned to SHAs), pre-commit, Dependabot and branch protection.

## Guardrails

- Acceptance tests are written by a different agent than the code, committed first, and protected: `hooks/acceptance-guard.sh` blocks edits to them and to the marker that lists them, `hooks/acceptance-stop.sh` runs them before a session may stop, and `/land` takes the test commit from git history (not from the marker) and diffs the tests against it.
- Rules that judge a change are read from the base branch, never the PR: `AGENTS.md` (required checks, sensitive paths) and `REVIEW.md` (what reviewers check). A PR touching them is a hard block.
- Review is never done by the session that wrote the code. Findings are tagged Important / Nit / Pre-existing; re-review covers only new commits; max 2 rounds.
- `/land` hard-blocks on auth, billing, license, customer-data and agent-config paths, foreign authors and forks.
- `hooks/scan-output.sh` flags hidden bidi/zero-width characters and known injection or exfiltration markers in content the agent reads.
- Agents never merge to `main` or post PR comments on their own.
- `/run-project` can give clear, no-risk slices to a free model via [OpenCode](https://opencode.ai). It can only edit the slice's files; Claude tests and opens the PR.

## Setup on a new machine

```sh
cp config.example.json ~/.config/agent-kit/config.json   # owner and projects folder
./install.sh --wire-hooks
```

`--wire-hooks` adds the hooks in `hooks/settings.example.json` to `~/.claude/settings.json` (the old file is kept as `settings.json.bak`); without it, merge them by hand. `/plan-project` and `/shape` also use `grilling`, `domain-modeling`, `codebase-design` and `prototype` from [mattpocock/skills](https://github.com/mattpocock/skills) (`npx skills add https://github.com/mattpocock/skills --skill <name>`).

## Cloud sessions

Claude Code cloud sessions don't get your `~/.claude`, so the skills and hooks are missing there and `/ship` warns that the acceptance tests are protected only by `/land`. To have them, add agent-kit to the cloud environment's repositories and install it in the environment's setup script (it runs as root before Claude starts; sessions without agent-kit skip it):

```sh
if [ -d agent-kit ]; then
  printf '{"github_owner": "<you>", "projects_dir": "%s"}\n' "$PWD" > /tmp/agent-kit.json
  agent-kit/install.sh --wire-hooks /tmp/agent-kit.json
fi
```

## Checking the checks

- New repos get a `verify` skill (the smoke test agents run before committing) and a `REVIEW.md`; review misses become `REVIEW.md` lines (`skills/_forge/workflow.md`, "Drift → guardrail").
- `/land` appends each verdict to `~/.claude/land-log.tsv`. A PR reverted or fixed after a `low` verdict is a miss: replay `/land` on that SHA when you change it.
- `/ship` and `/run-project` commits carry a `Verified:` trailer, so `git log --grep 'Verified: tests; not exercised'` finds what was never run.
