# CSV import with duplicate skipping

## Outcome
The owner can load Expenses from a CSV file in the pinned ledger CSV format with `sandbox ledger import <file>`; re-importing the same file adds nothing.

## Acceptance
- [ ] Importing `tests/fixtures/expenses.csv` (seeded fake data, pinned columns) stores every row and prints `imported N, skipped 0 duplicates`.
- [ ] Importing it again prints `imported 0, skipped N duplicates` and stores nothing new.
- [ ] Duplicates are counted per identical Expense (date, amount, Category, note): as many copies as already exist in the DB are skipped, the rest imported. A file with two identical rows imported into an empty ledger imports both.
- [ ] A file with a UTF-8 BOM imports the same as one without.
- [ ] A file with a bad row (bad amount, bad date, missing column) imports nothing and exits 1 naming the line number.

## Exercise
```
export SANDBOX_LEDGER_DB=$(mktemp -d)/ledger.db
python3 -m sandbox ledger import tests/fixtures/expenses.csv
python3 -m sandbox ledger import tests/fixtures/expenses.csv
python3 -m sandbox ledger list
```

## Out of scope
- Other CSV formats (bank exports); column mapping.

## Risk
none

## Interfaces
- Uses: command module contract, `make_expense`, `CSV_COLUMNS`, `Store.add`, `Store.expenses`, `LedgerTestCase` (from 01)
- Provides: `ledger import PATH`, `import_expenses(store, path) -> tuple[int, int]`, `tests/fixtures/expenses.csv` (architecture.md: ledger.commands.import, CSV)

## Decisions
| Question | Default | Why |
|---|---|---|
| A repeated `note` header? | Error (`repeated column 'note'`), nothing imported | Safest: no silent guess about which column wins; relaxing later is reversible |
| A row shorter than the header (even only in an extra column)? | Error (`missing column '<name>'`), nothing imported | Safest: no silent guess that missing cells are empty; relaxing later is reversible |

Depends on: 01
Owns: sandbox/ledger/commands/import_csv.py, tests/test_ledger_import.py, tests/fixtures/
