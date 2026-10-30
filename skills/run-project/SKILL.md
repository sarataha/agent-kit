---
name: run-project
description: Build an approved /plan-project plan on a long-lived dev branch: parallel slice agents in worktrees, PRs merged into dev when checks pass, integration check after each merge, one release PR dev → main for the owner.
disable-model-invocation: true
---

# /run-project <repo> <project>

The session that runs this is the coordinator. It never writes feature code: background agents do, from [BRIEFS.md](BRIEFS.md). It works from any working directory: use absolute paths and `git -C {{PROJECTS}}/<repo>`, and give agents absolute worktree paths. Prefer a session started in `{{PROJECTS}}` (a session in a work repo files personal runs under it, and tools that default to the cwd hit the wrong repo). The coordinator merges reviewed slice PRs into `dev` only; `main` stays the owner's.

**Restarts.** After the session was reopened, compacted or replaced, a plain "continue" from the owner means: run step 1 and [RESUME.md](RESUME.md) before anything else. Trust git, GitHub and the status file, never memory of agents or results from before the restart.

**Terms.** *Candidate*: the exact commit a merge gate checks (the PR's `headRefOid` when the gate starts). *Release candidate*: the `dev` commit the release PR is frozen at. *Head*: a PR's current commit.

## 1. Preflight

`S=~/.claude/project-runs/<repo>-<project>` holds the status file `status.md` and `contract.json` (local, never in the repo). `CH=~/.claude/skills/plan-project/contract_hash.py`.

1. **Plan.** `specs/<project>/plan.md` says `Status: approved`; `python3 ~/.claude/skills/plan-project/check_plan.py <specs folder>` prints `OK`. Read `plan.md`, `architecture.md`, `AGENTS.md`.
2. **Specs folder.** Not on `dev` yet: `{{PROJECTS}}/<repo>/specs/<project>`. On `dev`: a fresh export, `X=$(mktemp -d) && git -C {{PROJECTS}}/<repo> archive origin/dev specs/<project> | tar -x -C "$X"`, folder `$X/specs/<project>`.
3. **Run state.**
   - No status file → new run: `python3 $CH snapshot <folder> $S/contract.json`; its output is `Contract:`.
   - Status file, not released → `python3 $CH check <folder> $S/contract.json`. `OK` → follow [RESUME.md](RESUME.md) before starting anything. `CHANGED <file>` → stop, tell the owner which files changed; after re-approval archive the status file to `status-<timestamp>.md` and start new. Exit 2 → stop and report. Old `Plan:` line, no `contract.json` → RESUME.md "Old status files".
   - Owner said "fresh" → archive the status file; list existing `<project>-*` worktrees, branches and open PRs; reuse them or leave them for the owner (never close PRs).
   - Previous run `released` → see Release lifecycle.
4. **Release freeze.** An open release PR `dev` → `main` whose head is this run's `Release candidate:` → resume in step 4 (owner-requested changes go through step 4.2); skip step 5. Any other open release PR → stop: `dev` is frozen until the owner merges it.
5. **`dev` holds `main`.** No `dev` on origin → `git push origin origin/main:refs/heads/dev`. Otherwise `dev` holds `main` when any of these is true:
   - `git merge-base --is-ancestor origin/main origin/dev`;
   - `main`'s tree is a `dev` commit's tree, a squash-merged release (record it, see Release lifecycle): `git log --format=%T origin/dev | grep -qx "$(git rev-parse 'origin/main^{tree}')"`;
   - `git merge-tree --write-tree origin/dev origin/main | head -1` equals `git rev-parse 'origin/dev^{tree}'`.

   None true → branch `sync-main-<date>` from `origin/dev`, `git merge origin/main` (conflicts: keep both intents, or stop for the owner), push, PR into `dev` titled `chore: sync main into dev`, step 2.6 repair gate, squash-merge.

   Then `~/.claude/skills/run-project/protect_dev.sh {{OWNER}}/<repo>` (`dev` can't be deleted or force-pushed). It fails (no admin rights, plan without rulesets) → tell the owner and continue.
6. **Open model still usable.** Plan says `Implementer: <model>` (not `claude`) → `~/.claude/skills/run-project/oc_check.sh <model> {{PROJECTS}}/<repo>`. `NO` → run every slice with the Claude implementer and tell the owner why (a free tier may have ended since planning). Re-check on resume.
7. **Specs on `dev`.** Not there yet → in a worktree of `dev`, `git add` exactly `specs/<project>/` and `GLOSSARY.md`, check no token or usage figures are in them, commit `docs: <project> specs`, push to `dev`.

After any merged PR that edits specs beyond appended Decisions rows (owner-approved acceptance edit, repair PR changing `architecture.md`): re-snapshot from `origin/dev` and log `Contract: <new hash> after <PR>`.

Status file header: `Contract:`, `Started:`, `Cap:`, `Budget:`, then metrics updated as the run goes: attempts used, retries (review/fix rounds beyond the first), owner interventions, escaped bugs (found after a slice merged: integration, final review, release review, owner), finished, elapsed. Usage stays in the usage file (step 5).

Done when: `dev` holds the specs and the status file has a row per slice (`pending`).

## 2. Run the frontier

Status per slice: `pending → tests → implementing → review → merging → merged`, or `failed`, `paused (question)`. Update the status file after every change, with branch, worktree, PR URL, test commit, runner files, reviewed SHA, attempt count, and every blocking finding with its state (`open`, `fixed <sha>`, `declined: <reason>`).

Frontier = `pending` slices whose `Depends on:` are all `merged`. Start frontier slices, oldest number first, while fewer than the cap (plan Run settings) are active. For each slice:

1. `git worktree add {{PROJECTS}}/<repo>/.claude/worktrees/<project>-<NN> -b <project>-<NN>-<slug> origin/dev` as its own command; confirm `git worktree list` shows it before starting any agent for the slice.
2. **test-writer** agent (background). Record test files, runner files (test runner config and the file defining the test script), command, test commit (the baseline). Verify yourself that the tests fail for the missing behaviour and existing tests pass.
3. **implementer** agent (background). Plan `Implementer: <model>` and the slice's Risk is `none` → that model instead (see Open-model implementer below).
   - `QUESTION:` reply → status `paused (question)`, its dependents wait, send the owner the question with options and a recommendation (PushNotification when available). Continue the other slices. The owner's answer → add a Decisions row to the slice spec, restart the implementer.
   - `Defaults:` → record them for the release PR.
4. **reviewer** and **spec-check** agents (background, in parallel), both given the PR's current head SHA. Each reply starts `REVIEWED <sha>`.
5. Blocking findings, a `not met` / `unproven`, or a changed acceptance test → **fixer** agent, then one more review round on the new head. Max 2 rounds. Cheap non-blocking findings may go to the same fixer. Record every declined finding with its reason (release PR).
6. Merge gate on the candidate, all of:
   - **CI:** `gh pr checks <pr> --watch` finished; then `gh api --paginate repos/<owner>/<repo>/commits/<candidate>/check-runs --jq '.check_runs[] | [.name, .conclusion, .started_at] | @tsv'`, keeping only the latest `started_at` per name (re-runs repeat names): every name on the `Required checks:` line of `AGENTS.md` on `dev` is `success` (no such line → every name is `success` and at least one ran). CI on that SHA, not the agent's local claim.
   - **Reviews:** the latest reviewer and spec-check `REVIEWED` SHA equals the candidate. Anything pushed after them → another review round on the new commits first (counts toward the 2 rounds).
   - **Findings:** no blocking finding `open` in the status file: each is `fixed <sha>` (confirmed by the later round) or `declined` with a reason.
   - **Acceptance:** `git diff <baseline> <candidate> -- <test files>` empty, or exactly an edit the owner approved. `git diff <baseline> <candidate> -- <runner files>` non-empty → the reviewer must confirm no acceptance test is excluded or skipped; record it.
   - **Ownership:** `gh pr diff <pr> --name-only` within `Owns:` plus the slice's own spec file (Decisions rows), or a path the coordinator directed and no other slice owns.
   - **Spec:** spec-check all `met`, or a `not met` the coordinator overrules with the reason recorded.
   - Then `gh pr merge <pr> --squash --delete-branch --match-head-commit <candidate>` into `dev`.
   - **Repair PRs** (integration fix, final fix, main→dev sync) use the same gate with these inputs: Owns = the paths named in the fixer's brief plus one new test file (sync: every path); Acceptance = every merged slice's acceptance test files unchanged by the PR (`git diff origin/dev...<candidate> -- <all acceptance test files>` empty, three dots: only the PR's own changes; sync: any change is listed for the owner instead); Reviews = a **reviewer** `REVIEWED <candidate>` that confirms the PR fixes the stated failure and nothing else (sync: that it brings only `main`'s changes and its conflict resolutions drop no `dev` work); no spec-check.
7. `git worktree remove --force` the slice worktree (after merge only temp files remain), then `git branch -D <branch>`. (`gh pr merge --delete-branch` deletes the remote branch but fails on the local one while its worktree exists; that error is expected.)

A slice whose implementer or merge gate fails twice → `failed`; its dependents stay `pending` and are reported, not started.

**Checkpoints.** Budget: at 50% and 75% of the plan's slice-attempt budget, tell the owner (attempts used, slices merged, what's left); at 100% stop starting slices, finish active ones, go to step 4. Plan `Checkpoints:` (Run settings, optional, e.g. `after 01`, `before release`) → at each, stop starting slices, report, wait for "continue". Owner says "pause" anytime → start nothing new, let active agents finish their current role, status `paused`; `/run-project` again resumes via [RESUME.md](RESUME.md).

### Open-model implementer

The model (via OpenCode) edits files only: no shell, no git. The coordinator does the rest.

1. Run `~/.claude/skills/run-project/oc_implement.sh <model> <wt> specs/<project>/<NN>-<slug>.md $S/<NN>-oc.log <acceptance test files from the status file>` (background Bash). It locks OpenCode to the spec's `Owns:` paths and the slice spec, denies the acceptance tests, and prints the model's report.
2. Stall: the script kills OpenCode after 10 minutes with no new log output and exits `124`; that is a stalled try.
3. Check the result: `git -C <wt> status` shows only owned paths; read the diff before running anything; run lint and the full suite on a copy (`rsync -a --exclude .git --exclude opencode.json <wt>/ <new temp dir>/`).
4. Failing → never fix it yourself. One more run of the same script with `OC_FINDINGS="<failing checks and output>"`. Two failed tries → a Claude **fixer**; a stalled try → the Claude implementer. The model's tries and that fixer together are one implementer attempt (the "fails twice" rule and the budget).
5. Green → `git add` exactly the changed owned paths and the slice spec; commit `feat: <project> <NN>-<slug>`; `git -C <wt> fetch origin && git -C <wt> merge origin/dev`; on a fresh copy rerun lint and the suite, then run the spec's Exercise and keep the exact output; push and open the PR with the implementer's `gh pr create` and body format (`## Exercised` = that output). Defaults in the model's report → `Defaults:`.

## 3. Integration check (after every merge)

In a worktree of the new `origin/dev`: the repo's lint and full test suite, then the Journey check steps whose slices are all `merged` (the `# NN` comments in `plan.md` name them), then every Regression journey (earlier milestones; they must keep passing). Record pass/fail per step with the `dev` SHA.

Fail → stop starting slices; **integration-fixer** agent once; its PR goes through the step 2.6 repair gate. Still failing → stop the run and report to the owner with the failing step and output. Count it as an escaped bug.

## 4. Release

When no slice is active:

1. **final-review** agent on `origin/main...origin/dev`. It catches cross-cutting bugs per-slice review misses (pipes, output sanitising, huge inputs).
   - Blocking or cheap user-visible findings → one **fixer** agent on a `<project>-final-fix` branch into `dev`, its own **reviewer**, the step 2.6 repair gate, then step 3 again.
   - Then, from a fresh clone of `dev` (`git clone --branch dev` into a temp dir), as a user gets it: the Journey check and Regression journeys; the README install/run instructions exactly as written; every listing command piped into `head -1` with 10,000+ rows (a few rows never trigger a broken pipe).
2. Freeze: record `Release candidate: <dev SHA>` in the status file. From now on nothing merges into `dev` except an owner-requested change, which goes through the repair gate and then repeats step 3, a final review of the diff since the release candidate, and the fresh-clone journey, and updates the release candidate in the status file and the release PR.
3. Open the release PR: `gh pr create --base main --head dev --assignee @me --title "<project>: <one-line outcome>"`, body:

```
Plan: specs/<project>/plan.md
Release candidate: <dev SHA> (all evidence below is for this SHA)

## Risky slices
<each slice with Risk not none: what it does, its PR, what to check>

## Not done
<failed or paused slices, why, and whether they carry into the next milestone; or none>

## Defaults chosen
<each default an agent picked, with its slice and the Decisions row>

## Built
<one line per merged slice with its PR>

## Journey check
<each step, incl. regression journeys and the fresh-clone run: command, pass/fail, key output>

## Reviews
<per slice: findings fixed / rejected with reason; final review result>

## Open risks
<pre-mortem flags not yet caught by a passing check; unresolved review findings; docs that disagree with the code>
```

No token or usage figures in the PR. Never merge it.

## Release lifecycle (ongoing products)

- **Released:** the owner merged the release PR → status `released <main merge SHA>`, `Finished:` time. With `delete_branch_on_merge` on and no ruleset protecting `dev`, GitHub deletes `dev` at that merge; the next preflight recreates it from `main`. A ruleset blocking deletion of `dev` keeps it. A squash-merged release leaves `main` outside `dev`'s history, so the next release PR would show every old change again: when `main`'s tree equals the release candidate's tree, push `git merge -s ours origin/main` onto `dev` (from a detached worktree of `origin/dev`; check the tree is unchanged before pushing). It records the history and changes no file, so it needs no gate. Not-done slices and open risks are listed in the status file for the next milestone.
- **Hotfix:** a change made on `main` directly (small mode, `/ship` against `main`) is fine; the next preflight syncs `main` into `dev`.
- **Next milestone:** a released plan is not run again; plan the next one with `/plan-project` (its step 1 says how).

## 5. Report

1. `python3 ~/.claude/skills/run-project/usage.py <this session's transcript> <project> --repo <repo> --since "<command-name>/run-project</command-name>" --label "run <date>"` (transcript: newest `*.jsonl` in `~/.claude/projects/<cwd as dashes>/`). It writes only to `~/.claude/project-usage/<repo>-<project>.md`, the same file `/plan-project` uses.
2. Retro: write the run's lessons (what broke in the setup, not in the code: each failure → where it happened → the smallest skill/brief/script change) to `~/.claude/project-runs/<repo>-<project>/lessons.md` and propose those changes to the owner.
3. Tell the owner: release PR URL, release candidate, merged / failed / paused slices, metrics (attempts, retries, owner interventions, escaped bugs, elapsed), usage file path. Usage numbers go in the session reply only.
