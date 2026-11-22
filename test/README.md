# Protocol engine simulation

The RTL and gate-level jobs use cocotb to assemble the pulse program, start the
pin driver in `engine_checks.vh` and compare its CSV trace with the Python model.
The driver accesses the DUT through its Tiny Tapeout pins. It also exercises
incomplete loads, unsupported commands, bad instructions, open drain, stopping,
deselection and full-memory fall-through. It then loads the UART image over the
same SPI pins. The independent UART check reads every output sample from
`sim_build/uart-rtl.csv` and checks P1, output enable, RUNNING and FAULT through
the 8N1 frame and HALT.

The FIFO test fills all four TX slots, checks overflow rejection, refills
while running, waits with the line idle, then supplies another byte and stops.
The checker validates the six 8N1 frames cycle by cycle. The RTL CI job also
runs `fifo_edges.v` to check writes on the final GET_TX timeout edge and
simultaneous push/pop ordering with empty, occupied and full queues.

The RX test drives P2 with an independent serial clock, loads the receiver
through SPI and checks READ_RX responses. It covers consecutive frames,
a false start, framing and overrun faults, FIFO order and restart after CLEAR.
The core bench also reads on the exact edge that PUT_RX writes to an empty
or full queue.

The same pin driver loads each SPI mode over the host port. Its peripheral
checker decodes six MOSI bytes per mode, drives a different MISO sequence
and checks every reply through READ_RX. It also checks SCK polarity, which
edge samples data, 500 ns clock halves, CS setup and hold, FIFO stalls and
STOP release. It delays each MISO launch and expires the bit after sampling
so that a receiver sampling on the opposite edge sees incorrect data.

The I2C test uses an independent target at address 0x53 on the resolved bus.
It decodes START, repeated START, STOP, address, data and ninth-clock ownership.
It checks the Standard- and Fast-mode clock, SDA setup and framing minima
from [NXP UM10204, Table 11](https://www.nxp.com/docs/en/user-guide/UM10204.pdf).
The digital bus model sinks immediately and delays a rising level for two
clock samples. Board capacitance, analog edges and pad thresholds require
measurement. The cases include address, data and repeated-address NACKs,
stretching during data and after ACK, a stretch timeout, restart after CLEAR,
and a six-byte read with a full RX FIFO. Results are read over the host SPI
port. A two-stage chip input synchronizer follows the modeled P7 pad readback.

## Setting up

The Linux workflow uses Icarus, make and `test/requirements.txt`.
For standalone Questa, run `python scripts/questa_engine.py --bin <Questa-bin-directory>`
from the repository root. It saves the pin checks and cycle comparison in a new
run directory and exits nonzero if compilation, simulation or comparison fails.

## How to run

To run the RTL simulation:

```sh
make -B
```

To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
```

If you wish to save the waveform in VCD format instead of FST format, edit tb.v to use `$dumpfile("tb.vcd");` and then run:

```sh
make -B FST=
```

This will generate `tb.vcd` instead of `tb.fst`.

## How to view the waveform file

Using GTKWave

```sh
gtkwave tb.fst tb.gtkw
```

Using Surfer

```sh
surfer tb.fst
```
