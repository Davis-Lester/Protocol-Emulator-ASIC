# SPI and reset timing review

Reviewed the 20 MHz UART layout at commit `6c0b456` using the final netlist,
resolved SDC and three post-route timing reports from [GDS run 44681569474](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44681569474).

## SPI host interface

SCK, MOSI and CS enter as data sampled by the system clock. Each first-stage
Q feeds only its corresponding second-stage D through the routed data path.
The SPI parser detects edges and consumes data after the second stage.

| Input | First-stage instance | Second-stage instance |
| --- | --- | --- |
| SCK, `ui_in[0]` | `_12171_` | `_12174_` |
| MOSI, `ui_in[1]` | `_12172_` | `_12175_` |
| CS active low, `ui_in[2]` | `_12173_` | `_12176_` |

The sign-off SDC assigns each input a 10 ns delay relative to `clk`. An
independent SPI master can change phase across that clock. If adding timing
exceptions, limit each one to the path from its input port to the matching
first-stage D. Resolve the endpoints against each synthesized design and
verify exactly one pair per input. Preserve both setup and hold checks
from stage one to stage two. The routed SCK interstage path has the smallest
hold slack in the design, +0.106419 ns at the fast corner. These instance
names identify the reviewed layout and can change after synthesis.

The [host contract](ARCHITECTURE.md#host-loading-and-control-contract)
specifies mode 0, up to 1 MHz, and at least eight system clocks (400 ns)
per SCK level, between frames, and from CS assertion to the first rising
edge. MOSI changes on falling edges. These separations matter because
the three inputs are sampled independently. For MISO, budget from the
external falling SCK edge through synchronized edge detection and the
output path to the master's next rising edge. In ideal RTL the first
stage captures SCK, the second stage copies it one clock later, and the
reply register updates one clock after that. Depending on phase, this
uses about 100–150 ns of the 400 ns minimum low interval. A physical
budget must also cover pad and routing delays, sampling uncertainty,
board delay and the master's setup time.

## Reset, selection and pin release

With `ena` low, the arming flip-flop clears asynchronously. With `ena`
high, a rising system clock sampling `rst_n` low sets it. The qualified
request `rst_n && ena && armed` asynchronously clears both reset stages.
On release, the first stage (`_12168_`) captures a one. On the following
edge the second stage (`_12169_`) captures it. Its Q, `active`, releases
193 downstream asynchronous reset pins. The qualified request also masks
the output pins and enables so reset or deselection can disable drive
between clock edges.

The archived `55-openroad-stapostpnr/<corner>/max.rpt` and `min.rpt`
each list 193 distinct downstream reset endpoints from `_12169_`.
The smallest slack in each set is shown below.

| Corner | Recovery slack (ns) | Removal slack (ns) |
| --- | ---: | ---: |
| Fast, 1.32 V, −40 °C | +47.963478 | +0.418735 |
| Typical, 1.20 V, 25 °C | +46.990669 | +0.785230 |
| Slow, 1.08 V, 125 °C | +45.379608 | +1.428825 |

Keep downstream recovery and removal, both reset stages' interstage timing,
and the direct pin-disable paths visible. A blanket exception from `ena` or
`rst_n` would also suppress checks on the arming flip-flop or external pin
release. For example, the slow-corner `checks.rpt` explicitly times
`ena` to `uio_oe[6]` with +27.515335 ns slack under the flow's I/O model.

## Pin-level verification

The shared pin bench on `local/cdc-review` releases reset 0.5 ns before and
0.5 ns after a rising system clock in separate trials. It waits the specified
400 ns and issues STATUS and an unsupported command with changing input
bits. Each 503 ns SPI half-period shifts subsequent edges relative to
`clk`. During the active-drive test it also drops `ena` 7 ns after a falling
clock edge and checks that the outputs and enables clear before the next
rising edge. These digital checks exercise the protocol and reset sequencing.
They do not measure synchronizer metastability or establish a physical
pin-disable time.

The expanded bench passed on behavioral RTL at `6346cfc` using Verilator
5.026 and GCC 14.2.0, with no PDK. The local replay command was
`python runs/verify.py` in the review worktree. All commands returned zero,
the simulator printed `ENGINE PIN CHECKS PASSED`, all 29 pulse samples
matched the cycle model, and the independent UART checker passed for 0x96.
The command manifest, source hashes, warnings and output traces are under
`runs/verilator-engine-i4e620a9/` in that worktree. The 42 software tests
also passed. The archived gate-level result at `6c0b456` predates these
additional cases.

## Demo-board selection and reset

The competition identifies the demo board's RP2350 as a possible host and
allows other documented hosts. The repository identifies the SPI signals but
does not select a board, SPI peripheral, clock-sampling implementation or
external device that will drive the UIO lines. The following is a reference
sequence for Tiny Tapeout Commander. [Competition host and reset FAQ](https://blog.janestreet.com/protocol-emulator-asic-competition/)

1. Keep external UIO drivers high impedance, SPI SCK low and SPI CS high.
   Select the project by its mux address and configure a 20 MHz project clock.
   Mux selection enables the design. The mux-address reset selects address zero.
   The separate project reset, `rst_n`, arms this design. [Mux operation](https://github.com/TinyTapeout/tt-multiplexer/blob/main/docs/INFO.md)
2. Invoke Commander's project reset after selection. Its default reset routine
   stops automatic clocking, asserts project reset, issues ten manual clock
   cycles, releases reset with the clock stopped, and restores the previous
   automatic clock frequency if one was active. This meets the RTL requirement
   for a selected rising edge with reset low. The selection routine alone
   does not call this reset routine. [Commander implementation](https://github.com/TinyTapeout/tt-commander-app/blob/main/src/ttcontrol/ttcontrol.py)
3. Allow at least eight **running** project clocks after releasing reset
   before asserting SPI CS. At 20 MHz that is 400 ns. With automatic clocking
   off, supply eight clocks explicitly. After CS falls, allow another 400 ns
   before the first rising SCK edge. Read STATUS, verify the success byte,
   six-byte payload length and version 1, then reload the program after each
   new selection. Configure the board's input mode to match the wiring.
   Commander selection uses manual inputs, while RP-driven inputs require
   RP control. [Demo-board configuration](https://tinytapeout.com/guides/get-started-demoboard-etr/)

## Routed MISO and output-enable delays

The following are maxima over the seven tabulated macro output loads
(0.001 to 0.300 pF) in each post-route Liberty model for `6c0b456`.
For MISO, read both `cell_rise` and `cell_fall` on the `clk` rising-edge
arc of `uo_out[0]`. For deselection, read `cell_fall` on the positive-unate
combinational arc from `ena` on each of the eight `uio_oe` pins. Bit 6
has the longest disable delay at all three corners. The tables use 50%
thresholds at the **macro boundary**. The archive location is
`GDS_logs.zip → runs/wokwi/55-openroad-stapostpnr/<corner>/*.lib`.

| Corner | Clock to MISO, either transition | `ena` falling to all eight OEs low |
| --- | ---: | ---: |
| Fast, 1.32 V, −40 °C | 2.438 ns | 1.276 ns |
| Typical, 1.20 V, 25 °C | 3.721 ns | 1.919 ns |
| Slow, 1.08 V, 125 °C | 5.865 ns | 3.089 ns |

**MISO setup.** For the 400 ns minimum SCK low phase, subtract the nominal
worst-phase three project clocks (150 ns) and the slow-corner clock-to-MISO
delay (5.865 ns). The remaining **244.135 ns** must cover the host receiver's
setup requirement, the input and return routes through the board, pads and
mux, sampling uncertainty and margin. A symmetric 1 MHz clock leaves
**344.135 ns** by the same calculation. Budgeting one extra capture cycle
uses another 50 ns. The competition's estimate of about 10 ns round trip
through the pads and mux is useful for planning only. To establish a
host-specific pass, use the selected receiver's sampling instant and setup
specification and compare against MISO measured at that receiver. [Competition I/O FAQ](https://blog.janestreet.com/protocol-emulator-asic-competition/)

**Pin handoff.** The tile drops UIO output enable asynchronously when project
`ena` falls. The **3.089 ns** modeled maximum ends at the tile's output-enable
pin. The physical deadline is the earliest instant the next driver can turn
on at the shared net. The mux also isolates deselected projects, but its
description supplies no numerical external-pad release time. Keep the other
driver in input mode through deselection. For a timed handoff, compare the
latest pad release with the earliest new driver enable, including skew and
margin. For a bench measurement, first drive a UIO pin against a weak
pull in the opposite direction, keep other drivers disabled, and scope
deselection and the released line. Account for the pull resistance, load
capacitance and scope threshold when interpreting the transition.
[Mux isolation](https://github.com/TinyTapeout/tt-multiplexer/blob/main/docs/INFO.md)

SPI CS ends only a host transaction. It does not release the programmable
UIO pins. MISO is on a dedicated output and drives zero when the parser
returns to idle. Use a dedicated host input or external isolation if several
SPI targets share the physical MISO wire.

Re-extract both sets of delay arcs after FIFO RTL is routed. Board-specific
setup and pin-turnaround constraints require the host peripheral or firmware
and the next driver's enable timing. Keep the existing sign-off checks until
those inputs are available.
