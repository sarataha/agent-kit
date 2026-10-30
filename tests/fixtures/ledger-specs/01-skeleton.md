# Ledger skeleton: add and list Expenses

## Outcome
The owner can record Expenses with `sandbox ledger add` and see them with `sandbox ledger list`, stored in the SQLite file at `SANDBOX_LEDGER_DB`.

## Acceptance
- [ ] `ledger add 12.50 groceries --date 2026-10-03 --note market` exits 0 and stores amount 1250 cents, date 2026-10-03, Category `groceries`, note `market`.
- [ ] `ledger add 40 transport` without `--date` stores today's local date.
- [ ] Category is compared case-insensitively: `Groceries` and `groceries` are the same Category.
- [ ] `ledger list` prints every Expense, oldest date first, amounts with two decimals (`12.50`, `40.00`).
- [ ] Invalid amounts (`12.5.0`, `-3`, `0`, `abc`) and invalid dates (`2026-13-01`, `03/10/2026`) exit 1 with a one-line error and store nothing.
- [ ] `SANDBOX_LEDGER_DB` unset → `./ledger.db`; the DB file and schema are created on first use.
- [ ] `sandbox greet ada` still prints `hello, ada`.

## Exercise
```
export SANDBOX_LEDGER_DB=$(mktemp -d)/ledger.db
python3 -m sandbox ledger add 12.50 groceries --date 2026-10-03 --note market
python3 -m sandbox ledger add 40 transport --date 2026-10-05
python3 -m sandbox ledger list
python3 -m sandbox ledger add 12.5.0 groceries; echo "exit=$?"
python3 -m sandbox greet ada
```

## Out of scope
- Budgets, import, report, export, license (later slices).
- Editing or deleting Expenses.

## Risk
none (local CLI, fake data)

## Interfaces
- Uses: none
- Provides: everything in architecture.md sections entry, ledger.cli (command module contract, `LedgerTestCase`), ledger.model, ledger.store, ledger.commands.add + list; full DB schema

Depends on: none
Owns: sandbox/__init__.py, sandbox/__main__.py, sandbox/ledger/__init__.py, sandbox/ledger/cli.py, sandbox/ledger/commands/__init__.py, sandbox/ledger/model.py, sandbox/ledger/store.py, sandbox/ledger/commands/add.py, sandbox/ledger/commands/listing.py, tests/__init__.py, tests/test_greet.py, tests/ledger_support.py, tests/test_ledger_model.py, tests/test_ledger_add_list.py, .gitignore, README.md
