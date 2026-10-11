"""Standard-library tests for the runner's false-success and timeout protection."""
from pathlib import Path
import sys
import tempfile
import unittest

import run_tests


class RunnerTests(unittest.TestCase):
    def test_zero_exit_script_error_is_failure(self):
        errors = run_tests.inspect_output(0, "SCRIPT ERROR: Assertion failed.\nCORE_TEST PASS\n", r"CORE_TEST PASS")
        self.assertTrue(errors)

    def test_zero_exit_without_pass_marker_is_failure(self):
        self.assertTrue(run_tests.inspect_output(0, "Godot Engine\n", r"CORE_TEST PASS"))

    def test_assertion_failure_cannot_hide_after_pass(self):
        self.assertTrue(run_tests.inspect_output(0, "CORE_TEST PASS\nERROR: Assertion failed\n", r"CORE_TEST PASS"))

    def test_test_fail_cannot_hide_after_pass(self):
        self.assertTrue(run_tests.inspect_output(0, "CORE_TEST PASS\nANOTHER_TEST FAIL\n", r"CORE_TEST PASS"))

    def test_nonzero_exit_is_failure_even_with_pass(self):
        self.assertTrue(run_tests.inspect_output(1, "CORE_TEST PASS\n", r"CORE_TEST PASS"))

    def test_zero_failure_summary_is_not_a_false_alarm(self):
        self.assertEqual(run_tests.inspect_output(0, "CORE_TEST PASS (576 checks, 0 failures)\n", r"CORE_TEST PASS"), [])

    def test_import_does_not_need_test_pass_marker(self):
        self.assertEqual(run_tests.inspect_output(0, "Import finished\n", None), [])

    def test_timeout_does_not_pass_even_after_success_text(self):
        self.assertTrue(run_tests.inspect_output(0, "CORE_TEST PASS", r"CORE_TEST PASS", timed_out=True))

    def test_foundations_flag_only_on_integrations(self):
        opted_in = {test.name for test in run_tests.TESTS if "--foundations" in test.arguments}
        self.assertEqual(opted_in, {"runtime_foundations", "adventure_integration", "encounters_integration"})

    def test_child_with_script_error_and_exit_zero_is_caught(self):
        with tempfile.TemporaryDirectory(prefix="godot-runner-test-") as folder:
            self.assertTrue(Path(folder).resolve().is_relative_to(Path(tempfile.gettempdir()).resolve()))
            log = Path(folder) / "fixture.log"
            result = run_tests.run_process(
                "fixture", [sys.executable, "-c", "print('SCRIPT ERROR: failed assertion'); print('CORE_TEST PASS')"],
                Path(folder), log, 5, r"CORE_TEST PASS",
            )
            self.assertEqual(result["status"], "fail")
            self.assertEqual(result["returncode"], 0)
            self.assertIn("SCRIPT ERROR", log.read_text(encoding="utf-8"))

    def test_hung_child_is_killed_and_logged(self):
        with tempfile.TemporaryDirectory(prefix="godot-runner-test-") as folder:
            self.assertTrue(Path(folder).resolve().is_relative_to(Path(tempfile.gettempdir()).resolve()))
            result = run_tests.run_process(
                "fixture", [sys.executable, "-c", "import time; print('begin', flush=True); time.sleep(30)"],
                Path(folder), Path(folder) / "timeout.log", 1, r"CORE_TEST PASS",
            )
            self.assertEqual(result["status"], "fail")
            self.assertTrue(result["timed_out"])
            self.assertLess(result["seconds"], 10)


if __name__ == "__main__":
    unittest.main()
