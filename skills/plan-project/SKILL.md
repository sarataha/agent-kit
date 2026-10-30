---
name: plan-project
description: Plan a whole project or multi-slice milestone once (grilling, architecture, slice specs with dependencies and file ownership, plan.md) so /run-project can build it in parallel without shaping each slice.
disable-model-invocation: true
---

# /plan-project <repo> <project>

The only interactive step of project mode. Output: `specs/<project>/` (`plan.md`, `architecture.md`, `NN-<slug>.md` slices) that agents build to a working app on `dev` without asking the owner anything except what the risk rule in `plan.md` sends back.

Copy this checklist and tick it as you go:

```
- [ ] 1 Load
- [ ] 2 Validate
- [ ] 3 Grill
- [ ] 4 Architecture
- [ ] 5 Slices
- [ ] 6 Check
- [ ] 7 Pre-mortem
- [ ] 8 Approve and write
```

## 1. Load

- No repo yet → suggest `/new-project` first.
- Read `AGENTS.md`, the code, existing `specs/`, `GLOSSARY.md`, `docs/adr/`.
- Empty repo and a vague idea → ask the owner for material (notes, similar tools, screenshots, examples) before grilling. Continue only with material or the owner's explicit "none".
- `specs/<project>/` already holds a released plan (a next milestone of an existing product) → never rewrite it. Plan the milestone in a new folder `specs/<project>-<milestone>/` with its own (possibly small) `01` slice, and copy the released plan's Journey check under Regression journeys. A change too small for a milestone goes through `/shape` + `/ship`.

Done when: you can say in one sentence what the project is and what already exists.

## 2. Validate (new product only)

Run step 1 of `~/.claude/skills/shape/SKILL.md` (competitors, demand, wedge, kill criteria, verdict). Kill → stop.

## 3. Grill

Call the Skill tool with "grilling", then with "domain-modeling". The tree covers at least:

- the real goal: ask why until you reach the outcome, not the feature; a success measure if one exists
- who uses it and the full user journey that proves the milestone works
- scope in and out
- data, integrations, where it runs, stack constraints
- reality gate: real data, systems other people use, or real-world actions (send, post, write, pay); which actions must be staged for owner approval
- risk areas: auth, billing, license, customer data

Facts go to a subagent, never to the owner. A "what should it look like / does this flow feel right" question → offer the Skill tool with "prototype" before deciding.

Done when: the frontier is empty, the owner confirms shared understanding, and every answer is a Decisions row. Anything that changes a slice's shape, its data, or whether done is measurable is decided now, never left open.

Write `specs/<project>/plan.md` from [TEMPLATES.md](TEMPLATES.md) with Goal, Journey check, Decisions and Out of scope filled; leave Slices empty.

## 4. Architecture (fresh subagent)

Spawn a `general-purpose` subagent, model `opus`, with pointers only (repo path, `plan.md`, `GLOSSARY.md`, [TEMPLATES.md](TEMPLATES.md)) and this brief:

> Write `specs/<project>/architecture.md` from the architecture template in TEMPLATES.md. Call the Skill tool with "codebase-design". Deep modules, fewest seams, tests through the highest seam. Check every tech choice's latest stable version and limits on its source (`npm view`, release page, docs) and cite it with the date. Pin every tool version CI runs (linters, formatters); an unpinned tool makes local and CI disagree. Assign every path to exactly one module. Cover cross-cutting output and input handling in Global constraints (closed pipes, encodings, control characters, huge values). Keep `plan.md` Decisions; flag any you think are wrong instead of changing them. Repo: only the given path. No code.

Read the result against `plan.md`. Fix disagreements, or put them to the owner.

Done when: every module has an interface, a test seam and owned paths, and every version has a source.

## 5. Slices

Write `specs/<project>/NN-<slug>.md` in the `/shape` spec format plus the slice fields in [TEMPLATES.md](TEMPLATES.md).

- `01-skeleton`: thinnest runnable path through every layer (a tracer bullet). Owns the shared files from `architecture.md`. No dependencies.
- Every other slice: one vertical path, demoable alone, fits one fresh agent session, one PR into `dev`, depends on `01` directly or through other slices.
- `Depends on:` only slices that truly gate it. A slice that touches a path owned by a slice it isn't ordered with must depend on it.
- Interfaces use the exact signatures from `architecture.md`. Acceptance tests go through the module's test seam.
- Out of scope names commands or features, never concepts that `architecture.md` assigns to this slice (e.g. "budget commands", not "budgets", when 01 owns the budget table).
- Acceptance repeats no format, field or rule; it points to the `architecture.md` section that pins it.

Fill the `plan.md` Slices table.

Done when: every Journey check step and every Decision is covered by some slice's Acceptance.

## 6. Check

Run `python3 ~/.claude/skills/plan-project/check_plan.py <repo>/specs/<project>`. Fix every error and rerun until it prints `OK`. Copy its waves (what can run in parallel) into the Slices table.

Then spawn a fresh `sonnet` subagent: "Compare every slice's Acceptance, Exercise and Out of scope in `specs/<project>/` with `architecture.md` and `plan.md`. List each contradiction (format, field, rule, exit code, ownership) with file:line. Read-only." Fix every contradiction, rerun the checker.

## 7. Pre-mortem

Imagine the finished run failed, then work back. Technical: will slices build and integrate? Goal: will the journey and success measure be met? Each flag points to the slice Acceptance, Journey check step or spec change that catches it. A flag that would change a slice's shape means fixing the slices now (rerun step 6). Write the flags into `plan.md`.

## 8. Approve and write

Show the owner the Slices table (with waves and risk), the Journey check and the pre-mortem, plus a proposed `Implementer:` line. An open model from `~/.claude/skills/run-project/oc_models.txt` (free, slower; it builds Risk: none slices, Claude the rest) only if `~/.claude/skills/run-project/oc_check.sh <model> <repo>` prints `OK` (model passed the eval, personal {{OWNER}} repo under {{PROJECTS}}, model available and answering, no tracked secret files) and most slices are clear-spec with acceptance tests; else `claude`, quoting the `NO` lines or the reason. A model not in that file needs a model eval first (README, Open models). Ask: right size? dependencies right? merge or split any? implementer ok? Loop until yes, then set `Status: approved <date>`.

Run the repo's formatter on `specs/<project>/`. Don't commit: `/run-project` commits the specs on `dev`.

Record usage, local only: `python3 ~/.claude/skills/run-project/usage.py <this session's transcript> <project> --repo <repo> --since "<command-name>/plan-project</command-name>" --label "plan <date>"`.

Report: folder path, slice count, waves, risky slices, next command `/run-project <repo> <project>`, best started from a session in `{{PROJECTS}}`.
