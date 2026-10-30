# Resuming an interrupted /run-project

Read when the status file exists and `contract_hash.py check` printed `OK` (SKILL.md step 1). The status file is the record; GitHub and git are the truth. For each slice not `merged`, check what actually exists before acting, and never start a second worktree, branch or PR for the same slice.

Find the facts: `git -C {{PROJECTS}}/<repo> worktree prune` first (drops records of deleted worktree folders), then `git -C {{PROJECTS}}/<repo> worktree list --porcelain`, `git -C {{PROJECTS}}/<repo> ls-remote origin '<project>-<NN>-*'`, `gh pr list --repo <owner>/<repo> --head <branch> --state all --json number,state,headRefOid,mergeCommit`.

| Status says | What exists | Do |
|---|---|---|
| `pending` | nothing | start normally (SKILL.md step 2) |
| `pending` | worktree or branch | status file lost an update: treat as `tests` below |
| `tests` | no test commit on the branch | reuse the worktree (`git -C <wt> status` clean, else stash and note it); restart **test-writer** in it |
| `tests` | test commit pushed | record it as the baseline (if the status lacks it), verify the tests fail for the right reason, go to implementer |
| `implementing` | no PR | reuse the worktree; restart **implementer** with the recorded baseline (rewrite `.claude/ship-acceptance.json` if missing) |
| `implementing` | open PR | go to review on the PR's current head |
| `review` | open PR, reviews recorded for its current head, no blocking finding `open` | go to the merge gate |
| `review` | open PR, a blocking finding `open` | send it to the **fixer** (counts toward the 2 rounds) |
| `review` | open PR, no reviews for its current head | restart the missing **reviewer** / **spec-check** on that head |
| `merging` | PR merged | record the merge SHA, run the integration check (step 3) |
| `merging` | PR open | re-run the merge gate on its current head |
| any | PR closed unmerged | stop for the owner (only the owner closes PRs) |
| any | worktree path gone, branch exists | `git worktree add <wt> <branch>` (no `-b`) and continue |
| `paused (question)` | — | re-send the owner the recorded question |
| run `paused` (owner said "pause") | — | reconcile every slice as above, report, start nothing until the owner says "continue" |

Rules:
- Uncommitted changes in a reused worktree (any status) → `git -C <wt> stash push -u -m "<project> <NN> <role> partial work before resume"`, log it; the restarted role starts from the last commit, never from unreviewed leftovers. Keep `.claude/ship-acceptance.json` (ignored, not stashed).
- Attempts and the baseline (test commit) carry over; a restarted role is not a new attempt. An attempt counts from the moment the slice's first implementer starts. A new attempt starts only when the gate or implementer fails as defined in SKILL.md.
- A worker that may still be running (background agent from the dead session) is assumed dead: the session that spawned it is gone. Before reusing a worktree, check twice a minute apart that its branch (local and remote) and its file times are unchanged; if either moves, a worker is alive: stop and report.
- After reconciling every slice, write the status file, then continue the frontier.
- Integration fixer, final fixer and release PR resume the same way: find the branch/PR, reuse, continue at the recorded step.
- **Old status files** (an old `Plan: <hash>` line, no `contract.json`): the plan as first committed must match, `git -C {{PROJECTS}}/<repo> show $(git -C {{PROJECTS}}/<repo> log --format=%H --diff-filter=A -1 origin/dev -- specs/<project>/plan.md):specs/<project>/plan.md | git hash-object --stdin` equals `<hash>` (else stop for the owner). Snapshot that commit's specs folder (`git archive <commit> specs/<project>`), run `check` against the current one, replace the line with `Contract:`, and tell the owner the other spec files were checked only from their first commit.
- Release PR open at the recorded `Release candidate:` → the run is in step 4: nothing new starts; an owner-requested change follows step 4.2. Release PR head differs from the recorded candidate → stop and report (something merged outside the gate).
