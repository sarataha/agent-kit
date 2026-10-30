# License-gated detailed Report

## Outcome
With a valid license key, the owner can add `--detailed` to a Report to see each Category's Expenses and the top 3 Expenses of the Month.

## Acceptance
- [ ] With a valid `SANDBOX_LICENSE_KEY`, `report --month M --detailed` prints the normal Report, then each Category's Expenses, then the 3 largest Expenses of the Month.
- [ ] Without a key, or with an invalid or tampered key, `--detailed` prints a one-line `ledger: upgrade: ...` message to stderr, nothing to stdout, and exits 3; the plain Report is unaffected.
- [ ] `python3 scripts/seed.py --license` prints a valid test key; `python3 scripts/seed.py` output is unchanged.
- [ ] The key check is offline (HMAC with the fixed test secret), no network.

## Exercise
```
export SANDBOX_LEDGER_DB=$(mktemp -d)/ledger.db
python3 -m sandbox ledger add 250 groceries --date 2026-10-03
python3 -m sandbox ledger report --month 2026-10 --detailed; echo "exit=$?"
SANDBOX_LICENSE_KEY=$(python3 scripts/seed.py --license) python3 -m sandbox ledger report --month 2026-10 --detailed
```

## Out of scope
- Real key issuing or sales; key expiry.

## Risk
license (license-gated feature in `sandbox/billing/`; listed first in the release PR)

## Interfaces
- Uses: `build_report`, `render_report`, `sandbox/ledger/commands/report.py` (04), `LedgerError` (01)
- Provides: `check_license(key)`, `issue_key(subject)`, `render_detailed(store, month)`, `report --detailed`, `scripts/seed.py --license` (architecture.md: billing)

Depends on: 04
Owns: sandbox/billing/, scripts/seed.py, tests/test_billing_detailed.py, sandbox/ledger/commands/report.py
