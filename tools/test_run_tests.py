"""Runner regressions using real subprocesses, including inherited Windows pipes."""
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

import run_tests as runner


def running(pid: int) -> bool:
    if os.name == "nt":
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.OpenProcess(0x100000, False, pid)
        if not handle:
            return False
        try:
            return kernel.WaitForSingleObject(handle, 0) == 0x102
        finally:
            kernel.CloseHandle(handle)
    try:
        state = Path(f"/proc/{pid}/stat")
        if state.exists() and state.read_text().split()[2] == "Z":
            return False
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


class RunnerTests(unittest.TestCase):
    def test_regular_checks_failure_keeps_running_and_counts_totals(self):
        code = "print('ERROR: failed assertion'); print('[test] CHECKS=8 FAIL=2')"
        result = runner.capture_process([sys.executable, "-u", "-c", code], Path.cwd(), 3)
        self.assertEqual(result[2], "")
        passed, failed, status = runner.summarize_output(*result)
        self.assertEqual((passed, failed), (6, 2))
        self.assertTrue(status.startswith("FAIL"))

    def test_zero_exit_without_result_is_not_a_pass(self):
        self.assertTrue(runner.summarize_output(0, "engine started\n", "")[2].startswith("ERROR"))

    def test_late_script_error_overrides_pass_summary(self):
        out = "[test] PASS=3 FAIL=0\nSCRIPT ERROR: invalid property\n"
        self.assertTrue(runner.summarize_output(0, out, "")[2].startswith("ERROR"))

    def test_truncated_script_error_is_still_reported(self):
        self.assertEqual(runner.summarize_output(0, "SCRIPT ERROR:", "SCRIPT_ERROR")[2], "ERROR SCRIPT ERROR:")

    def test_lowercase_scene_summary(self):
        self.assertEqual(runner.summarize_output(0, "[RoomEventUI] checks=19 failures=[]", ""), (19, 0, "PASS"))

    def test_cleanup_warning_does_not_hide_valid_result(self):
        out = "[test] PASS=4 FAIL=0\nERROR: 1 resources still in use at exit\n"
        self.assertEqual(runner.summarize_output(0, out, ""), (4, 0, "PASS"))

    def test_fatal_script_error_returns_before_suite_timeout(self):
        code = "import time; print('SCRIPT ERROR: Parse Error: example',flush=True); time.sleep(30)"
        started = time.monotonic()
        result = runner.capture_process([sys.executable, "-u", "-c", code], Path.cwd(), 10)
        self.assertEqual(result[2], "SCRIPT_ERROR")
        self.assertLess(time.monotonic() - started, 5)
        self.assertIn("Parse Error: example", result[1])

    def check_child_cleanup(self, fatal: bool):
        with tempfile.TemporaryDirectory() as folder:
            pid_path = Path(folder) / "child.pid"
            code = (
                "import pathlib,subprocess,sys,time; "
                "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                f"pathlib.Path({str(pid_path)!r}).write_text(str(child.pid)); "
                + ("print('SCRIPT ERROR: example',flush=True); " if fatal else "")
                + "time.sleep(30)"
            )
            pid = None
            try:
                result = runner.capture_process([sys.executable, "-u", "-c", code], Path(folder), 3 if not fatal else 10)
                self.assertEqual(result[2], "SCRIPT_ERROR" if fatal else "TIMEOUT")
                pid = int(pid_path.read_text())
                self.assertFalse(running(pid), "child retained the output pipe after the invocation was stopped")
            finally:
                if pid is None and pid_path.exists():
                    pid = int(pid_path.read_text())
                if pid is not None and running(pid):
                    if os.name == "nt":
                        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
                    else:
                        os.kill(pid, signal.SIGKILL)

    def test_fatal_error_stops_child_that_inherits_output_pipe(self):
        self.check_child_cleanup(True)

    def test_timeout_stops_child_that_inherits_output_pipe(self):
        self.check_child_cleanup(False)


if __name__ == "__main__":
    unittest.main()
