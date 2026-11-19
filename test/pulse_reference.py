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
    uart = assemble((ROOT / "programs/uart_tx.asm").read_text())
    if len(uart) != 13:
        raise ValueError("Update the UART loader for the new program length")
    (directory / "uart_tx.hex").write_text(hex_text(uart))
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


def read_samples(path):
    with path.open(newline="") as stream:
        return [(int(r["cycle"]), int(r["out"], 16), int(r["oe"], 16),
                   int(r["running"]), int(r["fault"])) for r in csv.DictReader(stream)]


def compare(directory, expected):
    check_uart(read_samples(directory / "uart-rtl.csv"))
    actual = read_samples(directory / "pulse-rtl.csv")
    if len(actual) != len(expected):
        raise AssertionError(f"Expected {len(expected)} samples, got {len(actual)}")
    for observed, wanted in zip(actual, expected):
        if observed != wanted:
            raise AssertionError(f"(edge, OUT, OE, RUNNING, FAULT): expected {wanted}, got {observed}")


def check_uart(samples):
    # Independent receiver. Find the first driven idle bit, then check every
    # clock of the start, eight LSB-first data bits and stop against 8N1.
    bit_clocks = round(20_000_000 / 115_200)
    levels = [1, 0, *((0x96 >> i) & 1 for i in range(8)), 1]
    enabled = next((i for i, row in enumerate(samples) if row[2]), None)
    if enabled is None:
        raise AssertionError("UART TX never enabled")
    release = enabled + len(levels) * bit_clocks
    if len(samples) != release + 1:
        raise AssertionError(f"Expected UART release on edge {release}, got {len(samples)-1}")
    for i, (cycle, out, oe, running, fault) in enumerate(samples):
        driving = enabled <= i < release
        if (cycle, oe, running, fault) != (i, 2 if driving else 0, int(i < release), 0):
            raise AssertionError(f"UART pin enable, status or cycle mismatch on edge {i}")
        if driving:
            slot = (i - enabled) // bit_clocks
            if out != levels[slot] << 1:
                raise AssertionError(f"UART level mismatch in slot {slot} on edge {i}")
