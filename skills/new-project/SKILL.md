---
name: new-project
description: Scaffold a new personal project repo under {{OWNER}} with AGENTS.md, CI (lint + test, actions pinned to SHAs), pre-commit, Dependabot, branch protection, and seeded fake data. Paid repos are private. Use when the user runs /new-project or starts a new repo in {{PROJECTS}}.
---

# /new-project

## 1. Ask (one message)

Name, one-line purpose, language/stack, **OSS or paid** (open-core: public core repo + private paid repo), license for OSS (default Apache-2.0).

Show the plan (repo name, visibility, files) and get a yes before creating anything on GitHub.

## 2. Create

- `gh repo create {{OWNER}}/<name> --private|--public --clone` into `{{PROJECTS}}/<name>`. Paid → always `--private`.
- `gh repo edit --delete-branch-on-merge --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false`.

## 3. Files

**`AGENTS.md`** (agents.md format, short, specific to this repo):
```
# <name>
<one-line purpose>. Audience: <who>. <OSS | Paid (private)>.

## Commands
setup: <cmd>   lint: <cmd>   test: <cmd>   run: <cmd>   seed: <cmd>

## Exercise
<how to run the app locally and hit a changed path>

## Conventions
<only what a linter can't enforce>

## Boundaries
- Sensitive paths (always human review): <auth/billing/license/customer-data dirs>
- Test data: seeded fake data only (`<seed cmd>`, fixed seed). Never real customer data.

Required checks: lint, test
```
`Required checks:` lists the CI job names `/land` must see succeed on the exact head SHA (GitHub Free can't enforce this on private repos).

**`CLAUDE.md`**: single line `@AGENTS.md` (Claude Code reads CLAUDE.md, not AGENTS.md).

**`.github/workflows/ci.yml`**: on `pull_request` + push to `main`; `permissions: contents: read`; jobs `lint` and `test` using the AGENTS.md commands. Every `uses:` pinned to a full commit SHA with the version as a comment:
```
uses: actions/checkout@<40-char-sha> # v<x.y.z>
```
Resolve the latest release: `tag=$(gh api repos/<owner>/<action>/releases/latest -q .tag_name)` then `gh api repos/<owner>/<action>/commits/$tag -q .sha`.

**`.github/dependabot.yml`**: weekly updates for `github-actions` plus the stack's package ecosystem (keeps SHA pins current).

**`.pre-commit-config.yaml`**: the stack's formatter + linter, `gitleaks`, `check-merge-conflict`, `end-of-file-fixer`, `trailing-whitespace`. `rev:` pinned to latest release SHA. Run `pre-commit install && pre-commit run --all-files`.

**Seed + fixtures**: a seed script with a fixed random seed generating fake data (Faker or equivalent). CI test job uses it. Fake domains only (`example.com`), no real-looking secrets.

**Also**: `.gitignore` (incl. `.env*`), `.env.example`, `README.md` (what, quickstart), `LICENSE` (OSS only), `SECURITY.md` (OSS only). Minimal hello-world app + one passing test so CI is green.

Deps: stdlib first; else latest stable, verified not deprecated.

**`.claude/settings.json`**: `{"attribution": {"sessionUrl": false}}`.

## 4. Push + protect

- Commit `chore: scaffold project`, push to `main`, wait for CI green.
- Protect `main`: require PR, require `lint` + `test` checks, no force push, `enforce_admins: true` (agents push as you, an admin; without it they can bypass protection):
  `gh api -X PUT repos/{{OWNER}}/<name>/branches/main/protection --input <json>` (private repos on free plan may not support it; report if so).

- Label: `gh label create needs-human --force` (`/land` adds it to PRs that need review).

## 5. Report

Repo URL, visibility, CI status. Next: `/shape <first feature>`, then `/ship <repo> <slug>`.
