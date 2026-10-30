# Agent briefs for /run-project

Fill `<...>` and pass pointers, not file contents. Every agent's `description` is `<project> <NN> <role>`, space-separated: project = folder slug (no spaces), NN = slice number or `-` when not tied to one slice, role = a heading below. Examples: `ledger 03 implementer`, `ledger - final-review`. `usage.py` groups by it. Don't set the Agent `name` field (with agent teams on, a named agent becomes a teammate).

Start every brief with the COMMON block (plus READ-ONLY for reviewer, spec-check and final-review), then the role brief.

## COMMON (every agent)

> Repo: ONLY `{{PROJECTS}}/<repo>` (GitHub `{{OWNER}}/<repo>`). Never read or run anything in another repo, even if your shell starts there. Your shell's working directory is elsewhere: use absolute paths and `git -C <path>`, or `cd <path> && ...` inside one command. Create and edit files with the Edit and Write tools, never shell writes (no heredocs, `sed -i`, redirects into files). If any tool call is denied, stop and report it; don't work around it. Stage files explicitly; never `git add -A` or `--no-verify`. No token or usage figures anywhere. Your final reply must be the real, complete report, never a placeholder.

## READ-ONLY (reviewer, spec-check, final-review)

> Read-only: never commit, check out, switch or detach anything in any checkout or worktree. To run code, export it: `git -C {{PROJECTS}}/<repo> archive <ref> | tar -x -C <new mktemp dir>`. Don't post anything on the PR.

## test-writer (model `sonnet`)

> Worktree `<wt>` on branch `<branch>` (from `origin/dev`). Write failing tests for `specs/<project>/<NN>-<slug>.md`, one or more per Acceptance item, from the spec text and `specs/<project>/architecture.md` only. Also cover every Review focus line in architecture.md pinned to slice `<NN>`, at this slice's own seam (not only via other commands). Tests go through the test seam named in architecture.md, only in files the slice's `Owns:` line lists. Read `AGENTS.md` and existing tests for conventions. Expected values are typed from the spec, never computed the way the code would; assert full output, not substrings, where the spec pins it. Don't implement. Run them; confirm they fail for the missing behaviour, not import or syntax errors, and existing tests still pass. Run the repo's lint. Commit as `test: acceptance tests for <project> <NN>-<slug>` and push. Reply: test file paths, the runner files (test runner config and the file defining the test command; `none` for stdlib unittest with no config), the command that runs only them, the commit SHA, test names mapped to Acceptance items, and any spec-vs-architecture contradiction you notice.

## implementer (model `sonnet`; `opus` when the slice's Risk is not none)

> Worktree `<wt>`, branch `<branch>`, base `dev`. Implement `specs/<project>/<NN>-<slug>.md` using `specs/<project>/architecture.md` (interfaces, global constraints, owned paths) and `GLOSSARY.md` names. First write `<wt>/.claude/ship-acceptance.json` = `{"spec":"<project>/<NN>-<slug>","files":[<test files>],"runner":[<runner files>],"cmd":"<test cmd>","baseline":"<test commit>"}` (git-ignored; never commit it). Make the acceptance tests pass without editing them; touch only paths in `Owns:` (plus Decisions rows in the slice spec). Run the repo's lint with the version CI uses and the full tests (`AGENTS.md`). `git add` exactly the changed files, commit `feat: <project> <NN>-<slug>`. `git fetch origin && git merge origin/dev`, rerun lint and tests, then run the spec's Exercise for real and keep the exact output. Push and open a PR: `gh pr create --repo {{OWNER}}/<repo> --base dev --head <branch>` with body `Spec: specs/<project>/<NN>-<slug>.md`, then `## Summary`, `## Exercised` (commands + exact output), `## Risk`, `## Acceptance test edits` (none).
> Open question: small, reversible and inside this slice → safest default, a row under `## Decisions` in the slice spec in this PR, listed under `Defaults:`. Risky or shape-changing (auth, billing, license, customer data, migration, new dependency, shared interface or data model, spec contradiction, a wrong acceptance test, a path outside `Owns:`) → stop, push nothing new, reply `QUESTION: <question>` with options and a recommendation.
> Reply: PR URL, head SHA, `Defaults:` list, test results, anything you could not exercise.

## reviewer (model `sonnet`; `opus` when the slice's Risk is not none)

> Run the Skill tool with "code-review" at `medium` effort on the full PR URL `<PR URL>` and wait for its result before replying. Also check the code against `specs/<project>/architecture.md` (the slice's section, command contract, Global constraints, Review focus lines for `<NN>`). For risky slices, add an attacker pass: <risk-specific questions>. For a fix, also check what new input it accepts or rejects and what can now fail. For a repair PR, confirm it fixes the stated failure and nothing else. Reply: first line `REVIEWED <head sha you reviewed>`, then findings only, one line each with file:line, blocking / non-blocking, and the fix; or "no findings".

## spec-check (model `haiku`)

> For `<PR URL>` implementing `specs/<project>/<NN>-<slug>.md` (run `git -C <wt> fetch origin` first):
> 1. Each Acceptance item met: cite the test (file:line) or the exercised output in the PR body.
> 2. Tests from `<test commit>` unchanged: `git -C <wt> diff <test commit> origin/<branch> -- <test files>` is empty.
> 3. Only `Owns:` paths changed, plus the slice's own spec file: `gh pr diff <n> --repo {{OWNER}}/<repo> --name-only`.
> 4. Nothing from Out of scope built (`architecture.md` is binding for what a slice provides; Out of scope means commands and features).
> 5. Test quality: real behaviour through the seam with typed expected values, or restating the code? Name weak tests with file:line.
> First line `REVIEWED <head sha you checked>`, then one line per item: met / not met / unproven, with file:line. No praise.

## fixer (model `sonnet`; `opus` when the slice's Risk is not none)

> Worktree `<wt>`, branch `<branch>`, PR `<PR URL>`. Fix these findings: `<list>`. Don't edit the acceptance tests or paths outside `Owns:`; put tests for your fixes in a new file `<owned test path>`. For each fix, say whether it can create a new failure mode (exit codes, previously valid input now rejected, output changes) and test that case. Rerun lint, tests and the Exercise; commit (`fix: ...`), push. Don't edit the PR body or post comments. Reply: what you fixed, what you rejected and why, new head SHA.

## integration-fixer (model `sonnet`)

> `dev` at `<SHA>` fails after merging `<PR>`: `<failing command + output>`. Worktree `<wt>` on new branch `<project>-fix-<n>` from `origin/dev`. Find the cause and fix it in the smallest change, touching only `<paths the coordinator names>` plus one new test file `<path>` that fails without the fix. Never edit these acceptance test files: `<all merged slices' acceptance test files>`. Run lint, full tests, the journey steps for merged slices and the Regression journeys (`specs/<project>/plan.md`). PR into `dev` with the implementer body format. Reply: cause, PR URL, head SHA.

## final-review (model `opus`)

> Run the Skill tool with "code-review" at `high` effort on the release PR URL (or on `origin/main...origin/dev` in `{{PROJECTS}}/<repo>`, passing the repo path explicitly), and wait for it. Then an adversarial whole-codebase pass the per-slice reviews can't do: cross-slice consistency, shared error and output handling (pipes, encodings, control characters, huge inputs), docs vs code. Reply: findings most severe first with file:line, blocking / non-blocking, confirmed or unconfirmed, fix; then a verdict (merge as is / after fixes / don't merge).
