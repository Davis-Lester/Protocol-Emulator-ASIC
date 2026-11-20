"""Run the Tiny Tapeout pin tests and pulse scoreboard using Questa in batch mode."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "test"))
from pulse_reference import compare, prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", type=Path, help="Questa executable directory (otherwise use PATH)")
    args = parser.parse_args()
    runs = ROOT / "runs"
    runs.mkdir(exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="questa-engine-", dir=runs))
    print(f"Run directory: {directory}", flush=True)
    rtl = [ROOT / "src" / name for name in ("protocol_emulator.v", "protocol_spi.v", "protocol_core.v")]
    inputs = rtl + [ROOT / name for name in ("test/tb.v", "test/engine_checks.vh",
                    "test/pulse_reference.py", "programs/pulse.asm", "programs/uart_tx.asm",
                    "programs/uart_fifo_tx.asm", "model/engine.py",
                    "tools/assembler.py", "scripts/questa_engine.py")]
    record = {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "git_status": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
              "input_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in inputs},
              "pdk": "RTL behavioral simulation", "commands": [], "result": "FAIL"}

    def run(tool, arguments, log_name):
        binary = tool + (".exe" if os.name == "nt" else "")
        path = str(args.bin.resolve() / binary) if args.bin else shutil.which(binary)
        if not path:
            raise RuntimeError(f"{binary} missing from PATH; specify --bin")
        cmd = [path, *map(str, arguments)]
        entry = {"argv": cmd, "log": log_name, "exit_code": None}
        record["commands"].append(entry)
        result = subprocess.run(cmd, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors="replace")
        entry["exit_code"] = result.returncode
        (directory / log_name).write_text(result.stdout, encoding="utf-8")
        if result.returncode:
            raise RuntimeError(f"{tool} exited {result.returncode}\n{result.stdout[-2500:]}")
        return result.stdout

    try:
        build = directory / "sim_build"
        expected = prepare(build)
        for tool in ("vlog", "vsim"):
            record[tool] = run(tool, ["-version"], tool + "-version.log").strip()
        run("vlib", ["work"], "vlib.log")
        run("vlog", ["+define+QUESTA_STANDALONE", "+incdir+" + str(ROOT / "test"),
                     *rtl, ROOT / "test/tb.v"], "compile.log")
        output = run("vsim", ["-c", "-onfinish", "stop", "work.tb", "-do",
                     "onerror {quit -code 1}; run 20 ms; quit -code 0"], "simulate.log")
        if "ENGINE PIN CHECKS PASSED" not in output or "ENGINE FAIL:" in output:
            raise RuntimeError(f"Pin checks did not pass. See {directory / 'simulate.log'}")
        compare(build, expected)
        record["result"] = "PASS"
        print("PASS: SPI pin checks, 29 pulse samples, fixed-byte UART and six FIFO-fed UART frames")
    except (OSError, RuntimeError, ValueError, AssertionError) as exc:
        record["error"] = str(exc)
        print(f"FAIL: {exc}", file=sys.stderr)
    finally:
        (directory / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    return int(record["result"] != "PASS")


if __name__ == "__main__":
    sys.exit(main())
