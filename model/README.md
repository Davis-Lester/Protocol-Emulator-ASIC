# Reference model

`engine.py` executes all 16 instructions in `docs/ARCHITECTURE.md`, one system
clock edge at a time, with staged program loading, four-byte TX/RX FIFOs,
two-stage protocol input synchronization, open-drain pin adaptation and sticky
faults. Its decoder is separate from the assembler's encoder tables.

Run from the repo root with Python 3.10+ (no third-party packages):

```text
python scripts/workflow.py demo
python scripts/workflow.py test-model
```

Or run an existing hex image:

```text
python -m model.engine runs/pulse.hex --trace runs/pulse.csv --vcd runs/pulse.vcd
```

CSV records post-edge state and time at an assumed 20 MHz by default. VCD uses
1 ns units, timestamps state changes at rising edges, and assumes a fresh START
with released outputs at time zero. No clock waveform is included. Use
`--clock-hz` to change time scaling; VCD needs an integer nanosecond period.
An integer PC sentinel can reach 64 to expose an illegal fall-through without
wrapping; this is diagnostic model state, not a proposed 7-bit hardware PC.

CLI exit codes: 0 = halted without fault, 1 = engine fault, 2 = invalid arguments,
bad image/I/O, or cycle budget exhausted while still running. `--max-cycles`
defaults to 10000; a budget limit does not stop or fault the simulated engine.

## API and scope

Create `Engine()`, call `load_program(words)` or the staged
`begin_load`/`write_word`/`commit_load` methods, then `start()` and `tick()`.
`tick(pins=...)` accepts external input values; the execution logic reads the
pre-edge second synchronizer stage. A level first sampled on edge 1 can affect
execution on edge 3. The input argument is not a resolved electrical bus: tests
or an eventual co-simulation harness must model external pull-ups/loopback.

Host calls are atomic engine-boundary operations, not wire-level SPI transactions.
For same-edge FIFO traffic, `tick(tx_write=byte, rx_read=True)` services the host
before the engine. Rejected host requests appear in `Trace.host_error`; the
engine still executes that edge. Direct rejected host methods raise `HostError`
without faulting the engine.

`reset()` and `tick(reset=True)` invalidate the program and clear control state
without clearing memory storage or the simulation cycle counter. Reset is already
conditioned at this boundary: reset-release synchronization, host SCK/MOSI/CS
sampling, physical metastability, board timing, and wire-level host parsing are
not implemented. Deselecting via `tick(ena=False)` invalidates state and blocks
further work until reset and program reload. Use a future RTL harness to verify
the actual wrapper reset/CDC behavior.

Fault diagnostics are `Fault.NONE=0`, `ILLEGAL_INSTRUCTION=1`, `PC_RANGE=2`,
`WAIT_TIMEOUT=3`, `TX_TIMEOUT=4`, `RX_TIMEOUT=5`, `LOOP_UNDERFLOW=6`, and
`PROGRAM_TRAP=7`, with a separate `trap_code` byte. These model diagnostics do
not assign the SPI host response byte layout or error codes.

This is an executable software specification. Passing these tests does not prove
an RTL implementation, supported protocol rates, area, timing, DRC or LVS.
