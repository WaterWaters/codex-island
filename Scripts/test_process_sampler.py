#!/usr/bin/env python3
"""Calibrate macOS sampler CPU units against the child's independent POSIX clock."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
BUSY_CHILD = """
import json, sys, time
print("ready", flush=True)
assert sys.stdin.readline().strip() == "go"
start = time.process_time_ns()
end = time.monotonic() + 1.2
while time.monotonic() < end:
    pass
print(json.dumps({"cpuNanoseconds": time.process_time_ns() - start,
                  "completedMonotonicSeconds": time.clock_gettime(time.CLOCK_MONOTONIC)}), flush=True)
sys.stdin.readline()
"""

class ProcessSamplerTests(unittest.TestCase):
    binary: Path

    def test_invalid_arguments_are_rejected(self):
        for arguments in ([], ["0", "1", "1"], ["1", "-1", "1"], ["1", "1", "0"],
                          ["1", "1", "61"], ["1", "86401", "1"], ["not-a-pid", "1", "1"]):
            with self.subTest(arguments=arguments):
                result = subprocess.run([str(self.binary), *arguments], capture_output=True)
                self.assertEqual(result.returncode, 2)

    def test_cpu_nanoseconds_agree_with_child_process_clock(self):
        child = subprocess.Popen([sys.executable, "-u", "-c", BUSY_CHILD], text=True,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        sampler = None
        try:
            self.assertEqual(child.stdout.readline().strip(), "ready")
            launch_clock = time.clock_gettime(time.CLOCK_MONOTONIC)
            sampler = subprocess.Popen([str(self.binary), str(child.pid), "4", "1"],
                                       bufsize=0, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            first = json.loads(sampler.stdout.readline())
            child.stdin.write("go\n")
            child.stdin.flush()
            workload = json.loads(child.stdout.readline())
            expected = workload["cpuNanoseconds"]
            output, errors = sampler.communicate(timeout=15)
            self.assertEqual(sampler.returncode, 0, errors)
            rows = [first, *[json.loads(line) for line in output.splitlines()]]
            # Descheduling can coalesce intervals; the final duration and CPU
            # coverage matter, not an exact number of timer firings.
            self.assertGreaterEqual(len(rows), 2)
            self.assertLessEqual(len(rows), 5)
            self.assertTrue(all(a["elapsedSeconds"] < b["elapsedSeconds"]
                                for a, b in zip(rows, rows[1:])))
            self.assertGreaterEqual(rows[-1]["elapsedSeconds"], 4)
            # CLOCK_MONOTONIC is shared with the C sampler. Its start is no
            # earlier than launch_clock, so this proves the last sample covers
            # all work even if the parent was briefly descheduled after launch.
            self.assertLessEqual(workload["completedMonotonicSeconds"],
                                 launch_clock + rows[-1]["elapsedSeconds"],
                                 "Calibration window missed the workload; scheduling is inconclusive")
            actual = (rows[-1]["userNanoseconds"] + rows[-1]["systemNanoseconds"]
                      - first["userNanoseconds"] - first["systemNanoseconds"])
            self.assertGreater(expected, 100_000_000, "CPU-starved calibration is inconclusive")
            self.assertTrue(math.isclose(actual, expected, rel_tol=0.1, abs_tol=30_000_000),
                            f"sampler {actual} ns does not agree with POSIX process clock {expected} ns")
            self.assertEqual(first["cpuTimeUnits"], "nanoseconds")
            self.assertGreater(first["machTimebaseNumer"], 0)
            self.assertGreater(first["machTimebaseDenom"], 0)
        finally:
            for process in (sampler, child):
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                if process is not None:
                    for stream in (process.stdin, process.stdout, process.stderr):
                        if stream is not None:
                            stream.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, help="Use an existing sampler instead of compiling it")
    arguments = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This sampler and calibration require macOS")
    with tempfile.TemporaryDirectory(prefix="island-sampler-calibration-") as folder:
        binary = arguments.binary.resolve() if arguments.binary else Path(folder) / "island-sample"
        if arguments.binary is None:
            subprocess.run(["xcrun", "clang", "-O2", "-Wall", "-Wextra", "-Werror",
                            str(ROOT / "Scripts/sample_process.c"), "-o", str(binary)], check=True)
        ProcessSamplerTests.binary = binary
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProcessSamplerTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        return 0 if result.wasSuccessful() else 1

if __name__ == "__main__":
    raise SystemExit(main())
