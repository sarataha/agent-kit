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

- Acceptance tests are written by a different agent than the code, committed first, and protected: `hooks/acceptance-guard.sh` blocks edits to them, `hooks/acceptance-stop.sh` runs them before a session may stop, and `/land` diffs them against the baseline commit.
- Review is never done by the session that wrote the code.
- `/land` hard-blocks on auth, billing, license, customer-data and agent-config paths, foreign authors and forks.
- `hooks/scan-output.sh` flags hidden bidi/zero-width characters and known injection or exfiltration markers in content the agent reads.
- Agents never merge to `main` or post PR comments on their own.
- `/run-project` can give clear, no-risk slices to a free model via [OpenCode](https://opencode.ai). It can only edit the slice's files; Claude tests and opens the PR.

## Setup on a new machine

```sh
cp config.example.json ~/.config/agent-kit/config.json   # owner and projects folder
./install.sh
```

Then merge `hooks/settings.example.json` into `~/.claude/settings.json`. `/plan-project` and `/shape` also use `grilling`, `domain-modeling`, `codebase-design` and `prototype` from [mattpocock/skills](https://github.com/mattpocock/skills) (`npx skills add https://github.com/mattpocock/skills --skill <name>`).
