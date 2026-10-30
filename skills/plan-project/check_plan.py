#!/usr/bin/env python3
"""Check a /plan-project folder: required files and sections, dependency graph, file ownership.

Usage: check_plan.py <repo>/specs/<project>
Prints each error and exits 1, or prints OK and the parallel waves.
"""

import posixpath
import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = [
    "## Outcome",
    "## Acceptance",
    "## Exercise",
    "## Out of scope",
    "## Risk",
]
SLICE_FILE = re.compile(r"^(\d{2})-[a-z0-9-]+\.md$")


def norm(path):
    return posixpath.normpath(path.strip().rstrip("*"))


def overlaps(a, b):
    a, b = norm(a), norm(b)
    return (
        a == "." or b == "." or a == b or a.startswith(b + "/") or b.startswith(a + "/")
    )


def field(text, name):
    m = re.search(rf"^{name}:\s*(.*)$", text, re.MULTILINE)
    if not m:
        return None
    return [
        v.strip()
        for v in m.group(1).split(",")
        if v.strip() and v.strip().lower() != "none"
    ]


def main(folder):
    folder = Path(folder)
    errors = []
    for name in ("plan.md", "architecture.md"):
        if not (folder / name).is_file():
            errors.append(f"missing {name}")
    plan = (folder / "plan.md").read_text() if (folder / "plan.md").is_file() else ""

    slices = {}
    for f in sorted(folder.glob("*.md")):
        if f.name in ("plan.md", "architecture.md"):
            continue
        if not SLICE_FILE.match(f.name):
            errors.append(f"{f.name}: slice files are named NN-<slug>.md")
            continue
        slices[f.stem] = f.read_text()
    if not slices:
        errors.append("no slice files")

    ids = {}
    for sid in slices:
        number = sid[:2]
        if number in ids:
            errors.append(f"duplicate slice number {number}: {ids[number]}, {sid}")
        else:
            ids[number] = sid
    if len(ids) != len(slices):
        return report(errors, {})
    deps, owns = {}, {}
    for sid, text in slices.items():
        for sec in REQUIRED_SECTIONS:
            if not re.search(rf"^{re.escape(sec)}\s*$", text, re.MULTILINE):
                errors.append(f"{sid}: missing section '{sec}'")
        if "- [ ]" not in text:
            errors.append(f"{sid}: Acceptance has no '- [ ]' items")
        d = field(text, "Depends on")
        o = field(text, "Owns")
        if d is None:
            errors.append(f"{sid}: missing 'Depends on:' line")
        if not o:
            errors.append(f"{sid}: missing or empty 'Owns:' line")
        for path in o or []:
            normalized = norm(path)
            if normalized.startswith(("/", "../")) or normalized == "..":
                errors.append(
                    f"{sid}: owned path '{path}' must be repo-relative and stay inside the repo"
                )
        resolved = []
        for dep in d or []:
            # Accept the full slice name ("03-links") or its number ("03").
            key = (
                dep
                if dep in slices
                else ids.get(dep)
                if re.fullmatch(r"\d{2}", dep)
                else None
            )
            if key is None:
                errors.append(f"{sid}: depends on unknown slice '{dep}'")
            elif key == sid:
                errors.append(f"{sid}: depends on itself")
            else:
                resolved.append(key)
        deps[sid], owns[sid] = resolved, o or []
        if plan and not re.search(rf"\|\s*{sid[:2]}\b|\|\s*{re.escape(sid)}\b", plan):
            errors.append(f"{sid}: not listed in plan.md Slices table")

    skeleton = ids.get("01")
    if not skeleton:
        errors.append("no 01-<slug> skeleton slice")
    elif deps.get(skeleton):
        errors.append(f"{skeleton}: the skeleton has no dependencies")

    # Cycles, then the ancestors of each slice.
    state, order = {}, []

    def visit(s, stack):
        if state.get(s) == "done":
            return
        if state.get(s) == "open":
            errors.append("dependency cycle: " + " -> ".join(stack + [s]))
            return
        state[s] = "open"
        for d in deps.get(s, []):
            visit(d, stack + [s])
        state[s] = "done"
        order.append(s)

    for s in slices:
        visit(s, [])
    if any("cycle" in e for e in errors):
        return report(errors, {})

    ancestors = {}
    for s in order:
        anc = set()
        for d in deps[s]:
            anc |= {d} | ancestors[d]
        ancestors[s] = anc
    if skeleton:
        for s in slices:
            if s != skeleton and skeleton not in ancestors[s]:
                errors.append(
                    f"{s}: does not depend on {skeleton} (directly or through other slices)"
                )

    names = sorted(slices)
    for i, a in enumerate(names):
        for b in names[i + 1 :]:
            if a in ancestors[b] or b in ancestors[a]:
                continue
            for pa in owns[a]:
                for pb in owns[b]:
                    if overlaps(pa, pb):
                        errors.append(
                            f"{a} and {b} can run in parallel but both own '{pa}' / '{pb}': add a dependency or split ownership"
                        )

    wave = {}
    for s in order:
        wave[s] = 1 + max((wave[d] for d in deps[s]), default=0)
    return report(errors, wave)


def report(errors, wave):
    if errors:
        for e in errors:
            print(f"ERROR {e}")
        return 1
    print("OK")
    for w in sorted(set(wave.values())):
        print(f"wave {w}: " + ", ".join(s for s in sorted(wave) if wave[s] == w))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
