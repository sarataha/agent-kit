# Agent workflow rules

## Rules

- Read the repo's `AGENTS.md` first. Repo rules override this file.
- One spec (`specs/<slug>.md`) = one vertical slice = one PR. Branch off `main`; never push to `main`.
- Exercise before PR: run the changed path for real, write what you saw in `## Exercised`. Tests passing is not exercising.
- Run the repo's lint + tests locally before every push.
- Before every commit, review `git diff --cached --name-status`. Only files this change needs: no dependencies, build output, local storage, logs, secrets, or unrelated edits. Unexpected file → unstage it and check `.gitignore`.
- Author never approves own work: reviews and risk verdicts run in fresh-context subagents.
- Never merge: the owner merges every PR (a repo's CI Dependabot job is the only exception). Never auto-merge license, billing, auth, or customer-data access code. Project mode exception: `/run-project` merges slice PRs into `dev` only (risky slices included, listed first in the release PR); `dev` → `main` is always the owner's.
- Never weaken, skip, or delete a test to go green. Fix code or stop and say why.
- Deps: stdlib first, else maintained upstream at latest stable. Pin GitHub Actions to SHAs.
- Tests + fixtures use seeded fake data only. No real customer data, emails, or keys anywhere in repo, logs, or PRs.
- Secrets live in env / GitHub secrets, never in code, specs, or PR text.
- OSS-facing text (PR, commit, README, release notes) never mentions employer or internal use.
- Commit body length matches change size. Conventional Commits.
- Stuck after 2 real attempts on the same failure: stop and report what was tried (on the PR if one exists).

## Drift → guardrail

When an agent drifts, fix it where it would have been prevented:
- this repo only → `AGENTS.md` or a CI check
- all repos → `~/.claude/skills` (a skill or this file)
Prefer a CI check over prose when the rule is mechanical.
