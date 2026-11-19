# Current handoff

Updated 2026-11-19.

## Status

- Official template imported at 4b1204ab387b5ab94db1d57067051d8d89a2f83c.
- Origin is configured for Davis-Lester/Protocol-Emulator-ASIC. No remote state,
  push or Actions result was verified in this task.
- Initial architecture selected in docs/ARCHITECTURE.md. Metadata/pin names describe
  the planned engine; RTL and testbench still implement the template adder.
- info.yaml targets 20 MHz; src/config.json uses a matching 50 ns period.
- No engine RTL, simulation pass, area result, timing closure or EDA result claimed.
- Pre-edit source commit: 6d3c82c847ec117bc3dd2606402a6d0c22c5de6e.

## Ownership

- Local: specification, cycle model, assembler/host tooling, documentation and review.
- Server: EDA inventory, simulations, Cadence/custom macro execution.
- Current documentation task: local/architecture-v1 in an isolated checkout.
  The original School checkout is outside this chat's writable roots. Apply the
  reviewed patch there on a task branch before handing this contract to the server.

## Next tasks

1. Obtain original template simulation and official GDS/precheck results at the
   pre-edit source commit; record commands, versions, logs and pass/fail evidence.
   Compare the 20 MHz constraint update separately. Keep a clean template
   reference before replacing RTL.
2. Local: implement the instruction encoder/assembler and cycle model from the
   architecture contract. Accept only when instruction timing, reserved fields,
   reset/load safety, branches and timeout cases have meaningful tests.
3. Local: implement the host loader and OUT/DELAY/HALT waveform demonstration.
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
metadata/pinout and documentation updates. These are specifications, not verified
hardware. Record later implementation and verification assistance separately.

## Validation of this change

- `python scripts/workflow.py check`: passed starter structure and template provenance.
- YAML parsed; all 24 pin keys and listed source/module/testbench references checked.
- `info.yaml` 20 MHz and `src/config.json` 50 ns checked for consistency.
- `git diff --check`: passed. Example RTL and testbench were not modified.
- These are infrastructure/reference checks, not RTL simulation or EDA verification.

## Task handoff format

- Task and owner:
- Branch and source commit:
- Changed interfaces/files:
- Commands and observed results:
- Acceptance criteria:
- Blockers and next action:
