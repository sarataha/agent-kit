# ledger plan

Status: approved 2026-10-29

## Goal

Pilot project mode: one `/run-project` start builds `sandbox ledger` (a personal expense tracker CLI) on `dev` with no per-slice help from the owner. Ledger has no product goal of its own.

Success measure: the pilot pass criteria in the project-mode pilot plan (working app and journey check pass without the owner starting slices; stop and resume neither duplicates nor loses work; an injected incompatible pair is caught by the journey check; a second fresh run ignores stale status; usage and owner interventions recorded locally).

## Journey check

Run from the repo root on `dev`. After each merge the coordinator runs only the steps whose slices are merged; with every slice merged, all steps must pass.

```
J=$(mktemp -d); export SANDBOX_LEDGER_DB=$J/ledger.db
python3 -m sandbox ledger add 12.50 groceries --date 2026-10-03 --note market   # 01: exit 0
python3 -m sandbox ledger add 40 transport --date 2026-10-05                    # 01: exit 0
python3 -m sandbox ledger list                                                  # 01: both Expenses shown, amounts 12.50 and 40.00
python3 -m sandbox ledger budget set groceries 200                              # 02: exit 0
python3 -m sandbox ledger import tests/fixtures/expenses.csv                    # 03: "imported N, skipped 0 duplicates"
python3 -m sandbox ledger import tests/fixtures/expenses.csv                    # 03: "imported 0, skipped N duplicates"
python3 -m sandbox ledger report --month 2026-10 > $J/r1.txt                    # 04: groceries line shows Budget 200.00
python3 -m sandbox ledger export --format csv > $J/out.csv                      # 05: exit 0
SANDBOX_LEDGER_DB=$J/fresh.db python3 -m sandbox ledger import $J/out.csv       # 03+05: "skipped 0 duplicates"
SANDBOX_LEDGER_DB=$J/fresh.db python3 -m sandbox ledger budget set groceries 200
SANDBOX_LEDGER_DB=$J/fresh.db python3 -m sandbox ledger report --month 2026-10 > $J/r2.txt
diff $J/r1.txt $J/r2.txt                                                        # 03+04+05: no difference
python3 -m sandbox ledger report --month 2026-10 --detailed 2>$J/e.txt; test $? -eq 3 && grep -q '^ledger: upgrade:' $J/e.txt   # 06: no key, upgrade message
SANDBOX_LICENSE_KEY=$(python3 scripts/seed.py --license) python3 -m sandbox ledger report --month 2026-10 --detailed   # 06: per-Category Expenses and top 3
```

## Decisions

| Question | Answer |
|---|---|
| Real goal | Pilot project mode; pass = the pilot criteria in the project-mode pilot plan. |
| User and journey | Owner only, at the terminal, fake data. Journey: add, budget, import, report, export, re-import into an empty DB gives the same report. |
| What is tracked | Expenses only, one currency, stored as integer cents (`12.50` in, `1250` stored). No income, no multi-currency, no floats. |
| Storage | One SQLite file (stdlib `sqlite3`) at `SANDBOX_LEDGER_DB`, default `./ledger.db`. Tests use a temp file. |
| Scope | 6 slices: skeleton (`add`, `list`), budgets, CSV import, monthly report, export (CSV/JSON), license-gated detailed report. |
| Reality gate | No real data, no shared systems, no real-world actions. Seeded fake data only. Nothing staged for owner approval. |
| Risky slice | Detailed report lives in `sandbox/billing/`, Risk: license. Offline HMAC check with a fixed test secret; test key from the seed script. Missing or bad key: upgrade message, exit 3 (exit 2 is argparse's usage error). Merges into `dev`, listed first in the release PR. |
| Incompatible-pair test | `architecture.md` pins the CSV format. The pilot tests the journey check separately by breaking one side on purpose mid-run (e.g. rename an export column) and confirming the check fails. |
| Names | Expense, Category, Budget, Month, Report (see `GLOSSARY.md`). |
| Dates | ISO `YYYY-MM-DD`; `add` defaults to today's local date; Month = `YYYY-MM` of the date. |
| Duplicates on import | Same date, amount, Category and note = duplicate: skipped and counted, `imported N, skipped M duplicates`. |
| Report output | `report --month YYYY-MM`: one line per Category with spent, Budget, remaining, `OVER` when spent > Budget; `-` when no Budget; total line last. |
| License key and detailed report | Key from `SANDBOX_LICENSE_KEY`. Valid key + `--detailed` adds each Category's Expenses and the top 3 Expenses. |
| Journey check location | Shell commands in this file; the coordinator runs the steps of merged slices after each merge. |
| Run budget | Stop after 12 slice attempts (6 slices × 2). |
| Duplicates within one file | Multiset: per identical Expense, skip as many copies as already exist in the DB, import the rest. Re-import skips all; identical Expenses survive a round trip. |
| Size of 01 | Keep 01-skeleton as one slice; splitting gains no parallelism. |

## Slices

| # | Slice | Depends on | Risk | Wave |
|---|---|---|---|---|
| 01 | 01-skeleton: `add`, `list`, CLI registry, model, store, test seam | none | none | 1 |
| 02 | 02-budgets: `budget set`, `budget list` | 01 | none | 2 |
| 03 | 03-import: CSV import, duplicate skipping | 01 | none | 2 |
| 04 | 04-report: monthly Report against Budgets | 02 | none | 3 |
| 05 | 05-export: CSV and JSON export, round trip | 03 | none | 3 |
| 06 | 06-detailed-report: license-gated `--detailed` | 04 | license | 4 |

## Run settings

- Parallel cap: 2
- Budget: stop after 12 slice attempts
- Unanswered question mid-run: small, reversible, inside one slice → safest default, new Decisions row, listed in the release PR. Risky or shape-changing (auth, billing, license, customer data, migration, new dependency, shared interface or data model, spec contradiction, wrong acceptance test) → pause that slice and its dependents, ask the owner.

## Pre-mortem

Technical:
- 01 is the largest slice (CLI registry, model, store, test seam, `add`, `list`) and gates everything; if it fails twice the whole run stops → caught by 01 Acceptance; run budget stops the run instead of looping.
- `--detailed` failing with argparse's exit 2 could pass a weak journey step → license failure exits 3 and the journey step also checks `ledger: upgrade:` on stderr.
- One command module that fails to import breaks every `ledger` subcommand (registry imports all) → full test suite after each merge into `dev`.
- gitleaks blocks the fixed HMAC test secret → `# gitleaks:allow` on that line (architecture.md billing); caught at 06 commit.
- ruff default rules not checked against the planned code → each slice runs `uvx ruff check .` before push; CI lint on every PR.
- 06 edits `sandbox/ledger/commands/report.py` owned by 04 → 06 depends on 04, so never in parallel (checker passes); 06 Owns lists the file.
- `add` default-date test flaking across midnight → architecture.md: test reads `date.today()` inside the test.

Goal:
- Stop-and-resume, the injected incompatible pair, and a second fresh run are not slice behaviour → `/run-project` pilot procedure, not this plan.
- Usage not recorded → recorded locally by the coordinator, never in the repo or a PR.

## Out of scope

- Editing or deleting Expenses - deliberate: the pilot needs 6 slices, not a full tracker.
- Recurring Expenses, income, multi-currency - deliberate: same reason.
- Any UI beyond the CLI; any network access - deliberate: the pilot must run offline and locally.
- Real license sales or key issuing - deliberate: the license check exists only to exercise the risky-slice path.
