"""Assembler input and post-edge scoreboard shared by the RTL and GL harnesses."""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.engine import Engine
from tools.assembler import assemble, hex_text


def prepare(directory):
    words = assemble((ROOT / "programs/pulse.asm").read_text())
    if len(words) != 7:
        raise ValueError("Update the pulse testbench for the new program length")
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "pulse.hex").write_text(hex_text(words))
    model = Engine()
    model.load_program(words)
    model.start()
    expected = [(0, 0, 0, 1, 0)]
    for _ in range(28):
        edge = model.tick()
        expected.append((edge.cycle, edge.uio_out, edge.uio_oe, int(edge.running), edge.fault))
    if model.running or model.fault:
        raise AssertionError("Pulse reference did not halt cleanly at edge 28")
    return expected


def compare(directory, expected):
    with (directory / "pulse-rtl.csv").open(newline="") as stream:
        actual = [(int(r["cycle"]), int(r["out"], 16), int(r["oe"], 16),
                   int(r["running"]), int(r["fault"])) for r in csv.DictReader(stream)]
    if len(actual) != len(expected):
        raise AssertionError(f"Expected {len(expected)} samples, got {len(actual)}")
    for observed, wanted in zip(actual, expected):
        if observed != wanted:
            raise AssertionError(f"(edge, OUT, OE, RUNNING, FAULT): expected {wanted}, got {observed}")
