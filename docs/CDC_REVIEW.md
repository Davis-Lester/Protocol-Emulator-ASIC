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

## Remaining verification

1. Check the actual host or wrapper sequence. With reset asserted, selection
   must settle in time for a rising clock to arm the chip and reset must
   remain low through that edge. Keep CS high for eight clocks after release.
   Establish the permitted pin-disable delay at deselection before assigning
   a physical budget to the output-enable path.
2. When changing constraints, compare targeted interstage setup/hold and
   downstream recovery/removal reports across all three corners. Confirm the
   intended SPI input paths are the only new exceptions. This review used the
   existing routed reports and introduced no timing exceptions.
