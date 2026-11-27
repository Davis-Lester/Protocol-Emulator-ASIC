# Current handoff

## Frozen engine for the PS/2 and SWD demonstrations

The hardware baseline is merged main at `a44dfb0`. Both protocol workspaces
start from the reviewed JTAG software at `33e73d7` so existing JTAG pin tests
are available. Local Codex owns programs, host tools and verification in the
`local/ps2-host` and `local/swd-host` worktrees.

[The freeze manifest](../config/frozen-engine.json) records the full commits,
source hashes, and reviewed submission identities. The ISA specification,
assembler and cycle model are recorded as reference versions. Source hashes
use Git blob bytes to avoid checkout-specific CRLF differences. Archived
routed Verilog and OASIS match byte for byte between the two listed runs.

From either worktree, compare hardware inputs with the frozen revision before
reporting a new program running on this hardware:

```sh
git diff --exit-code a44dfb0 -- src info.yaml .github/workflows/gds.yaml
```

First PS/2 milestone: load a keyboard receive program through SPI and verify
its pins and host readback against an independent keyboard model. First SWD
milestone: verify line turnaround and a debug-port ID read against an
independent target model. This checkpoint establishes the shared baseline
for both tests.


Updated 2026-11-23.

## JTAG gate-level and physical review

Local Codex reviewed the four supplied archives for
[Actions run 45207561284](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/45207561284).
Submission provenance identifies `e43fd6c627526a69138462fc3dcaabd901254c45`.
All archives pass ZIP integrity checks. Archived RTL, configuration, constraints,
documentation and info.yaml match that commit after newline normalization.
LibreLane 3.1.0.dev4 used ihp-sg13cmos5l revision
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.

| Corner | Setup slack | Hold slack | Slew / fanout / capacitance violations |
| --- | ---: | ---: | --- |
| Fast | +29.000325 ns | +0.107663 ns | 0 / 0 / 0 |
| Typical | +28.605048 ns | +0.284878 ns | 0 / 0 / 0 |
| Slow | +27.936758 ns | +0.603969 ns | 0 / 0 / 0 |

Final extracted STA agrees with submission metrics at a 50 ns clock period.
Setup and hold total negative slack are zero. Final routing and Magic DRC,
antenna and LVS error metrics are zero. Netgen reports a unique circuit
match. All ten prechecks pass and all three KLayout DRC XML files contain
zero items. Lint reports zero errors and warnings. The flow error log is
empty, and its warning log matches the previously reviewed SPI run.

The gate-level test_engine_pins passes at 55,529,000 ns. Its shared testbench
runs the 81-clock JTAG sequence after the earlier UART, SPI and I2C tests.
It verifies reset, instruction selection, 13-bit register updates, BYPASS,
FIFO stalls and STOP. The cocotb comparison checks scan data read through
host SPI. The local regression and both negative controls were also
rechecked against their saved input hashes and replies. Executable test
inputs match between local tested commit c1aa491 and the submitted commit.

The routed netlist, OASIS and metrics match the reviewed I2C artifacts byte
for byte. Standard-cell area is 261800 square micrometers and core utilization
is 21.6691%. JTAG runs through a new program and host software on the frozen
hardware implementation. Physical hardware validation remains pending.

Gate-level and precheck XML contain no embedded commit, so association follows
the supplied bundle. The gate-level job uses functional cell models.
Per-corner timing acceptance follows extracted STA. Top-level job transcripts
and exit codes are absent from the supplied ZIPs. Physical step COMMANDS,
final reports and the gate-level waveform are present.

Reproduce this review from the outer checkout with
`python runs/jtag-controller-gds/review.py`. Parsed results and archive hashes
are in `runs/jtag-controller-gds/reviewed-results.json`.
The JTAG milestone is ready for integration review. The merged-main I2C review is recorded below.

## Merged I2C baseline review

Local Codex reviewed the four supplied archives for
[Actions run 45205787143](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/45205787143).
The submission identifies merged main commit
`a44dfb0d8bd59d4eff65dcbb6729176af8b9ada4`. Archived source matches the
commit after newline normalization and all ZIP integrity checks pass.

The routed netlist, OASIS layout and metrics are byte-identical to the reviewed
I2C branch artifacts. Fast, typical and slow setup/hold slack match the I2C
table below, with zero setup/hold total negative slack and zero fanout, slew
and capacitance violations. DRC, LVS and antenna checks pass. All ten prechecks
pass and the three KLayout DRC XML files contain zero items. The gate-level
test_engine_pins passes at 47,107,000 ns. Executable test inputs match the
locally verified I2C commit 94f9c75.

This confirms the merged I2C baseline used for the JTAG demonstration.
The archive association and functional-model limitations described above also
apply here. Reproduce the review from the outer checkout with
`python runs/i2c-main-gds/review.py`. Parsed results and archive hashes are
in `runs/i2c-main-gds/reviewed-results.json`.

## JTAG on the frozen pin engine

The baseline is merged main commit `a44dfb0d8bd59d4eff65dcbb6729176af8b9ada4`.
Its RTL, constraints, physical configuration, assembler and cycle model match
the reviewed I2C design at `94f9c75`. The src tree is
`e05ebe7a249038f1658cc626f23a21c1d9dc97af`. Keep this baseline for the
program-only demonstration. The merged-main physical run passes the review below.

Local Codex implemented four-wire JTAG on `local/jtag-controller` at
`c1aa491`. The controller image occupies 14 of the 64 available words.
Host software selects the scan path, length and shifted value. See the
[host instructions and wiring](../README.md#scan-a-jtag-target).

The behavioral RTL regression passed on that commit with Verilator 5.026
and GCC 14.2.0. All 26 recorded commands returned zero, all recorded input
hashes match, and simulation finished at approximately 56 ms. The TAP saw
81 clocks. From Pause-DR it reached Reset and then Idle. Both four-bit IR
captures returned 0x5. Two 13-bit scans returned 0x1357 and then 0x1791.
Eight-bit BYPASS returned 0x2C for 0x96 input, and one-bit BYPASS returned
zero. Empty TX and full RX both held TCK low. All preceding protocol
regressions and all 45 software tests passed.

Two corrupted copies of the image exercised the independent checkers.
Misrouting TMS failed the reset-sequence assertion. Sampling P0 in place
of TDO failed the host IR readback comparison. Full logs and command
records are in this worktree's ignored `runs/verilator-engine-_utcqjpj/`,
`runs/drop_tms-r161jzf0/` and `runs/sample_tms-uai63jyg/`. The next
acceptance step is the JTAG branch's official gate-level and physical review.

## I2C controller physical and gate-level review

Local Codex reviewed the four supplied ZIP archives for
[Actions run 45094314290](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/45094314290).
Submission provenance identifies `94f9c75e1e39c065f895c426707adb3c0dd7202b`.
Archived RTL, SDC, configuration, documentation and info.yaml match that commit
after newline normalization. All four archives pass integrity checks.
LibreLane 3.1.0.dev4 used ihp-sg13cmos5l revision
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.

| Corner | Setup slack | Hold slack | Slew / fanout / capacitance violations |
| --- | ---: | ---: | --- |
| Fast | +29.000325 ns | +0.107663 ns | 0 / 0 / 0 |
| Typical | +28.605048 ns | +0.284878 ns | 0 / 0 / 0 |
| Slow | +27.936758 ns | +0.603969 ns | 0 / 0 / 0 |

Extracted final STA and submission metrics agree at a 50 ns clock period,
with zero setup and hold total negative slack. Final routing DRC, Magic DRC,
antenna, LVS and lint error/warning metrics are zero. Netgen reports a unique
circuit match. All ten prechecks pass and all three KLayout DRC XML files
contain zero items. The routed netlist, OASIS and metrics match the reviewed
SPI artifacts byte for byte. Standard-cell area is 261800 square micrometers
and core utilization is 21.6691%.

The gate-level test_engine_pins passes at 47,107,000 ns. At this commit the
shared pin driver exercises 18 I2C scenarios across both speeds, including
write and repeated-START read, direct read, target NACKs, finite stretch,
SDA held low after ACK, stretch timeout, recovery, TX-empty and RX-full waits.
The local Verilator run in `runs/verilator-engine-hoedpw3u/` also passes,
and all recorded source input hashes match the reviewed checkout. Its measured
data-bit periods are 10,050 ns and 2,550 ns with the digital pull-up model.
The write image occupies 46 words and the read image occupies all 64 words.
The prior local software check passed 45 tests.

The I2C programs reserve P7 for output readback in addition to P2/SCL and
P3/SDA. Leave P7 unconnected on the board. The testbench models pad readback
and pull-up delay. Analog bus edges and physical pad behavior require board
validation. The gate-level job uses functional cell models, while per-corner
timing acceptance follows extracted STA. Gate-level and precheck XML contain
no embedded source commit, so their association follows the supplied bundle.
Top-level job transcripts and exit codes are absent from these ZIPs. Physical
step COMMANDS, final reports and the gate-level waveform are present.

Archive hashes, comparisons and parsed results are saved in the outer checkout
at `runs/i2c-controller-gds/reviewed-results.json`. Reproduce the review from
that checkout with `python runs/i2c-controller-gds/review.py`.
The I2C milestone is ready for integration review.

## SPI controller physical review

Local Codex reviewed the four supplied archives for
[Actions run 44982346056](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44982346056).
Submission provenance identifies `a32bf7ec04c6d100340d254570af80cf15699368`.
Archived RTL, configuration, constraints, documentation and info.yaml match
that revision after newline normalization. Every archive passed ZIP integrity
checks. LibreLane 3.1.0.dev4 used ihp-sg13cmos5l revision
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.

| Corner | Setup slack | Hold slack | Slew / fanout / capacitance violations |
| --- | ---: | ---: | --- |
| Fast | +29.000325 ns | +0.107663 ns | 0 / 0 / 0 |
| Typical | +28.605048 ns | +0.284878 ns | 0 / 0 / 0 |
| Slow | +27.936758 ns | +0.603969 ns | 0 / 0 / 0 |

Final extracted STA reports and submission metrics agree. The clock period
is 50 ns, with zero setup and hold total negative slack. Final routing and
Magic DRC, antenna and LVS metrics are zero. Netgen reports that the circuits
match uniquely. All ten prechecks passed and the three KLayout DRC XML files
contain zero items. Lint reports zero errors and warnings.

The gate-level test_engine_pins passed after 22,786,350 ns. The shared bench
at the source revision includes all four SPI modes with six full-duplex
frames per mode, CS setup and hold, 500 ns SCK halves, FIFO stalls and STOP,
plus the preceding UART and pulse checks. The job uses functional cell
models. Corner timing acceptance follows extracted STA. Gate-level and
precheck XML contain no embedded commit, so their association follows the
supplied bundle. Top-level job command transcripts and exit codes were absent.
The archive preserves physical step COMMANDS and detailed reports.

The routed netlist, OASIS layout and final metrics are byte-identical to
the reviewed UART RX slew-repair artifacts. Placed standard-cell area is
261800 um² and core utilization is 21.6691%. This run exercises the additional
SPI programs on that hardware implementation.

Archive hashes, source comparisons, commands and parsed acceptance results
are in the outer checkout's ignored
`runs/spi-controller-gds/reviewed-results.json`. Reproduce the archive review
with `python runs/spi-controller-gds/review.py` from the outer checkout.
The SPI milestone is ready for integration review. I2C controller programs
and an independent target checker are next.

## SPI controller on `local/spi-controller`

Local Codex added four loadable SPI images and a peripheral pin checker at
`c535ffa`, then tightened the MISO timing check at `19904b4`. The branch
starts at the reviewed UART RX revision `47dddce`. The programs drive a
1 MHz SCK from the 20 MHz project clock and transfer one full-duplex,
MSB-first byte per CS assertion. Modes 0 and 2 use 19 words. Modes 1 and 3
use 18 words.

The shared RTL and gate-level bench loads each assembled program through
the host SPI port. At `19904b4` the local RTL run passed six distinct
transfers per mode, with all 24 replies read in order. The monitor checked
the selected sampling edge, 500 ns SCK halves, at least 500 ns of CS setup
and hold, MOSI setup, inactive clocks during FIFO stalls and STOP pin
release. It delayed target MISO and inverted it after the sampling window.
Two negative controls independently detected a late RXBIT and a shortened
SCK half-period.

Local replay used Verilator 5.026 and GCC 14.2.0 with behavioral RTL and
no PDK. `python runs/verify.py` passed all four mode markers, the UART
checks and the 29-sample pulse comparison. Verilator reported about 23 ms
of simulated time. All 25 recorded commands returned
zero. The six existing timescale and bench width warnings were present.
`python runs/verify_fifo_edges.py` passed the exact-edge FIFO checks.
All 42 software tests and the workspace structure check passed.
Manifests and logs are in this worktree's ignored directories
`runs/verilator-engine-t5b4pglg/`, `runs/verilator-fifo-edges-dxp5nr94/`
and `runs/spi-negative-controls-ajzdv0k_/`.

The RTL, physical configuration, constraints and GDS workflow match those
used for the passing UART RX layout at `8cb7eb0`. The official physical
and gate-level review is recorded above.

## UART RX slew repair on `local/uart-rx-slew`

The [repair run 44863037788](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44863037788)
at `8cb7eb05cb305c48c688dcdc976a4ba89c104578` passes the reviewed UART RX
physical acceptance checks. Archived RTL, configuration and SDC files match
that commit after newline normalization. LibreLane 3.1.0.dev4 used
ihp-sg13cmos5l revision `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.

| Corner | Setup slack | Hold slack | Slew / fanout / capacitance violations |
| --- | ---: | ---: | --- |
| Fast | +29.000325 ns | +0.107663 ns | 0 / 0 / 0 |
| Typical | +28.605048 ns | +0.284878 ns | 0 / 0 / 0 |
| Slow | +27.936758 ns | +0.603969 ns | 0 / 0 / 0 |

The final detailed reports and submission metrics agree on all corner counts.
Setup and hold total negative slack is zero at the 50 ns clock target.
Routing and Magic DRC, antenna and LVS metrics are zero. All ten prechecks
passed, with zero items in all three KLayout DRC XML files. The gate-level
test_engine_pins passed after 14,564,350 ns, exercising the shared UART RX,
UART TX and pulse tests. Precheck and gate-level XML have no embedded commit.
Their association follows the supplied artifact bundle.

Post-global-routing repair ran with the requested 400 µm wire length and
20% slew margin. It inserted 175 buffers in 151 long nets. OpenROAD warned
that the length limit was below its delay-optimal value of 4688 µm.
The final setup and hold reports above account for the resulting routed design.
Placed standard-cell area is 261800 µm² and utilization is 21.6691%.
All eight protocol-input synchronizer pairs remain intact. The 252 reported
downstream reset-release paths meet recovery and removal at every corner.
Worst recovery slack is +45.871578 ns and removal slack is +0.250429 ns.
Maximum tabulated macro clock-to-MISO delay is 5.821650 ns and
ena-to-OE-disable delay is 2.520360 ns, excluding wrapper, pad and board delays.

The outer checkout's ignored `runs/uart-rx-slew-gds/reviewed-results.json`
records archive hashes, provenance, source comparisons and parsed results.
The UART RX branch is ready for integration review.

### Repair diagnosis

The final DEF from RX run 44849276133 shows 685.44 µm of metal between
NOR4 output `_07127_/Y` and its single buffer load `_07128_/A`. The global
route guide already shows the detour to the left edge. The placement repair
loaded all three timing corners, but the flow skipped design repair after
global routing. The slow-corner report shows 3.382752 ns at the buffer
input against a 2.507400 ns limit.

Local Codex enabled post-global-routing design repair, set its maximum wire
length to 400 µm and its slew margin to 20%. A wire following the archived
route exceeds that threshold and is eligible for buffering. The margin gives
detailed routing and extraction headroom. The final slew checker now covers
all corners. Its previous corner pattern matched none of the reported names.

Local checks confirmed that all four settings exist in the archived LibreLane
configuration and survive the merge with the generated project settings.
All three RTL files and both SDCs match the archived RX submission.
`python scripts/workflow.py check` passed. Physical validation was completed
by the official GDS workflow recorded above. The acceptance criteria require
zero final slew and fanout violations at each corner, nonnegative setup and
hold slack, and passing antenna, DRC, LVS, precheck and gate-level tests.

## UART RX physical review

The supplied archives identify commit `a22bd464b1f2313dff87b8657b47f85f64cbb999`
and [Actions run 44849276133](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44849276133).
Archived RTL and SDC files match that commit after newline normalization.
LibreLane 3.1.0.dev4 used ihp-sg13cmos5l at
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.

| Corner | Setup slack | Hold slack | Fanout violations | Slew violations |
| --- | ---: | ---: | ---: | ---: |
| Fast | +29.003814 ns | +0.107079 ns | 0 | 0 |
| Typical | +28.610882 ns | +0.283972 ns | 0 | 0 |
| Slow | +27.945941 ns | +0.602444 ns | 0 | 2 |

Timing uses the 50 ns target and original sign-off constraints. Total negative
setup and hold slack is zero. Final routing and Magic DRC, antenna and LVS
mismatch metrics are zero. All ten prechecks passed, with zero items in the
three KLayout DRC reports. The gate-level XML records test_engine_pins passing
after 14,564,350 ns, covering the shared RX/TX/pulse bench from this commit.
The gate-level and precheck archives have no embedded commit ID. Their
association with the GDS run follows the supplied artifact bundle.

Physical closure remains open for the two slow-corner slew entries.
`_07127_/Y` (sg13cmos5l_nor4_1) drives `_07128_/A`
(sg13cmos5l_buf_4) on `_02409_`. Both share a 2.507400 ns limit.
Reported slews are 3.382252 ns and 3.382752 ns respectively, with
slacks -0.874852 ns and -0.875352 ns. The driver has one load and
0.130758 pF reported capacitance. This path still meets setup timing.
The flow log reports the offending corner and then prints
"No max slew violations found". The final metrics and detailed checks agree
on two violations. Repair this route or its driver and repeat the official
flow with zero slew violations required across all corners.

The routed netlist retains all eight protocol-input synchronizer pairs.
Each first-stage Q reaches only its matching second-stage D, including any
inserted buffers or hold-delay cells. The reset release stage has 252 reported
downstream recovery and removal endpoints at every corner. Worst recovery
slack is +45.684490 ns, worst removal slack +0.237778 ns.
Maximum tabulated clock-to-MISO delay is 6.117070 ns. Maximum tabulated
ena-to-OE-disable delay is 2.518820 ns. These are macro-boundary values over
the generated load tables, excluding external pads, mux and board.

Full artifacts, archive SHA-256 values and parsed results are in the outer
checkout's ignored `runs/uart-rx-gds/` directory and
`reviewed-results.json`. Local Codex reviewed these results and recorded
the open slew repair. A new physical repair run remains pending.

## UART RX on `local/uart-rx`

Local Codex added synchronized protocol inputs, the 13-word receive program
and the four-byte RX FIFO on top of FIFO TX commit `04cfa13`. The pin bench
loaded the program over SPI, drove P2 as an independent 8N1 transmitter,
and read back consecutive bytes 96, 00, FF and 53 (hex). A fifth frame
faulted and preserved those four bytes. A bad stop bit faulted while an
earlier byte remained readable. After CLEAR and START, byte A9 was received.
The test also rejected a 2 us start pulse. Bit intervals exercised were
8571, 8681 and 8801 ns at the 20 MHz system clock.

The behavioral RTL and pin bench are at `91c7194`. The direct FIFO bench
at `ca3b848` passed with simultaneous reads and writes on empty and full
queues. The first run of the extended direct bench issued CLEAR before the
preceding TX test had halted. The corrected bench retires HALT first.
The local replays used Verilator 5.026, GCC 14.2.0 and no PDK. The completed
pin run resumed the interrupted compilation with `python runs/resume.py`.
Its manifest and logs are under `runs/verilator-engine-ezq06z5p/`. The
simulator printed UART RX PIN CHECKS PASSED and ENGINE PIN CHECKS PASSED.
The UART TX scoreboards and 29-sample pulse comparison passed. The edge
replay (`python runs/verify_fifo_edges.py`) printed FIFO EDGE CHECKS PASSED.
Its manifest is under `runs/verilator-fifo-edges-ljh7thpc/`. Both runners
returned zero. All 42 software tests, the infrastructure check and design
lint with the existing filename warning suppressed passed.

Next, run the official GDS and gate-level jobs on this branch. Recheck fanout,
setup and hold across corners, including the new protocol input synchronizers.

## FIFO-fed UART TX on `local/uart-fifo`

Local Codex implemented a four-byte TX FIFO, WRITE_TX, GET_TX and JMP, plus
the streaming program and pin tests at `dd5f49a`. The exact-edge arbitration
test and its RTL CI step are at `93e2edb`. WRITE_TX accepts writes before
START or during execution, and uo[4] advertises free space. A full write
returns status 5. The pin bench loaded the 13-word program and decoded
96, 00, FF, 53, A9 and 3C (hex) at nominal 115200 baud, 8N1. The first
five frames began 1740 clocks apart. The sixth began after FIFO starvation
and a live refill. All 15,561 samples matched the expected transmission,
idle hold and pin release. The fixed-byte UART test and the 29-sample pulse
comparison also passed.

Local behavioral replays used Verilator 5.026, MSYS2 GCC 14.2.0 and no PDK.
`python runs/verify.py` at `dd5f49a` and `python runs/verify_fifo_edges.py`
at `93e2edb` both returned zero. All recorded command exit codes were zero,
and each bench printed its pass marker. The edge test checks forwarding on
the final GET_TX timeout edge, a write arriving one edge too late, and
concurrent pushes and pops with a full or partially filled queue.
Local command manifests, logs and traces are in the ignored directories
`runs/verilator-engine-nk41t29h/` and `runs/verilator-fifo-edges-k_8zdlk7/`.
The 42 software tests and infrastructure check passed. Standalone design
lint reported zero warnings with `-Wall -Wno-DECLFILENAME`. The shared
pin bench elaboration retained three timescale and three width warnings.

The physical-flow owner should run the official Tiny Tapeout GDS, gate-level
pin regression, precheck and per-corner fanout and timing checks on the FIFO
branch. Routed results and extracted host timing numbers below describe the
prior `6c0b456` layout. Repeat path extraction on the FIFO layout.

## UART fanout repair on `local/uart-fanout`

The combined branch uses UART RTL from `525643a` and clock-tree settings
from `5c4970c`. The UART build had 132 violations at each of three corners:
127 clock leaves, the root clock buffer and four signal buffers. The worst
clock leaf drove 17 loads against a limit of eight. Four antenna diodes on
the UART signal net `_02092_` contributed to its ten loads.

Clock tree synthesis requests four sinks per cluster and 80 um buffer
spacing. The implementation signal-fanout target is four, leaving room for
up to four more loads against the observed eight-load limit. Sign-off uses
the original flow constraints. New placement and routing can change the
diode count.

The [combined GDS run](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44681569474)
at `6c0b456` reported zero fanout violations across the three corners,
worst setup slack +27.515 ns and worst hold slack +0.106 ns at 20 MHz.
DRC, antenna, LVS, Tiny Tapeout precheck and the UART gate-level test passed.
Local Codex traced the routed SPI synchronizers, reset distribution and
output masking in the [CDC and reset review](CDC_REVIEW.md).

## UART TX milestone on `local/uart-tx`

Base commit `2503f78`; tested RTL and bench commit `709eecf`. Local Codex
integrated the existing 13-word UART example, implemented LOAD_TX, TXBIT,
LOOP and DJNZ and verified pin behavior. Server retains physical-flow ownership.

The host loaded the example over SPI. At 20 MHz the simulated TX pin P1 was
enabled high on edge 2, fell for start on edge 176 and was released on edge
1916 after one full stop bit. Sampling at the nominal 115200-baud centers
decoded 0x96 LSB first. Every driven bit lasted 174 clocks (8.70 us).
The shared checker validates every sample of driven idle, start, data and
stop, plus output enables, RUNNING and FAULT. The pulse and host regression
also passed with all 29 reference samples matching.

Local command: `python runs/verify.py` in this checkout. Verilator 5.026,
MSYS2 GCC 14.2.0, behavioral RTL, no PDK. Elaboration, compilation, linking
and simulation returned zero. The bench printed ENGINE PIN CHECKS PASSED.
Commands, exit codes, hashes, CSVs and transcripts are in the ignored
`runs/verilator-engine-7ir2j2zu/`. Additional runs verified MSB-first shifting
and confirmed detection of an incorrect byte and shortened data bits. All 42
software tests passed. A separate RTL-only `--lint-only -Wall` run exited 1
on the existing top-module filename warning (DECLFILENAME). See
`runs/uart-rtl-lint/`. On the original physical settings, the [UART GDS run](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44630829222) passed the gate-level test, timing, DRC, LVS and precheck with the fanout violations listed above.

## Fanout repair on `local/fanout-repair`

Local Codex owns this configuration change and baseline report review. Server
Codex owns the physical rerun. The baseline is the official
[run 44603796511](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44603796511)
at `2503f7867acc23bd2d3b4dd65663ba0e3b42c86b`, after the reset edit.
LibreLane 3.1.0.dev4 used ihp-sg13cmos5l at
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`. The archived final metrics
show zero lint warnings, setup slack +28.208 ns and hold slack +0.108 ns.
The archives preserve per-step commands. Top-level job exit codes were absent.

All three post-route corners list the same 128 pins in
`55-openroad-stapostpnr/<corner>/checks.rpt`. Each has a limit of eight.
The root clock buffer drives 16 branches and 124 leaf clock buffers drive
11 to 16 loads each. In the final netlist, `fanout498/X` drives eight logic
loads and three antenna diodes. Both `fanout228/X` and `fanout248/X` drive
eight logic loads and one antenna diode.

The candidate configuration requests four sinks per CTS cluster and 80 um
clock-buffer spacing to encourage intermediate branches. P&R uses a fanout
target of five so repair can leave room for the three additional diode loads
seen in the baseline. Both SDC files source the flow's base constraints.
Sign-off uses the original fanout limits. The [minimal-engine rerun](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44629495353) reported zero fanout violations at every corner. Check the resolved configuration, actual CTS command, and
final per-corner `checks.rpt` **and** fanout metric. Acceptance requires zero
fanout violations in each corner, nonnegative setup and hold slack at 50 ns,
and passing DRC, antenna, LVS, precheck and gate-level tests. The separate
CDC/reset constraints review is recorded above for the combined layout.

The repository's standalone pin bench passed on the exact baseline RTL using
Verilator 5.026 and MSYS2 GCC 14.2.0 (behavioral simulation, no PDK).
Questa and ModelSim both stopped at launch with Windows error 623.
The local replay command was `python runs/fanout-rtl-check.py` in the parent
checkout. `runs/verilator-engine-8s05nu2p/result.json` there records the commit,
source hashes, tool versions, commands and exit codes. Elaboration, compilation
and simulation returned zero. Elaboration reported three module timescale and
three bench width warnings. Simulation printed `ENGINE PIN CHECKS PASSED`,
and the model comparison matched all 29 rows. P0 rose on edge 3, fell on 23
and was released on 28. All 42 software tests and the infrastructure check
also passed.

## Earlier minimal engine status

- Official template imported at 4b1204ab387b5ab94db1d57067051d8d89a2f83c.
- The official flow now targets tt_um_davis_lester_protocol_emulator. The
  original adder is preserved in src/project.v and in the c9e002c baseline.
- info.yaml targets 20 MHz; src/config.json uses a matching 50 ns period.
- Assembler and Python cycle-level model implement all 16 ISA instructions, with
  atomic loading/control, four-byte FIFOs, synchronized protocol inputs and pin safety.
- Timed-pulse example runs in the model: P0 high at edge 3, low at 23, released
  at 28; 20 cycles high = 1 us at an assumed 20 MHz. No actual clock is measured.
- Minimal engine RTL passed its SPI/pulse simulation in Questa. The first
  physical run at 8eaae90 passed the checks recorded below.
- Software-task source commit: c9e002ce6db3d3e4f6e151e9f619cdad7af516ba.

## Ownership

- Local: specification, cycle model, assembler/host tooling, documentation and review.
- Local/minimal-engine: RTL, host parser, pin verification and local Questa
  execution. The owner ran Questa from PowerShell and Codex reviewed the logs.
- Server: EDA inventory, synthesis and Cadence/custom macro execution.

## Engine simulation, 2026-11-19

Follow-up lint review removed the synchronous rst_n check from the program-memory
write enable. The asynchronously reset loading/count state already rejects
WRITE_WORD while reset is held. This addresses the reported SYNCASYNCNET cause.
The earlier passing simulation below predates this edit. The new local attempt
in runs/questa-engine-_6aotr9g/ was blocked by Windows error 623. Re-run Questa
and the GitHub linter on the updated source before accepting the fix.

- Base commit fa9859ffc9d537af55e3f009a3585added1f1d59 plus working-tree RTL
  on local/minimal-engine. Run manifest records SHA-256 for each source, bench,
  program, assembler, model and runner. Hashes matched the reviewed checkout.
- Command: `python scripts/questa_engine.py --bin "C:\intelFPGA\23.1std\questa_fse\win64"`.
  Questa Intel Starter FPGA Edition 2023.3, behavioral RTL, no PDK used.
  Version queries, vlib, vlog and vsim each returned 0. Compilation reported
  zero errors and warnings. Simulation printed ENGINE PIN CHECKS PASSED at 7532 us.
- The host loaded the assembled seven-word image over mode-0 SPI. At acceptance
  RUNNING went high. All 29 samples (acceptance through HALT) matched the Python
  model for OUT, OE, RUNNING and FAULT. P0 was enabled low on edge 2, high on
  edge 3, low on edge 23, then released with RUNNING low on edge 28.
- Assertions covered malformed and aborted requests, short and excess loads,
  protected writes while running, STOP, sticky faults, CLEAR, deselection,
  open drain and past-end fetch at address 64. The remaining twelve opcodes
  and the byte FIFOs are future work.
- Full logs, per-command exit codes, manifest and observed CSV:
  `runs/questa-engine-3bzq6mpy/` (ignored). The local Codex process launch
  failed with Windows error 623 in a separate attempt.

## Minimal engine physical results, 2026-11-19

The owner supplied four archives in `runs/minimal-engine-before-lint-fix/`.
Submission and GDS provenance identify commit
8eaae90b08829eec3e719fa984109384eaa95a9a and
[run 44587959919](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44587959919).
Archived engine RTL matches that commit after newline normalization.

| Measurement or check | Inspected result |
| --- | --- |
| Flow / PDK | LibreLane 3.1.0.dev4, ihp-sg13cmos5l, revision 89d42ee6d2fd9b50b86a1aada6fee6673c3e6008 |
| GDS | flow.log ends with Flow complete; final layout present |
| Footprint | 1724.16 x 710.64 um, about 1.22526 mm^2 |
| Synthesis | 7474 cells, 159767.2944 um^2 |
| Placed standard cells | 10146 cells, 199513 um^2, 16.5136% core utilization |
| Sequential cells | 1715 cells, including the register-based instruction memory |
| Magic DRC / routing DRC | Zero final violations |
| LVS | Circuits match uniquely; zero mismatch metrics |
| Precheck | Ten testcases passed; all three KLayout DRC XML reports have zero items |
| Gate-level test | test_engine_pins passed, 7532000 ns simulated |
| Timing target | 50 ns (20 MHz), fast/typical/slow corners |
| Setup / hold | Worst setup slack +28.0207936 ns, hold +0.1068759 ns; TNS zero |
| Register-to-register setup | Worst slack +36.098003 ns |
| Fanout | 136 reported maximum-fanout violations, open for review |
| Lint | Zero errors, one SYNCASYNCNET warning in this source revision |

Precheck and gate-level XML contain no commit ID. Their run association relies
on the owner-supplied bundle. The gate-level result uses the pin tests and pulse
scoreboard. A separate RTL test artifact was absent. Raw GitHub job exit statuses
and top-level invocation logs were absent. Per-step COMMANDS files, reports and
the final SDC remain in GDS_logs (1).zip. Parsed metrics and archive SHA-256
hashes are saved in `reviewed-results.json` beside the archives.

Timing uses generic fallback SDC, including 10 ns clock-relative input/output
delays for asynchronous host/reset inputs. Complete the CDC/reset constraint
review and investigate the fanout violations before accepting physical closure.
The flow uses Magic DRC, and the separate precheck performs KLayout CMOS5L DRC.
XOR and EQY were skipped. The usual LEF58 enclosure and missing IR source-location
warnings remain. The current reset lint fix postdates these results and needs
fresh simulation/lint/physical verification.

## Template reference

The [reviewed Actions run](https://github.com/Davis-Lester/Protocol-Emulator-ASIC/actions/runs/44566481686)
at c9e002ce6db3d3e4f6e151e9f619cdad7af516ba contains the original adder RTL
with the 50 ns constraint. GDS completed, Magic DRC had zero errors, Netgen
matched uniquely, all ten prechecks passed, and the supplied gate-level test
passed. The 8x4 LEF is 1724.16 x 710.64 um. The adder used 821.923 um^2 of
placed standard cells. LibreLane 3.1.0.dev4 used ihp-sg13cmos5l at
89d42ee6d2fd9b50b86a1aada6fee6673c3e6008. See the reviewed archives and
report under `runs/template-baseline/`. The separate adder RTL job is unverified.

## Next tasks

1. Confirm host reset/select sequencing and the external MISO and pin-disable
   timing budgets before changing the asynchronous interface constraints.
2. Integrate the reviewed SPI controller branch. Continue with I2C controller
   programs and an independent target checker.
3. Server: synthesize the complete register-memory baseline early and report area
   and timing before increasing memory or adding a custom macro.

## Environment evidence

Python 3.12.7 and Git are available. The local Questa run above exercised its
compiler, simulator and license. Make and Icarus were absent from the local
PATH during review. ECE server inventory is pending.
Record host/compute policy, tool versions, license checks, exact CMOS5L setup,
flow dependencies and backup location after discovery. Never paste credentials.

## AI contribution

At the owner's request, AI assistance drafted the initial architecture, project
metadata/pinout and documentation, then implemented the Python assembler/model,
pulse example and software functional tests. For the first RTL milestone Codex
implemented the SPI loader, pulse engine, Questa runner and pin-level checks.

## Software baseline validation (before RTL)

- `python scripts/workflow.py test-model`: 42 tests passed under Python 3.12.7.
- `python scripts/workflow.py demo`: model halts at cycle 28, releases pins and
  emits the pulse hex image, CSV trace and VCD waveform under ignored runs/.
- `python scripts/workflow.py check`: starter structure/provenance check passed.
- `git diff --check`: passed. Example RTL, metadata, physical
  configuration and official template test/GDS workflows are not modified.
- These are software functional/infrastructure checks, not RTL or EDA verification.

## Task handoff format

- Task and owner:
- Branch and source commit:
- Changed interfaces/files:
- Commands and observed results:
- Acceptance criteria:
- Blockers and next action:
