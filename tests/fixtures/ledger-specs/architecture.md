# ledger architecture

## Glossary
**Expense**: money spent once: an amount, a date, a Category and an optional note. _Avoid_: transaction, entry, record
**Category**: a free-text label grouping Expenses, compared case-insensitively. _Avoid_: tag, type
**Budget**: the spending limit for one Category in every Month. _Avoid_: limit, cap
**Month**: a calendar month, written `YYYY-MM`; an Expense belongs to the Month of its date. _Avoid_: period
**Report**: spending per Category for one Month, compared with each Category's Budget. _Avoid_: summary, statement

Code uses the same words: `Expense`, `category`, `budget`, `month`, `build_report`. No `Transaction`, `Entry`, `Tag`, `Limit`, `Period`, `Summary` identifiers.

## Stack
| Choice | Version | Why | Source (checked 2026-10-29) |
|---|---|---|---|
| Python | 3.12 (CI pins `python-version: "3.12"`); code must not need newer | Repo rule: stdlib only. `sqlite3.connect(autocommit=...)` and `TemporaryDirectory(delete=...)` both need 3.12 | `.github/workflows/ci.yml`; https://docs.python.org/3.12/library/sqlite3.html ("Added in version 3.12" for `autocommit`) |
| `sqlite3` | stdlib; module needs SQLite >= 3.7.15 | One local file, transactions, no server. `with con:` commits or rolls back but does **not** close the connection, so `Store.close()` is explicit. Use `autocommit=False` (docs: "the recommended value") and commit through `with con:`. No `STRICT` tables (avoid depending on the bundled SQLite version) | https://docs.python.org/3.12/library/sqlite3.html |
| `hmac` + `hashlib` SHA-256 | stdlib | Offline license check. `hmac.new(key, msg, digestmod="sha256")`; compare with `hmac.compare_digest`, whose `str` arguments must be ASCII only (guaranteed by the key regex) | https://docs.python.org/3.12/library/hmac.html |
| `csv` | stdlib | Import/export. Files opened with `newline=''` (docs: "should be opened with `newline=''`"). `DictReader` takes fieldnames from the first row; surplus fields go under `restkey` (default `None`). Writer `lineterminator` defaults to `'\r\n'`, so export sets `'\n'` | https://docs.python.org/3.12/library/csv.html |
| `utf-8-sig` codec | stdlib | Import opens CSV with `encoding="utf-8-sig"`: "On decoding `utf-8-sig` will skip those three bytes [BOM] if they appear". Export writes plain `utf-8` (no BOM), since `utf-8-sig` writes one on encode | https://docs.python.org/3.12/library/codecs.html |
| `argparse` | stdlib | Subcommands via `add_subparsers(required=True)` + `set_defaults(...)` dispatch. Usage errors exit 2. A positional like `-3` is accepted as a positional only while no option looks like a negative number | https://docs.python.org/3.12/library/argparse.html |
| `datetime` | stdlib | `date.today()` = current local date. `date.fromisoformat` accepts `20191204` and `2021-W01-1` since 3.11, so it is only used **after** a strict `YYYY-MM-DD` regex | https://docs.python.org/3.12/library/datetime.html |
| `re` | stdlib | Input validation with `re.fullmatch` and explicit `[0-9]` classes: `\d` on `str` patterns matches any Unicode `Nd` digit unless `re.ASCII` | https://docs.python.org/3.12/library/re.html |
| `str.casefold` | stdlib | Category key. Casefold is the documented caseless-matching form (`'ß'` -> `'ss'`), `lower()` is not | https://docs.python.org/3.12/library/stdtypes.html |
| `json` | stdlib | JSON export, `indent=2, ensure_ascii=False, sort_keys=True`. `dumps` adds no trailing newline (inferred from the doc examples, not stated), so export prints it with `print()` | https://docs.python.org/3.12/library/json.html |
| `pkgutil` + `importlib` | stdlib | Command discovery. `pkgutil.iter_modules(path)` yields `ModuleInfo`; order is not guaranteed, so results are sorted by name | https://docs.python.org/3.12/library/pkgutil.html |
| `unittest`, `unittest.mock.patch.dict`, `tempfile.TemporaryDirectory` | stdlib | Existing test runner (`python3 -m unittest -v`). `patch.dict(os.environ, ...)` restores the env on exit; `TemporaryDirectory` removes the DB on exit | https://docs.python.org/3.12/library/unittest.mock.html, https://docs.python.org/3.12/library/tempfile.html |
| gitleaks `gitleaks:allow` | pre-commit hook v8.30.1 (already pinned) | The fixed test HMAC secret line carries a trailing `# gitleaks:allow` so the hook does not block commits | https://github.com/gitleaks/gitleaks (README) |

## Global constraints
- Stdlib only. No new runtime or test dependency, no `pyproject.toml`, no network.
- Money is integer cents everywhere (`int`). Never call `float()` on an amount; parse text with the regex in `model.parse_amount`, format with `model.format_cents`.
- Dates are stored and printed as ISO `YYYY-MM-DD` text, Months as `YYYY-MM`. "Today" is `date.today()` (local).
- Every raw user string (CLI arg or CSV cell) is validated by one function in `sandbox/ledger/model.py`. Commands do not write their own validation.
- Category is stored normalised: `text.strip().casefold()`, non-empty. Display uses the stored form. Two spellings that casefold equal are one Category.
- Note is stored as `''` when absent (never `NULL`), so equality and duplicate checks work in SQL and Python. Note and Category may not contain `\t`, `\r` or `\n` (they would break line output).
- Results go to stdout; errors go to stderr as one line `ledger: error: <message>`. Nothing is written to stdout on a failing command.
- Exit codes:

  | Code | Meaning | Who |
  |---|---|---|
  | 0 | success (including empty results) | all |
  | 1 | bad input value, bad/unreadable CSV, DB error (`LedgerError`, `sqlite3.Error`) | all |
  | 2 | argparse usage error (argparse's own) | argparse |
  | 3 | `--detailed` with missing or invalid license key | billing |
- No option anywhere under `ledger` may look like a negative number (`-1` etc.), so `ledger add -3 x` reaches `parse_amount` and fails with exit 1, not a usage error.
- Output order is always deterministic: Expenses by `(date, id)`, Categories by name, so the journey `diff` holds.
- `SANDBOX_LEDGER_DB` and `SANDBOX_LICENSE_KEY` are read at command run time, never at import time. Empty `SANDBOX_LEDGER_DB` counts as unset (default `./ledger.db`).
- Dependency direction: `sandbox.billing` may import `sandbox.ledger`; `sandbox.ledger` never imports `sandbox.billing`, except `sandbox/ledger/commands/report.py`.
- Tests never touch `./ledger.db` and never read the developer's `SANDBOX_LICENSE_KEY` (see Test seam in `ledger.cli`).
- The existing `greet` command, `greet()` function and `tests/test_greet.py` stay as they are and keep passing.
- `python3 scripts/seed.py` with no arguments keeps printing the same users JSON (CI runs it).

## Modules

### entry (`sandbox/__main__.py`)
- Interface: `main(argv: list[str] | None = None) -> int` and `greet(name: str, shout: bool = False) -> str`, unchanged signatures. `main` builds the top-level `sandbox` parser, adds `greet` as today, then calls `sandbox.ledger.cli.register(sub)`. Dispatch: `greet` as today; `ledger` returns `sandbox.ledger.cli.run(args)`. Usage errors raise `SystemExit(2)` from argparse (unchanged).
- Owns: `sandbox/__init__.py`, `sandbox/__main__.py`, `tests/__init__.py`, `tests/test_greet.py`, `.gitignore` (01 adds `ledger.db`), `README.md`.
- Test seam: `main([...])` with `redirect_stdout`; existing `tests/test_greet.py`.
- Uses: ledger.cli.
- Edited once, by 01. No later slice touches it.

### ledger.cli (command registry and runner)
- Interface:
  - `register(top: argparse._SubParsersAction) -> None`: adds `ledger` with its own `add_subparsers(dest="ledger_cmd", required=True)`, then imports every module in `sandbox.ledger.commands` (via `pkgutil.iter_modules(commands.__path__)`, **sorted by name**) and calls its `register(subparsers)`.
  - `run(args: argparse.Namespace) -> int`: opens the Store from `SANDBOX_LEDGER_DB`, calls `args.handler(args, store, sys.stdout)`, closes the Store. Catches `LedgerError` -> prints `ledger: error: <msg>` (or the error's own `message_line()`) to stderr, returns `err.exit_code`. Catches `sqlite3.Error` -> `ledger: error: database: <msg>`, exit 1.
  - **Command module contract** (every file in `sandbox/ledger/commands/`): exposes `register(subparsers) -> None`, which calls `subparsers.add_parser("<name>", help=...)`, adds its arguments, and `set_defaults(handler=<fn>)`. Handler: `handler(args, store: Store, out: TextIO) -> int`. A handler raises `LedgerError` for user errors; it never calls `sys.exit` or prints to stderr itself. Adding a subcommand = adding one file; nothing else changes.
- Owns: `sandbox/ledger/__init__.py` (empty), `sandbox/ledger/cli.py`, `sandbox/ledger/commands/__init__.py` (empty), `tests/ledger_support.py`.
- Test seam (highest seam, used by every slice): `tests/ledger_support.py` provides `class LedgerTestCase(unittest.TestCase)`:
  - `setUp`: `TemporaryDirectory()`; `self.db_path = <tmp>/ledger.db`; `patch.dict(os.environ, {"SANDBOX_LEDGER_DB": self.db_path})` with `SANDBOX_LICENSE_KEY` removed; both undone by `addCleanup`.
  - `self.run_cli(*argv, env: dict | None = None) -> CliResult(code: int, out: str, err: str)`: calls `sandbox.__main__.main(["ledger", *argv])` under `redirect_stdout`/`redirect_stderr` to `StringIO`, converts `SystemExit` to its code. `env` is applied with a nested `patch.dict` for that call only.
  - `self.write_file(name: str, text: str, encoding="utf-8") -> str`: writes into the temp dir, returns the path (for CSV inputs, BOM cases via `encoding="utf-8-sig"`).
  - Tests assert on `code`, `out`, `err` only; no test imports a command module or the Store directly, except billing's key tests (see billing).
- Uses: ledger.model (errors), ledger.store.

### ledger.model (values, validation, errors)
- Interface (all pure, no I/O):
  - `@dataclass(frozen=True) class Expense: date: str; amount_cents: int; category: str; note: str = ""; id: int | None = field(default=None, compare=False)`. Equality (and so the duplicate key) is `(date, amount_cents, category, note)`.
  - `make_expense(date: str, amount: str, category: str, note: str | None) -> Expense`: validates raw text through the parsers below.
  - `parse_amount(text: str, *, allow_zero: bool = False) -> int`: after `strip()`, must `re.fullmatch(r"[0-9]+(\.[0-9]{1,2})?")`; value `> 0` (or `>= 0` with `allow_zero`) and `<= 9_999_999_999` cents (99,999,999.99). `"12.5"` -> 1250, `"40"` -> 4000.
  - `format_cents(cents: int) -> str`: `"12.50"`, `"0.00"`, negative as `"-12.50"`.
  - `parse_date(text: str) -> str`: `fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")` then `date.fromisoformat` for calendar validity; returns the same string.
  - `parse_month(text: str) -> str`: `fullmatch(r"[0-9]{4}-(0[1-9]|1[0-2])")`.
  - `parse_category(text: str) -> str`: `strip().casefold()`, non-empty, no `\t\r\n`, max 64 chars.
  - `parse_note(text: str | None) -> str`: `None` -> `""`; `strip()`; no `\t\r\n`; max 200 chars.
  - `CSV_COLUMNS: tuple[str, ...] = ("date", "amount", "category", "note")` (the pinned CSV contract, see Data model).
  - `class LedgerError(Exception)`: `exit_code: int = 1`. `class ValidationError(LedgerError)`. Messages name the bad value in quotes, e.g. `bad amount '12.5.0'`, `bad date '2026-02-30'`, `bad month '2026-13'`, `empty category`.
- Owns: `sandbox/ledger/model.py`, `tests/test_ledger_model.py` (optional table tests of the parsers; all behaviour must also be reachable through the CLI).
- Test seam: through the CLI (`add`, `import`, `budget set`, `report --month`); a pure table test of the parsers is allowed as an internal seam.
- Uses: nothing.

### ledger.store (SQLite)
- Interface:
  - `open_store(path: str | os.PathLike | None = None) -> Store`: `None` -> `os.environ.get("SANDBOX_LEDGER_DB") or "./ledger.db"`. Connects with `sqlite3.connect(path, autocommit=False)`, creates the schema if absent (idempotent), sets `PRAGMA user_version = 1`. Does not create parent directories (missing dir -> `sqlite3.Error` -> exit 1).
  - `class Store` (context manager; `close()` on exit):
    - `add(expenses: Iterable[Expense]) -> list[int]`: inserts all in **one** transaction (all or nothing), returns new ids.
    - `expenses(month: str | None = None) -> list[Expense]`: with ids, ordered by `date, id`; `month` filters `date LIKE month || '-%'`.
    - `set_budget(category: str, amount_cents: int) -> None`: upsert.
    - `budgets() -> dict[str, int]`: category -> cents.
    - `close() -> None`.
  - Takes already-validated values; the DB `CHECK`s are a backstop, not the validation path.
- Owns: `sandbox/ledger/store.py`.
- Test seam: through the CLI via `LedgerTestCase` (temp DB per test). The Store is the only adapter at its seam; there is no fake.
- Uses: ledger.model.

### ledger.commands.add + list (slice 01)
- Interface:
  - `ledger add AMOUNT CATEGORY [--date YYYY-MM-DD] [--note TEXT]`: date defaults to `date.today().isoformat()`. stdout: `added <id> <date> <amount> <category>` (e.g. `added 1 2026-10-03 12.50 groceries`). Exit 0.
  - `ledger list [--month YYYY-MM]`: one line per Expense, ordered by `(date, id)`: `<date>\t<amount>\t<category>\t<note>` (note may be empty; the trailing tab stays). No Expenses: no output, exit 0.
- Owns: `sandbox/ledger/commands/add.py`, `sandbox/ledger/commands/listing.py`, `tests/test_ledger_add_list.py`.
- Test seam: `LedgerTestCase.run_cli`. Tests pass `--date` except one test of the default, which compares with `date.today()` read inside the test.
- Uses: ledger.model, ledger.store.

### ledger.commands.budget (slice 02)
- Interface:
  - `ledger budget set CATEGORY AMOUNT`: `parse_amount(allow_zero=True)`; upsert. stdout: `budget <category> <amount>`. Exit 0.
  - `ledger budget list`: `<category>\t<amount>` per Budget, by category. None: no output.
  - Nested `add_subparsers(required=True)` under `budget`, owned by this module.
- Owns: `sandbox/ledger/commands/budget.py`, `tests/test_ledger_budget.py`.
- Test seam: `run_cli`.
- Uses: ledger.model, ledger.store.

### ledger.commands.import (slice 03)
- Interface:
  - `ledger import PATH`: reads the CSV below, validates every row, then writes all new rows in one `Store.add` call. stdout: `imported <N>, skipped <M> duplicates`. Exit 0.
  - **Atomic**: any bad row -> exit 1, nothing written, stderr `ledger: error: <path> line <n>: <reason>` with `n` = `reader.line_num` (1 = header).
  - **Duplicates (multiset)**: for each Expense key, `skipped = min(count in file, count already in DB before this import)`; the rest are imported. So re-importing a file skips every row, importing an export into an empty DB skips none, and two genuinely identical Expenses survive an export/import round trip.
  - Internal function (same file): `import_expenses(store: Store, path: str) -> tuple[int, int]`.
- Owns: `sandbox/ledger/commands/import_csv.py`, `tests/test_ledger_import.py`, `tests/fixtures/` (incl. `tests/fixtures/expenses.csv`).
- Fixture rules: `tests/fixtures/expenses.csv` uses the pinned header, all dates in `2026-10`, has no row equal to the two journey `add` Expenses, and no repeated rows (the journey expects `skipped 0` on first import). Must include at least one `groceries` row.
- Test seam: `run_cli` with files from `write_file` or `tests/fixtures/`.
- Uses: ledger.model, ledger.store.

### ledger.report (slice 04)
- Interface:
  - `@dataclass(frozen=True) class ReportRow: category: str; spent_cents: int; budget_cents: int | None` with `remaining_cents` (`None` when no Budget) and `over` (`budget is not None and spent > budget`).
  - `@dataclass(frozen=True) class Report: month: str; rows: list[ReportRow]; spent_cents: int`.
  - `build_report(store: Store, month: str) -> Report`: one row per Category that has an Expense in the Month **or** a Budget; sorted by category.
  - `render_report(report: Report) -> str` (exact text below).
  - CLI `ledger report --month YYYY-MM` (required) in `commands/report.py` prints `render_report`.
- Output (tab-separated, `\n` line ends):
  ```
  category	spent	budget	remaining
  groceries	12.50	200.00	187.50
  rent	900.00	800.00	-100.00	OVER
  transport	40.00	-	-
  TOTAL	952.50	1000.00	87.50
  ```
  `TOTAL`: spent = all Expenses in the Month; budget and remaining = sums over rows that have a Budget, or `-` if no row has one. `TOTAL` is upper case, so it cannot clash with a (casefolded) Category. Empty Month with no Budgets: header + `TOTAL	0.00	-	-`.
- Owns: `sandbox/ledger/report.py`, `sandbox/ledger/commands/report.py` (06 also edits this file, see billing), `tests/test_ledger_report.py`.
- Test seam: `run_cli`.
- Uses: ledger.model, ledger.store.

### ledger.commands.export (slice 05)
- Interface: `ledger export [--format csv|json]` (default `csv`) to stdout, all Expenses ordered by `(date, id)`. Exit 0. Empty DB: CSV header only / `{"expenses": [], "format": "ledger-export", "version": 1}`.
- Owns: `sandbox/ledger/commands/export.py`, `tests/test_ledger_export.py`.
- Test seam: `run_cli`; the round-trip test pipes `export` output through `write_file` into `import` against a second temp DB (`env={"SANDBOX_LEDGER_DB": ...}`).
- Uses: ledger.model (`CSV_COLUMNS`, `format_cents`), ledger.store.

### billing (slice 06, Risk: license, sensitive path)
- Interface:
  - `sandbox/billing/license.py`:
    - `check_license(key: str | None) -> None`: raises `LicenseError` (subclass of `LedgerError`, `exit_code = 3`) when missing/empty or invalid.
    - `issue_key(subject: str) -> str`: used only by `scripts/seed.py` and tests.
  - `sandbox/billing/detailed.py`: `render_detailed(store: Store, month: str) -> str`: `render_report(build_report(...))` followed by the detail block below.
  - CLI: 06 adds `--detailed` (store_true) to `ledger report` in `sandbox/ledger/commands/report.py`. With `--detailed`, the handler calls `check_license(os.environ.get("SANDBOX_LICENSE_KEY"))` **before** writing anything, then prints `render_detailed`.
  - `scripts/seed.py --license`: prints `issue_key("owner")` and a newline. Inserts the repo root (`Path(__file__).resolve().parents[1]`) into `sys.path` before importing `sandbox` (running `python3 scripts/seed.py` puts `scripts/` first on `sys.path`, not the repo root). No arguments: output unchanged.
- License key (pinned):
  - Format: `LEDGER1-<subject>-<mac>`, full regex `LEDGER1-([a-z0-9]{1,32})-([0-9a-f]{64})` via `re.fullmatch` on `key.strip()`.
  - `mac = hmac.new(TEST_SECRET, f"LEDGER1-{subject}".encode("ascii"), "sha256").hexdigest()`.
  - `TEST_SECRET = b"forge-sandbox-ledger-test-secret-v1"  # gitleaks:allow`, a fixed constant in `license.py`. Not a real secret; no expiry, no network.
  - Verify with `hmac.compare_digest(expected_hex, given_hex)` (both ASCII `str`).
  - Messages (stderr, exit 3, stdout empty): missing/empty -> `ledger: upgrade: --detailed needs a license key in SANDBOX_LICENSE_KEY`; invalid -> `ledger: upgrade: SANDBOX_LICENSE_KEY is not a valid license key`. Both start `ledger: upgrade:` (`LicenseError` overrides the `ledger: error:` prefix).
- Detailed block (appended after the normal Report, `\n` line ends):
  ```

  ## groceries
  2026-10-03	12.50	groceries	market
  ## transport
  2026-10-05	40.00	transport
  ## top 3
  2026-10-05	40.00	transport
  2026-10-03	12.50	groceries	market
  ```
  One `## <category>` section per Category with spending in the Month (Budget-only rows have no section), lines in `list` format ordered by `(date, id)`. `## top 3`: the 3 largest Expenses of the Month by `amount desc, date asc, id asc`; fewer if fewer exist; header always printed.
- Owns: `sandbox/billing/__init__.py`, `sandbox/billing/license.py`, `sandbox/billing/detailed.py`, `scripts/seed.py`, `tests/test_billing_detailed.py`.
- Test seam: `run_cli("report", "--month", ..., "--detailed", env={"SANDBOX_LICENSE_KEY": issue_key("owner")})`. Key-format tests may call `check_license` directly (internal seam). One test runs `scripts/seed.py --license` as a subprocess (`sys.executable`) and checks the key passes `check_license`.
- Uses: ledger.model, ledger.store, ledger.report.

### Untouched by the project
`AGENTS.md`, `CLAUDE.md`, `GLOSSARY.md`, `.env.example`, `.claude/`, `.github/` (workflows, dependabot), `.pre-commit-config.yaml`, `specs/`. A slice that needs to change one says so in its spec and the coordinator treats it as shape-changing.

## Data model

SQLite file at `SANDBOX_LEDGER_DB` (default `./ledger.db`), created by `open_store`:

```sql
CREATE TABLE IF NOT EXISTS expense (
  id           INTEGER PRIMARY KEY,
  date         TEXT    NOT NULL CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  category     TEXT    NOT NULL CHECK (category <> ''),
  note         TEXT    NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS expense_date ON expense (date);
CREATE TABLE IF NOT EXISTS budget (
  category     TEXT    PRIMARY KEY CHECK (category <> ''),
  amount_cents INTEGER NOT NULL CHECK (amount_cents >= 0)
);
PRAGMA user_version = 1;
```

No unique index on `expense`: identical Expenses are legal (see import duplicates rule). Schema changes after 01 are a shape change (pause and ask).

**CSV (import and export)**, pinned:
- UTF-8. Import accepts an optional BOM (`utf-8-sig`); export writes none. `newline=''` on open; export `lineterminator="\n"`, default `excel` dialect quoting (minimal).
- Header row exactly `date,amount,category,note` on export (from `model.CSV_COLUMNS`).
- Import header rules: names compared after `strip().casefold()`; any order; `date`, `amount`, `category` required, `note` optional; extra named columns ignored; a repeated required name is an error; empty file (no header) is an error.
- `amount` is decimal text (`12.50`), never cents. `note` empty string when none.
- Example:
  ```
  date,amount,category,note
  2026-10-03,12.50,groceries,market
  2026-10-05,40.00,transport,
  ```

**JSON export**, pinned (`json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=True)` + `\n`):
```json
{
  "expenses": [
    {
      "amount_cents": 1250,
      "category": "groceries",
      "date": "2026-10-03",
      "note": "market"
    }
  ],
  "format": "ledger-export",
  "version": 1
}
```
No `id`, no Budgets, no float amounts. JSON import is out of scope.

## Shared files
Only `01-skeleton` creates or edits these; a later slice that must change one lists it in Owns and is treated as shape-changing:
- `sandbox/__main__.py` (register `ledger`, dispatch to `ledger.cli.run`)
- `sandbox/ledger/__init__.py`, `sandbox/ledger/cli.py`, `sandbox/ledger/commands/__init__.py`
- `sandbox/ledger/model.py`, `sandbox/ledger/store.py`
- `tests/ledger_support.py`
- `.gitignore` (adds `ledger.db`)
- `README.md` (one `sandbox ledger` usage line)

Known exception: `sandbox/ledger/commands/report.py` is created by 04 and edited by 06 (adds `--detailed`). 06 depends on 04, so the edits never run in parallel.

No CI or lint config change is needed: `ci.yml` already runs `uvx ruff check .` and `python3 -m unittest -v`, which discovers `tests/test_*.py`.

## Review focus
- `add 12.5.0 x`, `add 1,000 x`, `add .5 x`, `add 12. x`, `add 12.345 x`, `add +5 x`, `add 1e3 x`, `add ١٢ x` (Arabic-Indic digits) -> exit 1, `ledger: error: bad amount '<text>'`, nothing stored (01)
- `add -3 x` -> argparse passes `-3` as the positional (no negative-number-like options), exit 1 `bad amount '-3'`; `add 0 x` -> exit 1 (01)
- `add 100000000.00 x` (over the cap) -> exit 1 (01)
- `add 12.5 x` then `list` -> shows `12.50` (01); CSV `12.5` and `12.50` for the same row are duplicates (03)
- `--date 2026-02-30`, `--date 2026-13-01`, `--date 03/10/2026`, `--date 20261003`, `--date 2026-W40-1` -> exit 1 `bad date` (01; also as CSV cells, 03)
- `add 5 "  Groceries "` then `add 5 groceries` -> both listed under `groceries`; `budget set GROCERIES 200` applies to them in the Report (01, 02, 04)
- Empty or whitespace Category, or Category/note containing tab or newline -> exit 1 (01, 03)
- `budget set groceries -3` -> exit 1; `budget set groceries 0` -> exit 0, then any spending shows `OVER` (02, 04)
- `budget set` twice for one Category -> last value wins (02)
- CSV with UTF-8 BOM (Excel "CSV UTF-8") -> header still recognised, imports normally (03)
- CSV header `Date,Amount,Category` (capitalised, no note column) or columns reordered -> imports (03)
- CSV with extra column `account` -> ignored; a row with more fields than the header -> exit 1 `line <n>: too many fields`, nothing imported (03)
- CSV missing `amount` column -> exit 1 `missing column 'amount'`; empty file -> exit 1; header only -> `imported 0, skipped 0 duplicates` (03)
- CSV with one bad row among good ones (e.g. line 7 amount `12.5.0`) -> exit 1 `<path> line 7: bad amount '12.5.0'`, zero rows written (03)
- CSV that is Latin-1, not UTF-8 -> exit 1 `<path>: not UTF-8`; missing path -> exit 1 `cannot read <path>` (03)
- Blank lines inside the CSV -> skipped, not errors (03)
- Same file imported twice -> second run `imported 0, skipped N duplicates`; file with two identical rows into an empty DB -> `imported 2, skipped 0` (03)
- `export --format csv` then import into an empty DB -> `skipped 0 duplicates` and an identical Report (03, 05; journey)
- Note with a comma or quote -> export quotes it, import restores it exactly (05)
- `report --month 2026-1`, `--month 2026-13`, `--month 2026-10-01` -> exit 1 `bad month` (04)
- `report --month 2030-01` (empty Month, no Budgets) -> header + `TOTAL	0.00	-	-`, exit 0; with Budgets -> those rows with `0.00` spent (04)
- Spent exactly equal to Budget -> no `OVER`; one cent more -> `OVER`, remaining `-0.01` (04)
- Expenses on `2026-09-30` and `2026-11-01` not counted in `2026-10` (04)
- `--detailed` with no key, empty key, whitespace key, wrong mac, upper-case mac, valid mac for another subject, truncated key -> exit 3, `ledger: upgrade: ...` on stderr, **empty stdout** (06)
- `--detailed` with a valid key plus surrounding whitespace/newline (e.g. pasted from `$(...)`) -> accepted (06)
- Month with fewer than 3 Expenses and `--detailed` -> `## top 3` lists what exists; ties broken by date then id (06)
- `SANDBOX_LEDGER_DB` pointing into a missing directory -> exit 1 `ledger: error: database: ...` (01)
- `SANDBOX_LEDGER_DB=""` -> uses `./ledger.db` (01); tests never do this
- `python3 -m sandbox greet ada` -> still `hello, ada` (01)
- `python3 scripts/seed.py` with no args -> unchanged users JSON (06)
