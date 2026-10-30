---
name: shape
description: Validate an idea before building (competitors, demand signal, kill criteria), spar with the user on scope, then write vertical-slice spec files (`specs/<slug>.md`) in the repo. Use when the user runs /shape <idea> or wants to turn an idea or feature into specs.
---

# /shape <idea>

Human-heavy step. Spar, don't transcribe. Output: a verdict, then specs an agent can `/ship` with no follow-up questions.

## 1. Validate (new product or big feature)

Skip for small features in an existing repo; go to step 2.

Research with WebSearch (extended mode for niche markets). Report, with links:
- **Competitors:** 3-7 closest. Pricing, OSS vs paid, last release/activity, top complaints (issues, Reddit, HN, reviews).
- **Demand signal:** real evidence people want this: search threads, GitHub issues on competitors asking for it, "is there a tool that..." posts. Quote + link. No evidence = say so.
- **Wedge:** why this wins for a self-serve buyer with no sales calls. Open-core split if paid: what's free, what's paid.
- **Kill criteria:** 2-4 measurable conditions that mean stop (e.g. "<20 stars / 0 paying users 60 days after launch", "competitor X ships Y").

Verdict: **build**, **narrow** (state the smaller bet), or **kill**. Stop here on kill unless the user overrides.

## 2. Spar

Call the Skill tool with "grilling" until scope is tight. The tree covers at least: who uses it, smallest useful outcome, what's out, data touched, auth/billing/license/customer-data involvement. Challenge assumptions. Prefer the user's answers over your guesses. Every answer becomes a Decisions row (step 3).

## 3. Slice

Each spec is a vertical slice: shippable to `main` alone or behind a flag, one PR, user-visible or testable end to end. No "set up DB" or "write tests" specs. First slice = thinnest path that runs.

Spec file `specs/<slug>.md` (slug: short kebab-case, e.g. `cmp-hide-list`):

```
# <title>

## Outcome
<what a user can do after this ships>

## Acceptance
- [ ] <checkable behaviour>

## Exercise
<exact command / request / click path to run the changed path for real>

## Out of scope
- <explicit non-goals>

## Decisions
| Question | Answer |
|---|---|
| <each question asked while sparring> | <the owner's answer, or the default chosen and why> |

## Grounding
- <external fact this slice depends on (library behaviour, limit, price)> - source: <url or command>, checked <YYYY-MM-DD>

## Pre-mortem
- <technical: how the build could fail> → caught by <Acceptance item / Exercise step>
- <goal: how it could ship and still miss the Outcome> → caught by <...>

## Open questions
- <only things the builder can answer mid-build>

## Risk
<none | auth | billing | license | customer-data | migration | CI>  (+ one line why)

Depends on: specs/<slug>.md (if any)
```

Rules for the spec:
- Every external fact the slice rests on is verified now and listed under Grounding. One you can't verify is written `[UNVERIFIED]` in place and gets a Pre-mortem line. Omit Grounding when the slice rests on no external facts.
- Numbers (thresholds, limits, timeouts) come from the owner or are tagged `(illustrative)`.
- Open questions are only for things the builder can settle mid-build. Anything that changes the slice's shape, its data, or whether Outcome is measurable gets decided now and goes in Decisions.
- Pre-mortem: imagine the shipped slice failed, then work back. If a flag would change the slice's shape rather than warn, fix the spec now (new Decisions row, changed Acceptance) instead of leaving the warning. Omit Open questions when empty.

## 3b. Feasibility check (before writing the files)

An agent can't fix a blocker you shaped in. For each slice, check it can be done today:
- Dependency upgrades: for every package the acceptance names, `npm view <pkg> version peerDependencies` (or the stack's equivalent). Any peer range that excludes the target → pick the way around it (drop/replace the package, wait) and write that decision into the spec, or don't shape it.
- External services, network, paid APIs the build can't use → say how to exercise without them.
- Acceptance items that contradict each other → resolve now.

## 4. Create

Show the slice list (titles + one-line outcome) and get a yes before creating anything.

- Repo exists: write each spec to `{{PROJECTS}}/<repo>/specs/<slug>.md` in the main checkout. Run the repo's formatter on it (e.g. `npx prettier --write`). Don't commit or push: `/ship` commits the spec with its acceptance tests, so it reaches `main` with the feature. Validation brief (step 1) goes in `specs/<feature>-brief.md` and lists the slice specs.
- No repo yet: suggest `/new-project` first, then write the specs.

Report: spec paths, which one to `/ship` first (`/ship <repo> <slug>`).
