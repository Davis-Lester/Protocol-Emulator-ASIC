# Current handoff

Updated 2026-11-19.

## Status

- Official template imported at 4b1204ab387b5ab94db1d57067051d8d89a2f83c.
- Origin is configured for Davis-Lester/Protocol-Emulator-ASIC. No remote state,
  push or Actions result was verified in this task.
- Initial architecture selected in docs/ARCHITECTURE.md. Metadata/pin names describe
  the planned engine; RTL and testbench still implement the template adder.
- info.yaml targets 20 MHz; src/config.json uses a matching 50 ns period.
- Assembler and Python cycle-level model implement all 16 ISA instructions, with
  atomic loading/control, four-byte FIFOs, synchronized protocol inputs and pin safety.
- Timed-pulse example runs in the model: P0 high at edge 3, low at 23, released
  at 28; 20 cycles high = 1 us at an assumed 20 MHz. No actual clock is measured.
- No engine RTL, RTL simulation pass, area result, timing closure or EDA result claimed.
- Software-task source commit: c9e002ce6db3d3e4f6e151e9f619cdad7af516ba.

## Ownership

- Local: specification, cycle model, assembler/host tooling, documentation and review.
- Server: EDA inventory, simulations, Cadence/custom macro execution.
- Software task: local/assembler-model in an isolated checkout. The original
  School checkout remains outside this chat's writable roots; deliver as a patch.
  The owner previously chose to integrate completed changes into main. No original
  checkout edits, commits or pushes are performed by this task.

## Next tasks

1. Obtain original template simulation and official GDS/precheck results at the
   original imported source commit 6d3c82c847ec117bc3dd2606402a6d0c22c5de6e;
   record commands, versions, logs and pass/fail evidence.
   Compare the 20 MHz constraint update separately. Keep a clean template
   reference before replacing RTL.
2. Local: use the implemented assembler/model as the software baseline. Add RTL
   loading, OUT/OE/DELAY/HALT and compare its trace against the pulse model;
   software tests alone do not verify RTL. Numeric SPI host response layout and
   wire-level parser/reset/CDC tests are still required.
3. Local: extend RTL to the remaining instructions, then UART TX/RX, SPI and I2C
   programs with independent protocol checkers. No such examples are claimed yet.
4. Server: synthesize the complete register-memory baseline early and report area
   and timing before increasing memory or adding a custom macro.

## Environment evidence

Previously observed: Python 3.12.7 and Git available; make and iverilog absent
from PATH. Intel FPGA ModelSim executables were discoverable, which is not a
license/compatibility test. No local EDA execution or server inventory is claimed.
Record host/compute policy, tool versions, license checks, exact CMOS5L setup,
flow dependencies and backup location after discovery. Never paste credentials.

## AI contribution

At the owner's request, AI assistance drafted the initial architecture, project
metadata/pinout and documentation, then implemented the Python assembler/model,
pulse example and software functional tests. No verified hardware is claimed.

## Validation of this change

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
