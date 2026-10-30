# Monthly Report against Budgets

## Outcome
The owner can see, for one Month, spending per Category against its Budget with `sandbox ledger report --month YYYY-MM`.

## Acceptance
- [ ] One line per Category with Expenses or a Budget: spent, Budget, remaining, two decimals.
- [ ] `OVER` on lines where spent > Budget; `-` for Budget and remaining when the Category has no Budget.
- [ ] A total line last.
- [ ] Only Expenses dated in that Month count.
- [ ] A Month with no Expenses and no Budgets prints only the total line with 0.00 and exits 0.
- [ ] A bad Month (`2026-13`, `10-2026`) exits 1 with a one-line error.

## Exercise
```
export SANDBOX_LEDGER_DB=$(mktemp -d)/ledger.db
python3 -m sandbox ledger add 250 groceries --date 2026-10-03
python3 -m sandbox ledger add 40 transport --date 2026-10-05
python3 -m sandbox ledger add 9 groceries --date 2026-11-01
python3 -m sandbox ledger budget set groceries 200
python3 -m sandbox ledger report --month 2026-10
```

## Out of scope
- `--detailed` (06-detailed-report).

## Risk
none

## Interfaces
- Uses: `Store.expenses(month)`, `Store.budgets` (01), Budgets set by 02, `parse_month`, `format_cents`
- Provides: `ReportRow`, `Report`, `build_report(store, month)`, `render_report(report)`, `ledger report --month` (architecture.md: ledger.report)

## Decisions
| Question | Decision |
|---|---|
| Does the TOTAL line get `OVER` when total spent exceeds the total Budget? | No. TOTAL never prints `OVER`; only Category lines do. Matches the architecture example. |

Depends on: 02
Owns: sandbox/ledger/report.py, sandbox/ledger/commands/report.py, tests/test_ledger_report.py
