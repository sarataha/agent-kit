"""Hooks: acceptance-guard protects the tests and the marker; format-on-edit reports parse errors."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / "hooks"
MARKER = {
    "spec": "budgets",
    "files": ["tests/test_budgets.py"],
    "runner": ["pyproject.toml"],
    "cmd": "python3 -m unittest tests.test_budgets",
    "baseline": "abc123",
}


def run_hook(name: str, payload: dict, home: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(HOOKS / name)],
        input=json.dumps(payload),
        env={**os.environ, "HOME": str(home)},
        capture_output=True,
        text=True,
        check=False,
    )


@unittest.skipUnless(shutil.which("jq"), "hooks need jq")
class AcceptanceGuardTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name) / "home"
        self.home.mkdir()
        self.repo = Path(tmp.name) / "repo"
        (self.repo / ".claude").mkdir(parents=True)
        (self.repo / "tests").mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.marker = self.repo / ".claude" / "ship-acceptance.json"
        self.marker_text = json.dumps(MARKER, indent=2) + "\n"
        self.marker.write_text(self.marker_text)

    def decision(self, tool: str, tool_input: dict) -> str:
        res = run_hook(
            "acceptance-guard.sh",
            {
                "tool_name": tool,
                "tool_input": tool_input,
                "cwd": str(self.repo),
                "session_id": "s1",
            },
            self.home,
        )
        self.assertEqual(res.returncode, 0, res.stderr)
        if not res.stdout.strip():
            return "allow"
        return json.loads(res.stdout)["hookSpecificOutput"]["permissionDecision"]

    def bash(self, cmd: str) -> str:
        return self.decision("Bash", {"command": cmd})

    def test_edit_acceptance_test_denied(self):
        path = str(self.repo / "tests" / "test_budgets.py")
        self.assertEqual(self.decision("Write", {"file_path": path}), "deny")

    def test_other_file_allowed(self):
        path = str(self.repo / "tests" / "test_other.py")
        self.assertEqual(self.decision("Write", {"file_path": path}), "allow")

    def test_marker_reviewed_edit_allowed(self):
        new = self.marker_text.replace(
            '"baseline": "abc123"', '"baseline": "abc123",\n  "reviewed": "def456"'
        )
        self.assertEqual(
            self.decision("Write", {"file_path": str(self.marker), "content": new}),
            "allow",
        )
        edit = {
            "file_path": str(self.marker),
            "old_string": '"baseline": "abc123"',
            "new_string": '"baseline": "abc123", "reviewed": "def456"',
        }
        self.assertEqual(self.decision("Edit", edit), "allow")

    def test_marker_protected_fields_denied(self):
        for field, value in (
            ("files", []),
            ("cmd", "true"),
            ("baseline", "fff"),
            ("runner", []),
        ):
            changed = json.dumps({**MARKER, field: value})
            with self.subTest(field=field):
                self.assertEqual(
                    self.decision(
                        "Write", {"file_path": str(self.marker), "content": changed}
                    ),
                    "deny",
                )
        edit = {
            "file_path": str(self.marker),
            "old_string": '"tests/test_budgets.py"',
            "new_string": "",
        }
        self.assertEqual(self.decision("Edit", edit), "deny")
        multi = {
            "file_path": str(self.marker),
            "edits": [{"old_string": '"cmd": "', "new_string": '"cmd": "true || '}],
        }
        self.assertEqual(self.decision("MultiEdit", multi), "deny")

    def test_marker_edit_without_exact_match_denied(self):
        # The Edit tool can match curly quotes to straight ones; the hook can't check that edit.
        edit = {
            "file_path": str(self.marker),
            "old_string": "\u201ccmd\u201d: \u201c",
            "new_string": "\u201ccmd\u201d: \u201ctrue || ",
        }
        self.assertEqual(self.decision("Edit", edit), "deny")

    def test_marker_invalid_json_denied(self):
        self.assertEqual(
            self.decision("Write", {"file_path": str(self.marker), "content": "{"}),
            "deny",
        )

    def test_bash_writes_to_marker_denied(self):
        for cmd in (
            "echo '{}' > .claude/ship-acceptance.json",
            "jq '.files=[]' .claude/ship-acceptance.json > /tmp/m && mv /tmp/m .claude/ship-acceptance.json",
            "sed -i 's/abc/fff/' .claude/ship-acceptance.json",
            "python3 -c \"import json; json.dump({}, open('.claude/ship-acceptance.json','w'))\"",
            "python3 - <<'EOF'\nopen('.claude/ship-acceptance.json', 'w').write('{}')\nEOF",
            "cp /tmp/forged.json .claude/ship-acceptance.json",
        ):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.bash(cmd), "deny")

    def test_bash_reads_and_rm_of_marker_allowed(self):
        for cmd in (
            "cat .claude/ship-acceptance.json",
            "jq -r .cmd .claude/ship-acceptance.json",
            "rm -f .claude/ship-acceptance.json .claude/ship-next.md",
            "cp .claude/ship-acceptance.json /tmp/marker.bak",
            "python3 -c \"import json; print(json.load(open('.claude/ship-acceptance.json'))['cmd'])\"",
        ):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.bash(cmd), "allow")

    def test_bash_writes_to_test_denied(self):
        for cmd in (
            "echo x > tests/test_budgets.py",
            "python3 -c \"import os; open('tests/test_budgets.py','w').write('')\"",
            "node -e \"require('fs').writeFileSync('tests/test_budgets.py','')\"",
            "/usr/bin/python3 -c \"open('tests/test_budgets.py','w')\"",
            "python3 -c\"open('tests/test_budgets.py','w')\"",
            "python3 - <<'EOF'\nopen('tests/test_budgets.py', 'w')\nEOF",
            "bash -c 'cp /dev/null tests/test_budgets.py'",
            "mv tests/test_budgets.py /tmp/",
        ):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.bash(cmd), "deny")

    def test_bash_running_tests_allowed(self):
        for cmd in (
            "python3 -m unittest tests.test_budgets",
            "python3 -m pytest tests/test_budgets.py -q",
            "git diff abc123 -- tests/test_budgets.py",
            "cp tests/test_budgets.py /tmp/copy.py",
            "python3 -c 'import sys' && python3 -m pytest tests/test_budgets.py 2>&1",
            "bash -c 'python3 -m pytest tests/test_budgets.py'",
        ):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.bash(cmd), "allow")


@unittest.skipUnless(shutil.which("jq"), "hooks need jq")
class FormatOnEditTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def run_on(self, name: str, text: str) -> subprocess.CompletedProcess:
        path = self.dir / name
        path.write_text(text)
        return run_hook(
            "format-on-edit.sh", {"tool_input": {"file_path": str(path)}}, self.dir
        )

    def test_missing_file_ignored(self):
        res = run_hook(
            "format-on-edit.sh",
            {"tool_input": {"file_path": str(self.dir / "gone.py")}},
            self.dir,
        )
        self.assertEqual(res.returncode, 0)

    def test_yaml(self):
        if subprocess.run(
            ["python3", "-c", "import yaml"], capture_output=True, check=False
        ).returncode:
            self.skipTest("PyYAML not installed")
        self.assertEqual(self.run_on("ok.yml", "a: 1\n---\nb: 2\n").returncode, 0)
        tags = "Value: !Ref Bucket\nb: !Sub\n  - x\nc: !!python/name:os.system\n"
        self.assertEqual(self.run_on("cf.yml", tags).returncode, 0)
        bad = self.run_on("bad.yml", "a: [\n")
        self.assertEqual(bad.returncode, 2)
        self.assertIn("bad.yml", bad.stderr)


if __name__ == "__main__":
    unittest.main()
