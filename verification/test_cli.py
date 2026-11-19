"""Exercise actual module entry points and inspect their files/exit codes."""

import csv
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def cli(module, *args):
    return subprocess.run([sys.executable, "-m", module, *map(str, args)],
                          cwd=ROOT, capture_output=True, text=True)


class CommandLineTests(unittest.TestCase):
    def test_assemble_then_execute_csv_and_vcd(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            image, trace, waveform = base / "pulse.hex", base / "pulse.csv", base / "pulse.vcd"
            result = cli("tools.assembler", "programs/pulse.asm", "-o", image)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(image.read_text().splitlines(),
                             ["100100", "200101", "100101", "300013", "100100", "300004", "000000"])
            result = cli("model.engine", image, "--trace", trace, "--vcd", waveform)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("HALTED after 28 cycles", result.stdout)
            with trace.open(newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 28)
            high = [r for r in rows if int(r["uio_out"]) & int(r["uio_oe"]) & 1]
            self.assertEqual([int(r["cycle"]) for r in high], list(range(3, 23)))
            self.assertEqual(float(rows[22]["time_ns"]) - float(rows[2]["time_ns"]), 1000)
            self.assertEqual(rows[-1]["uio_oe"], "0")
            vcd = waveform.read_text()
            self.assertIn("$timescale 1ns $end", vcd)
            self.assertIn('#150\nb00000001 !\nb00000001 "', vcd)
            self.assertIn('#1150\nb00000000 !\nb00000001 "', vcd)
            self.assertIn('#1400\nb00000000 !\nb00000000 "', vcd)

    def test_binary_format_is_three_bytes_per_word_big_endian(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pulse.bin"
            result = cli("tools.assembler", "programs/pulse.asm", "-o", path, "--format", "bin")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(path.read_bytes(), bytes.fromhex(
                "10 01 00 20 01 01 10 01 01 30 00 13 10 01 00 30 00 04 00 00 00"))

    def test_assembler_failure_is_nonzero_and_does_not_emit_image(self):
        with tempfile.TemporaryDirectory() as directory:
            source, image = Path(directory) / "bad.asm", Path(directory) / "bad.hex"
            source.write_text("DELAY 0\n")
            result = cli("tools.assembler", source, "-o", image)
            self.assertEqual(result.returncode, 2)
            self.assertIn("line 1", result.stderr)
            self.assertFalse(image.exists())

    def test_runtime_fault_and_cycle_limit_are_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "program.hex"
            image.write_text("F000A5\n")
            result = cli("model.engine", image)
            self.assertEqual(result.returncode, 1)
            self.assertIn("PROGRAM_TRAP", result.stdout)
            image.write_text("500000\n")
            result = cli("model.engine", image, "--max-cycles", 5)
            self.assertEqual(result.returncode, 2)
            self.assertIn("CYCLE LIMIT after 5 cycles", result.stdout)

    def test_bad_image_and_parameters_are_reported_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "program.hex"
            image.write_text("not hex\n")
            result = cli("model.engine", image)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)
            image.write_text("000000\n")
            for args in (("--max-cycles", 0), ("--clock-hz", 0), ("--pins", 256),
                         ("--od-mask", -1), ("--clock-hz", 3, "--vcd", Path(directory) / "bad.vcd")):
                with self.subTest(args=args):
                    result = cli("model.engine", image, *args)
                    self.assertEqual(result.returncode, 2)
                    self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
