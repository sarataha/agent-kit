"""Tests for skills/plan-project/contract_hash.py (snapshot/check) against copies of the ledger specs.

The fixture is the real ledger layout: 03 and 04 have `Depends on:` / `Owns:` after a `## Decisions` section,
and plan.md's Decisions table holds core requirements. Attack cases come from adversarial reviews.
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parent.parent
    / "skills"
    / "plan-project"
    / "contract_hash.py"
)
LEDGER = Path(__file__).resolve().parent / "fixtures" / "ledger-specs"
LAST_PLAN_ROW = (
    "| Size of 01 | Keep 01-skeleton as one slice; splitting gains no parallelism. |"
)


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
    )


class ContractTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.specs = self.tmp / "ledger"
        shutil.copytree(LEDGER, self.specs)
        self.snap = self.tmp / "run" / "contract.json"
        p = run("snapshot", self.specs, self.snap)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.digest = p.stdout.strip()

    def check(self):
        return run("check", self.specs, self.snap)

    def edit(self, name, old, new):
        p = self.specs / name
        text = p.read_text()
        self.assertEqual(text.count(old), 1, f"fixture text in {name}: {old!r}")
        p.write_text(text.replace(old, new))

    def append(self, name, text):
        p = self.specs / name
        p.write_text(p.read_text().rstrip("\n") + "\n" + text)

    def assertOK(self):
        p = self.check()
        self.assertEqual(
            (p.returncode, p.stdout.strip()), (0, "OK"), p.stdout + p.stderr
        )

    def assertChanged(self, *names):
        p = self.check()
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        for n in names:
            self.assertIn(f"CHANGED {n}", p.stdout)

    def decisions_table_end(self, name):
        """Index just after the last row of the first table in `## Decisions`."""
        text = (self.specs / name).read_text()
        start = text.index("|---", text.index("## Decisions"))
        pos = text.index("\n", start) + 1
        while text.startswith("|", pos):
            pos = text.index("\n", pos) + 1
        return text, pos

    # Fixture shape
    def test_fixture_has_fields_after_decisions(self):
        text = (self.specs / "04-report.md").read_text()
        self.assertLess(text.index("## Decisions"), text.index("Owns:"))

    # Allowed
    def test_unchanged_ok_and_snapshot_hash_stable(self):
        self.assertOK()
        self.assertEqual(
            run("snapshot", self.specs, self.tmp / "again.json").stdout.strip(),
            self.digest,
        )

    def test_status_line_in_header_ignored(self):
        self.edit("plan.md", "Status: approved", "Status: draft")
        self.assertOK()

    def test_row_appended_to_plan_decisions_ok(self):
        self.edit("plan.md", LAST_PLAN_ROW, LAST_PLAN_ROW + "\n| New default | x |")
        self.assertOK()

    def test_rows_appended_to_slice_decisions_ok(self):
        text, end = self.decisions_table_end("04-report.md")
        (self.specs / "04-report.md").write_text(
            text[:end] + "| a | b |\n| c | d |\n" + text[end:]
        )
        self.assertOK()

    def test_new_decisions_section_at_end_ok(self):
        self.append(
            "02-budgets.md",
            "\n## Decisions\n\n| Question | Answer |\n|---|---|\n| q | a |\n",
        )
        self.assertOK()

    def test_new_decisions_section_before_slice_fields_ok(self):
        self.edit(
            "02-budgets.md",
            "\nDepends on:",
            "\n## Decisions\n\n| q | a |\n|---|---|\n| x | y |\n\nDepends on:",
        )
        self.assertOK()

    def test_ledger_run_history_ok(self):
        """Real ledger run: 03, 04 and 05 got their Decisions sections above `Depends on:`."""
        first = self.tmp / "first"
        shutil.copytree(self.specs, first)
        for name in ("03-import.md", "04-report.md"):
            text = (first / name).read_text()
            start = text.index("## Decisions")
            end = text.index("\nDepends on:", start)
            (first / name).write_text(text[:start] + text[end + 1 :])
        run("snapshot", first, self.snap)
        self.assertOK()

    def test_new_section_before_fields_with_field_edit_detected(self):
        self.edit(
            "02-budgets.md",
            "\nDepends on: 01",
            "\n## Decisions\n\n| q | a |\n\nDepends on: 05",
        )
        self.assertChanged("02-budgets.md")

    def test_crlf_rewrite_ok(self):
        p = self.specs / "03-import.md"
        p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
        self.assertOK()

    # Contract changes
    def test_owns_after_decisions_detected(self):
        self.edit(
            "04-report.md",
            "Owns: sandbox/ledger/report.py",
            "Owns: sandbox/, sandbox/ledger/report.py",
        )
        self.assertChanged("04-report.md")

    def test_depends_after_decisions_detected(self):
        self.edit("04-report.md", "Depends on: 02", "Depends on: 05")
        self.assertChanged("04-report.md")

    def test_plan_decision_value_change_detected(self):
        self.edit("plan.md", "exit 3 (exit 2", "exit 4 (exit 2")
        self.assertChanged("plan.md")

    def test_plan_decision_row_deleted_detected(self):
        p = self.specs / "plan.md"
        lines = p.read_text().splitlines(keepends=True)
        p.write_text("".join(ln for ln in lines if not ln.startswith("| Storage |")))
        self.assertChanged("plan.md")

    def test_slice_decision_row_edited_detected(self):
        text = (self.specs / "03-import.md").read_text()
        start = text.index("|---", text.index("## Decisions"))
        row = text.index("\n|", start) + 1
        (self.specs / "03-import.md").write_text(
            text[:row] + "| changed | changed |" + text[text.index("\n", row) :]
        )
        self.assertChanged("03-import.md")

    def test_row_inserted_mid_decisions_table_detected(self):
        self.edit("plan.md", "| Run budget |", "| New default | x |\n| Run budget |")
        self.assertChanged("plan.md")

    def test_row_before_separator_detected(self):
        self.edit(
            "plan.md",
            "| Question | Answer |",
            "| Question | Answer |\n| sneaky | row |",
        )
        self.assertChanged("plan.md")

    def test_blank_line_splitting_table_detected(self):
        self.edit("plan.md", LAST_PLAN_ROW, LAST_PLAN_ROW + "\n\n| split | row |")
        self.assertChanged("plan.md")

    def test_decisions_heading_over_run_settings_detected(self):
        self.edit("plan.md", "## Run settings", "## Run settings\n\n## Decisions")
        self.assertChanged("plan.md")

    def test_decisions_heading_in_slice_acceptance_detected(self):
        self.edit("05-export.md", "## Acceptance", "## Acceptance\n## Decisions")
        self.assertChanged("05-export.md")

    def test_decisions_heading_and_row_in_slices_table_detected(self):
        self.edit(
            "plan.md",
            "| 06 | 06-detailed",
            "## Decisions\n| 07 | 07-x |\n| 06 | 06-detailed",
        )
        self.assertChanged("plan.md")

    def test_new_decisions_section_at_heading_boundary_ok(self):
        """Real notes run: the 02 implementer added Decisions between `## Risk` and `## Interfaces`."""
        self.edit(
            "02-budgets.md",
            "\n## Interfaces",
            "\n## Decisions\n| Question | Answer |\n|---|---|\n| q | a |\n\n## Interfaces",
        )
        self.assertOK()

    def test_new_decisions_section_at_architecture_boundary_ok(self):
        text = (self.specs / "architecture.md").read_text()
        i = text.index("\n## ", len(text) // 2)
        (self.specs / "architecture.md").write_text(
            text[:i] + "\n\n## Decisions\n\n| q | a |\n" + text[i:]
        )
        self.assertOK()

    def test_new_decisions_section_mid_section_detected(self):
        text = (self.specs / "architecture.md").read_text()
        h = text.index("\n## ", len(text) // 2)
        i = text.index("\n", h + 1)
        (self.specs / "architecture.md").write_text(
            text[:i] + "\n## Decisions\n| q | a |" + text[i:]
        )
        self.assertChanged("architecture.md")

    def test_second_decisions_section_at_end_detected(self):
        self.append("04-report.md", "\n## Decisions\n\n| q | a |\n")
        self.assertChanged("04-report.md")

    def test_rows_after_fenced_decisions_heading_detected(self):
        self.append("02-budgets.md", "\n```\n## Decisions\n```\n")
        self.snap.unlink()
        run("snapshot", self.specs, self.snap)
        self.append("02-budgets.md", "| sneaky | row |\n")
        self.assertChanged("02-budgets.md")

    def test_status_line_in_body_detected(self):
        self.edit(
            "05-export.md", "## Acceptance", "## Acceptance\nStatus: anything goes"
        )
        self.assertChanged("05-export.md")

    def test_architecture_change_detected(self):
        self.edit("architecture.md", "exit_code = 3", "exit_code = 4")
        self.assertChanged("architecture.md")

    def test_acceptance_change_detected(self):
        self.edit(
            "05-export.md", "## Acceptance", "## Acceptance\n- [ ] New requirement."
        )
        self.assertChanged("05-export.md")

    def test_table_row_outside_decisions_detected(self):
        self.edit("plan.md", "## Slices", "## Slices\n| 99 | extra | none | none | 5 |")
        self.assertChanged("plan.md")

    def test_new_slice_detected(self):
        shutil.copy(self.specs / "02-budgets.md", self.specs / "07-extra.md")
        self.assertChanged("07-extra.md")

    def test_odd_named_file_detected(self):
        shutil.copy(self.specs / "02-budgets.md", self.specs / "07-Backdoor.md")
        self.assertChanged("07-Backdoor.md")

    def test_removed_slice_detected(self):
        (self.specs / "06-detailed-report.md").unlink()
        self.assertChanged("06-detailed-report.md")

    def test_reports_every_changed_file(self):
        self.edit("architecture.md", "exit_code = 3", "exit_code = 4")
        self.edit("05-export.md", "## Acceptance", "## Acceptance\n- [ ] x")
        self.assertChanged("architecture.md", "05-export.md")

    # Snapshot format and errors
    def test_marker_like_line_unchanged_ok(self):
        self.append("03-import.md", "=== 99-phantom.md\n")
        self.snap.unlink()
        run("snapshot", self.specs, self.snap)
        self.assertOK()

    def test_missing_folder_is_error(self):
        p = run("snapshot", self.tmp / "nope", self.tmp / "x.json")
        self.assertEqual(p.returncode, 2, p.stdout)
        self.assertFalse((self.tmp / "x.json").exists())
        self.assertEqual(run("check", self.tmp / "nope", self.snap).returncode, 2)

    def test_unreadable_snapshot_is_error(self):
        self.snap.write_text("{not json")
        self.assertEqual(self.check().returncode, 2)


if __name__ == "__main__":
    unittest.main()
