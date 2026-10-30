#!/usr/bin/env python3
"""Contract identity of a /plan-project folder: what a run was approved to build.

Usage:
  contract_hash.py snapshot <specs folder> <snapshot.json>   # at run start; prints the hash
  contract_hash.py check <specs folder> <snapshot.json>      # on resume; exit 0 OK, 1 changed, 2 error

The contract is every *.md file in the folder, with `Status:` lines before the first `## `
heading removed. `check` allows exactly two kinds of change since the snapshot, which agents
make for defaults and owner answers:
- table rows appended right after the last row of an existing table in a `## Decisions` section;
- a `## Decisions` section (heading, blank lines, table rows) added to a file that had none,
  at its end, just before its trailing `Field: value` lines (`Depends on:`, `Owns:`), or right
  before an existing `## ` heading.
Anything else is reported as `CHANGED <file>`.
"""

import difflib
import hashlib
import json
import re
import sys
from pathlib import Path

DECISIONS = "## Decisions"
FIELD = re.compile(r"^[A-Z][A-Za-z ]*: ")


def normalise(text):
    lines, in_head = [], True
    for line in text.splitlines():
        line = line.rstrip()
        if line.startswith("## "):
            in_head = False
        if in_head and line.startswith("Status:"):
            continue
        lines.append(line)
    while lines and not lines[-1]:
        lines.pop()
    return lines


def contract_files(folder):
    folder = Path(folder)
    if not (folder / "plan.md").is_file():
        print(
            f"error: {folder}/plan.md not found (pass the specs folder by absolute path)",
            file=sys.stderr,
        )
        sys.exit(2)
    return {
        f.name: normalise(f.read_text(encoding="utf-8"))
        for f in sorted(folder.glob("*.md"))
    }


def sections(lines):
    """Heading of the `## ` section each line belongs to; headings inside ``` fences don't count."""
    out, current, fenced = [], None, False
    for line in lines:
        if line.lstrip().startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("## "):
            current = line.strip()
        out.append(current)
    return out


def is_row(line):
    return line.startswith("|")


def appended_rows(old, old_sec, i, inserted):
    """Rows inserted at old index i, right after the last row of a Decisions table."""
    return (
        all(is_row(line) for line in inserted)
        and i > 0
        and is_row(old[i - 1])
        and old_sec[i - 1] == DECISIONS
        and (i == len(old) or not is_row(old[i]))
    )


def trailing_fields_start(lines):
    """Start of the final block of blank and `Field: value` lines (a slice's `Depends on:` / `Owns:`)."""
    i = len(lines)
    while i > 0 and (not lines[i - 1] or FIELD.match(lines[i - 1])):
        i -= 1
    return i


def at_section_boundary(old, old_sec, i):
    """True if the next non-blank old line from i is a real (unfenced) `## ` heading."""
    while i < len(old) and not old[i]:
        i += 1
    return i < len(old) and old[i].startswith("## ") and old_sec[i] == old[i].strip()


def appended_section(old, old_sec, i, inserted):
    """A new Decisions section in a file that had none: at its end, before its trailing fields,
    or right before an existing `## ` heading (so no existing line moves into it)."""
    body = [line for line in inserted if line]
    return (
        (i >= trailing_fields_start(old) or at_section_boundary(old, old_sec, i))
        and DECISIONS not in old
        and body
        and body[0] == DECISIONS
        and all(is_row(line) for line in body[1:])
    )


def file_changed(old, new):
    if old == new:
        return False
    if old is None or new is None:
        return True
    old_sec = sections(old)
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(
        a=old, b=new, autojunk=False
    ).get_opcodes():
        if tag == "equal":
            continue
        inserted = new[j1:j2]
        if tag != "insert" or not (
            appended_rows(old, old_sec, i1, inserted)
            or appended_section(old, old_sec, i1, inserted)
        ):
            return True
    return False


def main(argv):
    if len(argv) != 4 or argv[1] not in ("snapshot", "check"):
        print(__doc__)
        return 2
    mode, folder, snap = argv[1], argv[2], Path(argv[3])
    current = contract_files(folder)
    if mode == "snapshot":
        text = json.dumps(current, ensure_ascii=False, indent=0, sort_keys=True)
        snap.parent.mkdir(parents=True, exist_ok=True)
        snap.write_text(text, encoding="utf-8")
        print(hashlib.sha256(text.encode("utf-8")).hexdigest())
        return 0
    try:
        approved = json.loads(snap.read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        print(f"error: snapshot {snap} unreadable: {err}", file=sys.stderr)
        return 2
    changed = [
        n
        for n in sorted(set(approved) | set(current))
        if file_changed(approved.get(n), current.get(n))
    ]
    for name in changed:
        print(f"CHANGED {name}")
    if not changed:
        print("OK")
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
