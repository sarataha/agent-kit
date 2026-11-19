"""install.sh fills {{OWNER}} and {{PROJECTS}} and never touches skills it did not install."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def install(dest: Path, cfg: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "CLAUDE_DIR": str(dest)}
    return subprocess.run(
        [str(ROOT / "install.sh"), str(cfg)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


class InstallTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.dest = self.tmp / "claude"
        self.cfg = self.tmp / "config.json"
        self.cfg.write_text(
            json.dumps({"github_owner": "octo-dev", "projects_dir": "/work/repos"})
        )

    def test_fills_placeholders(self):
        res = install(self.dest, self.cfg)
        self.assertEqual(res.returncode, 0, res.stderr)
        text = "".join(
            p.read_text(errors="replace") for p in self.dest.rglob("*") if p.is_file()
        )
        self.assertNotIn("{{OWNER}}", text)
        self.assertNotIn("{{PROJECTS}}", text)
        oc_check = (self.dest / "skills/run-project/oc_check.sh").read_text()
        self.assertIn('"/work/repos/"*', oc_check)
        self.assertIn('"github.com/octo-dev/"', oc_check)

    def test_hooks_installed_executable(self):
        install(self.dest, self.cfg)
        for name in ("acceptance-guard.sh", "acceptance-stop.sh", "scan-output.sh"):
            self.assertTrue(os.access(self.dest / "hooks" / name, os.X_OK), name)

    def test_skips_foreign_skill(self):
        mine = self.dest / "skills" / "ship"
        mine.mkdir(parents=True)
        (mine / "SKILL.md").write_text("my own ship skill\n")
        res = install(self.dest, self.cfg)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("skip skill ship", res.stderr)
        self.assertEqual((mine / "SKILL.md").read_text(), "my own ship skill\n")

    def test_wire_hooks_merges_once(self):
        self.dest.mkdir()
        settings = self.dest / "settings.json"
        settings.write_text(
            json.dumps(
                {
                    "model": "opus",
                    "hooks": {
                        "Stop": [{"hooks": [{"type": "command", "command": "mine.sh"}]}]
                    },
                }
            )
        )
        example = json.loads((ROOT / "hooks/settings.example.json").read_text())[
            "hooks"
        ]

        def wire():
            env = {**os.environ, "CLAUDE_DIR": str(self.dest)}
            return subprocess.run(
                [str(ROOT / "install.sh"), "--wire-hooks", str(self.cfg)],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

        res = wire()
        self.assertEqual(res.returncode, 0, res.stderr)
        got = json.loads(settings.read_text())
        self.assertEqual(got["model"], "opus")
        self.assertTrue((self.dest / "settings.json.bak").exists())
        commands = {
            e: [h["command"] for g in gs for h in g["hooks"]]
            for e, gs in got["hooks"].items()
        }
        self.assertIn("mine.sh", commands["Stop"])
        for event, groups in example.items():
            for g in groups:
                for h in g["hooks"]:
                    self.assertIn(h["command"], commands[event])

        res = wire()
        self.assertIn("already wired", res.stdout)
        self.assertEqual(json.loads(settings.read_text()), got)

    def test_without_wire_hooks_settings_untouched(self):
        install(self.dest, self.cfg)
        self.assertFalse((self.dest / "settings.json").exists())

    def test_missing_config(self):
        res = install(self.dest, self.tmp / "nope.json")
        self.assertEqual(res.returncode, 2)
        self.assertIn("no config", res.stderr)


if __name__ == "__main__":
    unittest.main()
