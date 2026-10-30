#!/usr/bin/env python3
"""Token usage for a project run, by agent, slice, role and model. Local only.

Usage: usage.py <session.jsonl> <project> [--repo <repo>] [--since <marker>] [--label <heading>]

Reads the coordinator session transcript and its subagents/*.jsonl. Subagents whose
description starts with "<project> " count toward the project, named "<project> <NN> <role>".
Appends a markdown section to ~/.claude/project-usage/<repo>-<project>.md (or <project>.md
without --repo) and prints it.
Never write this output into a repo, spec, status file, commit or PR.
"""

import argparse
import json
from collections import defaultdict
from pathlib import Path

KEYS = ("output", "fresh_input", "cache_read")


def tally(path, marker=None):
    """Return {model: {output, fresh_input, cache_read, replies}} for one transcript."""
    out = defaultdict(lambda: dict.fromkeys(KEYS + ("replies",), 0))
    started, seen = marker is None, set()
    with open(path, encoding="utf-8") as fh:
        lines = list(fh)
    for line in lines:
        try:
            m = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not started:
            if m.get("type") == "user" and marker in json.dumps(
                m.get("message", {}).get("content", "")
            ):
                started = True
            continue
        msg = m.get("message") or {}
        u = msg.get("usage")
        if m.get("type") != "assistant" or not u or msg.get("id") in seen:
            continue
        seen.add(msg.get("id"))  # one API reply can span several transcript lines
        t = out[msg.get("model", "unknown")]
        t["output"] += u.get("output_tokens", 0)
        t["fresh_input"] += u.get("input_tokens", 0) + u.get(
            "cache_creation_input_tokens", 0
        )
        t["cache_read"] += u.get("cache_read_input_tokens", 0)
        t["replies"] += 1
    return out, started


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session")
    ap.add_argument("project")
    ap.add_argument(
        "--since",
        help="count the main session only after the first user message containing this text",
    )
    ap.add_argument("--label", default="run")
    ap.add_argument(
        "--repo", help="prefix the usage file name, so plan and run share one file"
    )
    a = ap.parse_args()

    rows = []  # (agent, slice, role, model, totals)
    main_t, found = tally(a.session, a.since)
    if not found:
        raise SystemExit(f"marker not found: {a.since}")
    for model, t in main_t.items():
        rows.append(("coordinator", "-", "coordinator", model, t))

    sub = Path(a.session).with_suffix("") / "subagents"
    for meta in sorted(sub.glob("*.meta.json")):
        desc = json.loads(meta.read_text()).get("description", "")
        if not desc.startswith(a.project + " "):
            continue
        parts = desc.split(maxsplit=2)
        slice_, role = (parts[1], parts[2]) if len(parts) == 3 else ("-", desc)
        transcript = meta.with_name(meta.name.replace(".meta.json", ".jsonl"))
        if transcript.is_file():
            for model, t in tally(transcript)[0].items():
                rows.append((desc, slice_, role, model, t))

    def table(title, key):
        agg = defaultdict(lambda: dict.fromkeys(KEYS, 0))
        for r in rows:
            for k in KEYS:
                agg[key(r)][k] += r[4][k]
        lines = [
            f"### {title}",
            "",
            "| | Output | Fresh input | Cache read |",
            "|---|---|---|---|",
        ]
        for name in sorted(agg):
            t = agg[name]
            lines.append(
                f"| {name} | {t['output']:,} | {t['fresh_input']:,} | {t['cache_read']:,} |"
            )
        return "\n".join(lines)

    total = {k: sum(r[4][k] for r in rows) for k in KEYS}
    text = (
        "\n\n".join(
            [
                f"## {a.label}",
                f"Total: output {total['output']:,} | fresh input {total['fresh_input']:,} | cache read {total['cache_read']:,}",
                table("By slice", lambda r: r[1]),
                table("By role", lambda r: r[2]),
                table("By model", lambda r: r[3]),
            ]
        )
        + "\n"
    )

    name = f"{a.repo}-{a.project}" if a.repo else a.project
    dest = Path.home() / ".claude" / "project-usage" / f"{name}.md"
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        dest.write_text(
            "Local only. Never copy into a repo, spec, status file, PR or issue.\n\n"
        )
    with dest.open("a", encoding="utf-8") as f:
        f.write(text + "\n")
    print(text)
    print(f"appended to {dest}")


if __name__ == "__main__":
    main()
