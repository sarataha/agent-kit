# Budgets per Category

## Outcome
The owner can set a monthly Budget for a Category with `sandbox ledger budget set` and see Budgets with `sandbox ledger budget list`.

## Acceptance
- [ ] `ledger budget set groceries 200` exits 0 and stores 20000 cents for Category `groceries`.
- [ ] Setting a Budget again for the same Category (any case) replaces it.
- [ ] `ledger budget list` prints each Category and its Budget with two decimals.
- [ ] Invalid amounts exit 1 with a one-line error and store nothing.

## Exercise
```
export SANDBOX_LEDGER_DB=$(mktemp -d)/ledger.db
python3 -m sandbox ledger budget set groceries 200
python3 -m sandbox ledger budget set Groceries 250
python3 -m sandbox ledger budget list
```

## Out of scope
- Showing spending against Budget (04-report).
- Budgets that differ by Month.

## Risk
none

## Interfaces
- Uses: command module contract, `parse_category`, `parse_amount(allow_zero=True)`, `Store.set_budget`, `Store.budgets`, `LedgerTestCase` (from 01)
- Provides: `ledger budget set|list` (architecture.md: ledger.commands.budget)

Depends on: 01
Owns: sandbox/ledger/commands/budget.py, tests/test_ledger_budget.py
