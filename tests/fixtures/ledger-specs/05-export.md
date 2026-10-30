# Export to CSV or JSON

## Outcome
The owner can export every Expense with `sandbox ledger export --format csv|json`, and a CSV export re-imports into an empty ledger unchanged.

## Acceptance
- [ ] `export --format csv` writes the pinned ledger CSV format to stdout, oldest date first.
- [ ] `export --format json` writes the pinned JSON shape to stdout.
- [ ] Importing a CSV export into an empty ledger gives the same Expenses (round trip), checked by a test through the CLI.
- [ ] Notes containing commas and quotes survive the CSV round trip.
- [ ] An empty ledger exports a header-only CSV and the pinned JSON object `{"expenses": [], "format": "ledger-export", "version": 1}`, exit 0.

## Decisions
| Decision | Source |
|---|---|
| Acceptance 4 drops newlines: notes cannot contain newlines (architecture, Global constraints), so only commas and quotes are tested. | owner decision |
| Acceptance 5: an empty ledger exports a header-only CSV and the pinned JSON object `{"expenses": [], "format": "ledger-export", "version": 1}`, not `[]`, exit 0. | owner decision |

## Exercise
```
export SANDBOX_LEDGER_DB=$(mktemp -d)/ledger.db
python3 -m sandbox ledger add 12.50 groceries --date 2026-10-03 --note 'market, "fresh"'
python3 -m sandbox ledger export --format csv
python3 -m sandbox ledger export --format json
```

## Out of scope
- Writing to a file path (stdout only); other formats.

## Risk
none

## Interfaces
- Uses: `CSV_COLUMNS`, `format_cents`, `Store.expenses` (01), `ledger import` for the round-trip test (03)
- Provides: `ledger export --format csv|json` (architecture.md: ledger.commands.export, CSV, JSON export)

Depends on: 03
Owns: sandbox/ledger/commands/export.py, tests/test_ledger_export.py
