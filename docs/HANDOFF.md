# Current handoff

Updated 2026-11-19.

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
Sign-off uses the original fanout limits. The proposed settings require a
new official run. Check the resolved configuration, actual CTS command, and
final per-corner `checks.rpt` **and** fanout metric. Acceptance requires zero
fanout violations in each corner, nonnegative setup and hold slack at 50 ns,
and passing DRC, antenna, LVS, precheck and gate-level tests. The separate
CDC/reset constraints review is outstanding.

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
also passed. Physical closure of the candidate remains unverified.

## Status

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

1. Run the official Tiny Tapeout flow on the fanout candidate and inspect the
   per-corner reports against the acceptance criteria above.
2. Complete the physical CDC/reset constraint review. The pin tests exercise
   digital timing with oversampled SPI inputs.
3. Local: extend RTL to the remaining instructions, then UART TX/RX, SPI and I2C
   programs with independent protocol checkers. No such examples are claimed yet.
4. Server: synthesize the complete register-memory baseline early and report area
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
