"""Cycle-level execution model, with atomic host operations (not a wire-level SPI target)."""

import argparse
from collections import deque
import csv
from dataclasses import asdict, dataclass
from enum import IntEnum
from pathlib import Path
import sys


class Fault(IntEnum):
    NONE = 0
    ILLEGAL_INSTRUCTION = 1
    PC_RANGE = 2
    WAIT_TIMEOUT = 3
    TX_TIMEOUT = 4
    RX_TIMEOUT = 5
    LOOP_UNDERFLOW = 6
    PROGRAM_TRAP = 7


class HostError(ValueError):
    """Rejected host operation; does not itself fault the engine."""


@dataclass(frozen=True)
class Trace:
    cycle: int
    pc_before: int
    pc_after: int
    word: int | None
    retired: bool
    sampled_pins: int
    uio_out: int
    uio_oe: int
    running: bool
    fault: int
    trap_code: int
    tx_count: int
    rx_count: int
    tx_shift: int
    rx_shift: int
    loop_count: int
    host_error: str
    host_rx: int | None


def _unsigned(value, bits, name):
    if type(value) is not int or not 0 <= value < (1 << bits):
        raise HostError(f"{name} must be an unsigned {bits}-bit integer")
    return value


class Engine:
    """One tick is one rising system-clock edge; state snapshots are post-edge.

    Host methods are atomic engine-boundary operations, with no SPI wire timing.
    For same-edge FIFO traffic use tick(tx_write=..., rx_read=True): host first.
    tick(reset=True) models an asserted, already-conditioned core reset. The RTL
    wrapper's reset-release synchronizer and analog metastability are out of scope.
    """

    def __init__(self):
        self.memory = [0] * 64
        self.cycle = 0
        self.reset()

    def reset(self):
        """Invalidate program/control state without clearing memory storage or time."""
        self.program_valid = False
        self.word_count = 0
        self.load_count = None
        self.load_index = 0
        self.od_mask = 0
        self.running = False
        self.fault = Fault.NONE
        self.trap_code = 0
        self.pc = 0
        self.out = self.oe = 0
        self.tx_shift = self.rx_shift = self.loop_count = 0
        self.tx_fifo = deque()
        self.rx_fifo = deque()
        self._remaining = None
        self._sync1 = self._sync2 = 0
        self.needs_reset = False

    @property
    def uio_out(self):
        return self.out & (~self.od_mask & 0xFF)

    @property
    def uio_oe(self):
        if self.needs_reset:
            return 0
        return self.oe & ~(self.od_mask & self.out) & 0xFF

    def _stopped(self):
        if self.running:
            raise HostError("operation requires a stopped engine")
        if self.needs_reset:
            raise HostError("reset required after deselection")

    def begin_load(self, count):
        self._stopped()
        if type(count) is not int or not 1 <= count <= 64:
            raise HostError("program size must be 1-64 words")
        self.program_valid = False
        self.word_count = 0
        self.load_count = count
        self.load_index = 0

    def write_word(self, word):
        self._stopped()
        _unsigned(word, 24, "instruction")
        if self.load_count is None or self.load_index >= self.load_count:
            raise HostError("no active load or declared word count exceeded")
        self.memory[self.load_index] = word
        self.load_index += 1

    def commit_load(self):
        self._stopped()
        if self.load_count is None or self.load_index != self.load_count:
            raise HostError("program load is incomplete")
        self.word_count = self.load_count
        self.load_count = None
        self.program_valid = True

    def load_program(self, words):
        """Convenience helper using the same BEGIN/WRITE/COMMIT rules."""
        words = list(words)
        if not 1 <= len(words) <= 64:
            raise HostError("program size must be 1-64 words")
        for word in words:
            _unsigned(word, 24, "instruction")
        self.begin_load(len(words))
        for word in words:
            self.write_word(word)
        self.commit_load()

    def configure_od(self, mask):
        self._stopped()
        self.od_mask = _unsigned(mask, 8, "open-drain mask")

    def start(self):
        self._stopped()
        if not self.program_valid or self.fault:
            raise HostError("START requires a committed program and no fault")
        self.pc = 0
        self.out = self.oe = 0
        self.tx_shift = self.rx_shift = self.loop_count = 0
        self._remaining = None
        self.running = True

    def stop(self):
        self.running = False
        self.out = self.oe = 0
        self._remaining = None

    def clear(self):
        self._stopped()
        self.stop()
        self.pc = 0
        self.fault = Fault.NONE
        self.trap_code = 0
        self.tx_shift = self.rx_shift = self.loop_count = 0
        self.tx_fifo.clear()
        self.rx_fifo.clear()
        self.load_count = None
        self.load_index = 0

    def write_tx(self, value):
        if self.needs_reset:
            raise HostError("reset required after deselection")
        _unsigned(value, 8, "TX byte")
        if len(self.tx_fifo) == 4:
            raise HostError("TX FIFO full")
        self.tx_fifo.append(value)

    def read_rx(self):
        if self.needs_reset:
            raise HostError("reset required after deselection")
        if not self.rx_fifo:
            raise HostError("RX FIFO empty")
        return self.rx_fifo.popleft()

    def _fail(self, fault, trap_code=0):
        self.fault = fault
        self.trap_code = trap_code
        self.stop()

    def _branch(self, address):
        if address >= self.word_count:
            self._fail(Fault.PC_RANGE)
            return False
        self.pc = address
        return True

    def _wait(self, success, count, fault):
        if success:
            self._remaining = None
            return True
        if count:
            if self._remaining is None:
                self._remaining = count
            self._remaining -= 1
            if self._remaining == 0:
                self._fail(fault)
        return False

    def _execute(self, word, pins):
        """Decode separately from assembler field tables; return retirement flag."""
        opcode = word >> 20
        operand = word & 0xFFFFF
        # Legal operand masks, checked even for an untaken branch.
        masks = (0, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFFF, 0x3F, 0xFF, 0x3F,
                 0xFFFF, 0xF, 0xF, 0xFFFF, 0xFF, 0x3FF, 0, 0xFF)
        if operand & ~masks[opcode] or (opcode in (3, 6, 15) and operand == 0):
            self._fail(Fault.ILLEGAL_INSTRUCTION)
            return False
        pin = operand & 7
        if opcode == 0:
            self.stop()
            return True
        if opcode in (1, 2):
            mask, value = (operand >> 8) & 0xFF, operand & 0xFF
            if opcode == 1:
                self.out = (self.out & ~mask) | (value & mask)
            else:
                self.oe = (self.oe & ~mask) | (value & mask)
        elif opcode == 3:
            if self._remaining is None:
                self._remaining = operand
            self._remaining -= 1
            if self._remaining:
                return False
            self._remaining = None
        elif opcode == 4:
            pin, level = (operand >> 17) & 7, (operand >> 16) & 1
            if not self._wait(((pins >> pin) & 1) == level, operand & 0xFFFF, Fault.WAIT_TIMEOUT):
                return False
        elif opcode == 5:
            return self._branch(operand)
        elif opcode == 6:
            self.loop_count = operand
        elif opcode == 7:
            if self.loop_count == 0:
                self._fail(Fault.LOOP_UNDERFLOW)
                return False
            self.loop_count -= 1
            if self.loop_count:
                return self._branch(operand)
        elif opcode == 8:
            if not self._wait(bool(self.tx_fifo), operand, Fault.TX_TIMEOUT):
                return False
            self.tx_shift = self.tx_fifo.popleft()
        elif opcode == 9:
            msb = bool(operand & 8)
            bit = (self.tx_shift >> (7 if msb else 0)) & 1
            self.out = (self.out & ~(1 << pin)) | (bit << pin)
            self.tx_shift = ((self.tx_shift << 1) & 0xFF) if msb else (self.tx_shift >> 1)
        elif opcode == 10:
            bit = (pins >> pin) & 1
            self.rx_shift = (((self.rx_shift << 1) | bit) & 0xFF) if operand & 8 else ((self.rx_shift >> 1) | (bit << 7))
        elif opcode == 11:
            if not self._wait(len(self.rx_fifo) < 4, operand, Fault.RX_TIMEOUT):
                return False
            self.rx_fifo.append(self.rx_shift)
        elif opcode == 12:
            self.tx_shift = operand
        elif opcode == 13:
            pin, level, address = (operand >> 7) & 7, (operand >> 6) & 1, operand & 0x3F
            if ((pins >> pin) & 1) == level:
                return self._branch(address)
        elif opcode == 14:
            self.rx_shift = 0
        elif opcode == 15:
            self._fail(Fault.PROGRAM_TRAP, operand)
            return True
        # Keep a sentinel PC=word_count after the final word; never wrap at 64.
        # If still running, the next fetch faults instead of executing stale data.
        self.pc += 1
        return True

    def tick(self, pins=0, *, reset=False, ena=True, stop=False, tx_write=None, rx_read=False):
        """Run one edge, applying optional host FIFO/control events first.

        pins is the external eight-bit input bus, not a resolved model of wires.
        Engine reads the old second synchronizer stage on this edge; a newly
        applied pin level can first affect execution on the third sampling edge.
        Reset/deselection suppress host events and execution; STOP suppresses
        execution but may be combined with FIFO traffic for this atomic API.
        """
        _unsigned(pins, 8, "pin inputs")
        self.cycle += 1
        pc_before = self.pc
        sampled = self._sync2
        word = None
        retired = False
        host_error = ""
        host_rx = None
        if reset:
            self.reset()
        elif not ena:
            self.reset()
            self.needs_reset = True
        elif not self.needs_reset:
            self._sync2, self._sync1 = self._sync1, pins
            if stop:
                self.stop()
            if tx_write is not None:
                try:
                    self.write_tx(tx_write)
                except HostError as exc:
                    host_error = str(exc)
            if rx_read:
                try:
                    host_rx = self.read_rx()
                except HostError as exc:
                    host_error = "; ".join(filter(None, (host_error, str(exc))))
            if self.running:
                if not self.program_valid or not 0 <= self.pc < self.word_count:
                    self._fail(Fault.PC_RANGE)
                else:
                    word = self.memory[self.pc]
                    retired = self._execute(word, sampled)
        return Trace(self.cycle, pc_before, self.pc, word, retired, sampled,
                     self.uio_out, self.uio_oe, self.running, int(self.fault),
                     self.trap_code, len(self.tx_fifo), len(self.rx_fifo),
                     self.tx_shift, self.rx_shift, self.loop_count, host_error, host_rx)

    def run(self, max_cycles=10000, pins=0):
        if type(max_cycles) is not int or max_cycles < 1:
            raise ValueError("max_cycles must be positive")
        trace = []
        for _ in range(max_cycles):
            if not self.running:
                break
            trace.append(self.tick(pins))
        return trace


def write_csv(path, trace, clock_hz):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["time_ns", *Trace.__dataclass_fields__])
        writer.writeheader()
        for row in trace:
            writer.writerow({"time_ns": row.cycle * 1_000_000_000 / clock_hz, **asdict(row)})


def write_vcd(path, trace, clock_hz):
    if clock_hz <= 0 or 1_000_000_000 % clock_hz:
        raise ValueError("VCD requires a positive clock rate with an integer nanosecond period")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # No clk signal: changes are timestamped at rising-edge times, with a t=0
    # released-pin initial state. This export is intended for a freshly started run.
    signals = (("uio_out", 8, "!"), ("uio_oe", 8, '"'), ("running", 1, "#"),
               ("fault", 8, "$"), ("pc_after", 7, "%"))
    with path.open("w", encoding="ascii", newline="\n") as stream:
        stream.write("$timescale 1ns $end\n$scope module engine $end\n")
        for name, width, symbol in signals:
            stream.write(f"$var wire {width} {symbol} {name} $end\n")
        stream.write("$upscope $end\n$enddefinitions $end\n#0\n$dumpvars\n")
        for name, width, symbol in signals:
            value = int(name == "running")
            stream.write(f"b{value:0{width}b} {symbol}\n")
        stream.write("$end\n")
        for row in trace:
            stream.write(f"#{row.cycle * (1_000_000_000 // clock_hz)}\n")
            for name, width, symbol in signals:
                stream.write(f"b{int(getattr(row, name)):0{width}b} {symbol}\n")


def main(argv=None):
    from tools.assembler import read_hex

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--trace", type=Path, help="CSV trace output")
    parser.add_argument("--vcd", type=Path, help="VCD waveform output")
    parser.add_argument("--clock-hz", type=int, default=20_000_000)
    parser.add_argument("--max-cycles", type=int, default=10000)
    parser.add_argument("--pins", type=lambda s: int(s, 0), default=0)
    parser.add_argument("--od-mask", type=lambda s: int(s, 0), default=0)
    args = parser.parse_args(argv)
    try:
        if args.clock_hz <= 0:
            raise ValueError("clock rate must be positive")
        if args.vcd and 1_000_000_000 % args.clock_hz:
            raise ValueError("VCD requires an integer nanosecond clock period")
        engine = Engine()
        engine.load_program(read_hex(args.image))
        engine.configure_od(args.od_mask)
        engine.start()
        trace = engine.run(args.max_cycles, args.pins)
        if args.trace:
            write_csv(args.trace, trace, args.clock_hz)
        if args.vcd:
            write_vcd(args.vcd, trace, args.clock_hz)
        if engine.fault:
            print(f"FAULT {engine.fault.name} at cycle {engine.cycle}, PC={engine.pc}, trap={engine.trap_code}")
            return 1
        if engine.running:
            print(f"CYCLE LIMIT after {engine.cycle} cycles, PC={engine.pc}; engine still running")
            return 2
        print(f"HALTED after {engine.cycle} cycles ({engine.cycle / args.clock_hz * 1e6:g} us at {args.clock_hz} Hz); pins released")
        return 0
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
