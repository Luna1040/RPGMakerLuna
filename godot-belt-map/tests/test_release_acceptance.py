from pathlib import Path
import tempfile
import unittest

import release_acceptance as release


class ReleaseAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.web = self.root / "web"
        self.project.mkdir()
        self.web.mkdir()
        excludes = ",".join(release.REQUIRED_EXCLUDES)
        (self.project / "export_presets.cfg").write_text(
            'exclude_filter="' + excludes + '"\n'
            'custom_template/release="../.tools/godot/web-templates/web_nothreads_release.zip"\n',
            encoding="utf-8",
        )
        (self.web / "game.html").write_bytes(
            b'<canvas id="canvas"></canvas><script>'
            b'const GODOT_THREADS_ENABLED = false; new Engine(GODOT_CONFIG);</script>'
            + b" " * 2048
        )
        (self.web / "game.js").write_bytes(b"safe;" * 20_001)
        (self.web / "game.pck").write_bytes(b"GDPC" + b"\0" * 1_000_000)
        (self.web / "game.wasm").write_bytes(b"\x00asm" + b"\0" * 1_000_000)

    def tearDown(self):
        self.temp.cleanup()

    def test_clean_release_passes_static_gate(self):
        report = release.build_report(self.project, self.web, environment={})
        self.assertEqual("pass", report["status"])
        self.assertGreaterEqual(report["summary"]["passed"], 10)

    def test_configured_credential_is_rejected_without_disclosing_it(self):
        secret = "sk-private-unit-test-credential-123456789"
        with (self.web / "game.js").open("ab") as stream:
            stream.write(secret.encode("utf-8"))
        report = release.build_report(self.project, self.web, environment={"RPG_AGENT_API_KEY": secret})
        credential = next(row for row in report["results"] if row["name"] == "credential_isolation")
        self.assertEqual("fail", credential["status"])
        self.assertNotIn(secret, str(report))

    def test_incomplete_export_exclusions_are_rejected(self):
        (self.project / "export_presets.cfg").write_text(
            'exclude_filter="tests/*"\ncustom_template/release="web_nothreads_release.zip"\n',
            encoding="utf-8",
        )
        report = release.build_report(self.project, self.web, environment={})
        policy = next(row for row in report["results"] if row["name"] == "export_policy")
        self.assertEqual("fail", policy["status"])
        self.assertIn("captures/*", policy["missing_excludes"])


if __name__ == "__main__":
    unittest.main()
