# Templates for /plan-project

## plan.md

```
# <project> plan

Status: draft | approved <YYYY-MM-DD>

## Goal
<the outcome, from grilling>
Success measure: <one measurable thing, or omit the line>

## Journey check
<exact commands that run the full user journey against dev, and what output means pass. Tag each line with the slice numbers it needs (`# 03+05`). Round trips compare the whole data (e.g. diff export against export), not a summary that hides fields.>

## Regression journeys
<earlier milestones' Journey checks that must keep passing; "none" for a first milestone>

## Decisions
| Question | Answer |
|---|---|

## Slices
| # | Slice | Depends on | Risk | Wave |
|---|---|---|---|---|

## Run settings
- Parallel cap: 2
- Budget: stop after <owner's number> slice attempts (owner told at 50% and 75%)
- Checkpoints: <none | after NN | before release>: the run stops there and waits for "continue"
- Implementer: <claude | an OpenCode model id, e.g. opencode/glm-5.3-flash-free> (omit = claude; when a model is allowed: /plan-project step 8)
- Unanswered question mid-run: the implementer brief's rule (`~/.claude/skills/run-project/BRIEFS.md`): small → default + Decisions row; risky → that slice and its dependents pause for the owner.

## Pre-mortem
- <technical or goal risk> → caught by <slice NN Acceptance / Journey check step / spec change>

## Out of scope
- <item> - deliberate: <why> | deferred: <when to revisit>
```

## architecture.md

```
# <project> architecture

## Glossary
**<Term>**: <what it is, one sentence>. _Avoid_: <synonyms>

## Stack
| Choice | Version | Why | Source (checked <YYYY-MM-DD>) |
|---|---|---|---|

## Global constraints
- <rule every slice inherits, e.g. "times stored in UTC", "tests use no network">

## Modules
### <module>
- Interface: <exact signatures or endpoints, invariants, error modes>
- Owns: <paths>
- Test seam: <where tests call it, and with what stand-ins>
- Uses: <other modules>

## Data model
<types or tables with fields>

## Shared files
<paths only 01-skeleton creates: manifest, lockfile, CI, lint config. A later slice that must change one lists it in Owns.>

## Review focus
- <likely real-world failure input> → <expected behaviour> (pinned by slice NN)
```

## Slice fields

Add to each `NN-<slug>.md`, after the /shape sections. This `Depends on:` line replaces the /shape one (one line per slice; the checker reads the first):

```
## Interfaces
- Uses: <signature> (from NN-<slug>)
- Provides: <signature>

Depends on: 01-skeleton, 03-<slug>
Owns: src/<module>/, test/<module>/
```

`Depends on: none` only for `01-skeleton`. `Owns:` lists files or directories (ending in `/`), comma-separated.
