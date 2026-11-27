"""Assembler input and post-edge scoreboard shared by the RTL and GL harnesses."""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.engine import Engine
from tools.assembler import assemble, hex_text
from tools.i2c import program as i2c_program, transaction

from tools.ps2 import echo_program
from tools.jtag import decode_scan, reset_to_idle, scan

# Independent target captures 0101 in IR, has a 13-bit data register at IR=2,
# and shifts BYPASS through one stage. Each tuple includes expected scan-out.
JTAG_SCANS = (
    ("ir", 4, 0x2, 0x5),
    ("dr", 13, 0x1791, 0x1357),
    ("dr", 13, 0x0128, 0x1791),
    ("ir", 4, 0xf, 0x5),
    ("dr", 8, 0x96, 0x2c),
    ("dr", 1, 1, 0),
)


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
    fifo_program = assemble((ROOT / "programs/uart_fifo_tx.asm").read_text())
    if len(fifo_program) != 13:
        raise ValueError("Update the FIFO UART loader for the new program length")
    (directory / "uart_fifo_tx.hex").write_text(hex_text(fifo_program))
    rx = assemble((ROOT / "programs/uart_rx.asm").read_text())
    if len(rx) != 13:
        raise ValueError("Update the RX loader for the new program length")
    (directory / "uart_rx.hex").write_text(hex_text(rx))
    with (directory / "spi_programs.hex").open("w") as stream:
        for mode in range(4):
            image = assemble((ROOT / "programs" / f"spi_mode{mode}.asm").read_text())
            stream.write(f"{len(image):x}\n")
            stream.write(hex_text(image))
    with (directory / "i2c_programs.hex").open("w") as stream:
        for rate in (100, 400):
            for reading in (False, True):
                image = i2c_program(rate, reading)
                stream.write(f"{len(image):x}\n{hex_text(image)}")
    with (directory / "i2c_transactions.hex").open("w") as stream:
        for payload, count in ((b"\x5a", 0), (b"\x5a", 2), (b"", 1), (b"", 6)):
            data = transaction(0x53, payload, count)
            stream.write(f"{len(data):x} " + data.hex(" ") + "\n")
    ps2 = assemble((ROOT / "programs/ps2_rx.asm").read_text())
    (directory / "ps2_rx.hex").write_text(f"{len(ps2):x}\n" + hex_text(ps2))
    echo = echo_program()
    (directory / "ps2_echo.hex").write_text(f"{len(echo):x}\n" + hex_text(echo))
    jtag_image = assemble((ROOT / "programs/jtag.asm").read_text())
    (directory / "jtag_program.hex").write_text(f"{len(jtag_image):x}\n" + hex_text(jtag_image))
    cycles = reset_to_idle() + b"".join(scan(r, w, v) for r, w, v, _ in JTAG_SCANS)
    (directory / "jtag_cycles.hex").write_text(f"{len(cycles):x}\n" + cycles.hex(" "))
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
    replies = bytes.fromhex((directory / "jtag_replies.hex").read_text())
    offset = 6  # Five reset clocks and one idle clock.
    for register, width, value, wanted in JTAG_SCANS:
        size = len(scan(register, width, value))
        received = decode_scan(register, width, replies[offset:offset + size])
        if received != wanted:
            raise AssertionError(f"JTAG {register} {width} bits: expected {wanted:#x}, got {received:#x}")
        offset += size
    if len(replies) != offset:
        raise AssertionError("JTAG reply count mismatch")
    check_uart(read_samples(directory / "uart-rtl.csv"))
    check_fifo_uart(read_samples(directory / "uart-fifo-rtl.csv"))
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


def check_fifo_uart(samples):
    bit_clocks = round(20_000_000 / 115_200)
    idle = 2  # P1 driven high.
    start_edges = []
    edge = 2
    expected_pin_state = [(0, 0), (idle, 0)]
    for byte in (0x96, 0x00, 0xff, 0x53, 0xa9, 0x3c):
        while edge < len(samples) and samples[edge][1] == idle:
            expected_pin_state.append((idle, idle))
            edge += 1
        start_edges.append(edge)
        for level in (0, *((byte >> i) & 1 for i in range(8)), 1):
            expected_pin_state.extend([(level << 1, idle)] * bit_clocks)
            edge += bit_clocks
    if any(b - a != 10 * bit_clocks for a, b in zip(start_edges[:4], start_edges[1:5])):
        raise AssertionError(f"Gap in queued UART burst: {start_edges}")
    if start_edges[5] - start_edges[4] <= 10 * bit_clocks:
        raise AssertionError("Missing UART idle interval during FIFO starvation")
    expected_pin_state.extend([(idle, idle)] * (len(samples) - edge - 1))
    expected_pin_state.append((0, 0))
    if len(expected_pin_state) != len(samples):
        raise AssertionError("FIFO UART stream ended before all frames completed")
    for i, ((out, oe), observed) in enumerate(zip(expected_pin_state, samples)):
        expected = (i, out, oe, int(i != len(samples) - 1), 0)
        if observed != expected:
            raise AssertionError(f"FIFO UART edge {i}: expected {expected}, got {observed}")
