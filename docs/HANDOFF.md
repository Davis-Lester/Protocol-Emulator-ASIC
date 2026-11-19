# Current handoff

Updated 2026-11-19.

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
`runs/uart-rtl-lint/`. UART gate-level and physical results are pending.

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

1. Verify the reset lint fix with Questa and the official RTL/GDS/precheck/GL jobs.
2. Investigate 136 reported maximum-fanout violations and complete physical
   CDC/reset constraint review. The pin tests exercise digital timing with
   oversampled SPI inputs.
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
