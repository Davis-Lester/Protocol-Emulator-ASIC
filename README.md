# Programmable protocol emulator ASIC

Workspace for the Jane Street protocol-emulator competition: programmable pin timing, with UART, SPI and I2C planned as programs. Target: Tiny Tapeout IHP CMOS5L, 8x4 tiles. The initial architecture is documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). A Python assembler and cycle-level model now execute all 16 instructions, with a timed-pulse example and software tests. Current RTL is still the imported template adder; no functional protocol RTL or tapeout result is claimed.

## Run the software baseline

Python 3.10+ is sufficient; no third-party packages or EDA tools are required:

```text
python scripts/workflow.py test-model
python scripts/workflow.py demo
```

The demo assembles [programs/pulse.asm](programs/pulse.asm), runs it in the Python
model, and writes `runs/pulse.hex`, `runs/pulse.csv` and `runs/pulse.vcd`. P0 is
high from cycle 3 to cycle 23: 20 cycles, or 1 us at the assumed 20 MHz clock.
HALT releases it at cycle 28. See [model/README.md](model/README.md) for API/scope
and [tools/README.md](tools/README.md) for assembly syntax and image formats.
These are software results, not a simulation of the template RTL.

## Start here

1. Run `python scripts/workflow.py check` and `python scripts/workflow.py doctor`.
2. The official Tiny Tapeout template is already imported; its exact commit is recorded in `config/template-lock.json`. Do not rerun the importer over existing files.
3. Read `README.tinytapeout.md`, `test/README.md`, `info.yaml` and `.github/workflows/` before running the official flow. Metadata/pin names describe the planned engine; `tt_um_example` and its existing testbench still implement the adder. Rename module/testbench references together when implementing the engine.
4. Save the template simulation and physical baseline results before replacing RTL or integrating custom macros. Python model tests do not satisfy that gate.
5. Follow [the environment setup](docs/SETUP.md), [milestones](docs/PLAN.md), and [handoff](docs/HANDOFF.md).

The official Tiny Tapeout flow is authoritative for submission. Cadence provides custom-block design and characterization; Questa provides additional verification; Vivado is optional FPGA validation. No Cadence-only tapeout flow is substituted for Tiny Tapeout.

## Commands

```text
python scripts/workflow.py check
python scripts/workflow.py doctor
python scripts/workflow.py bootstrap-template
python scripts/workflow.py test-model
python scripts/workflow.py demo
```

`check` validates this starter workspace only. It does not simulate RTL or run DRC, LVS, timing, or precheck. `doctor` reports executable discovery, not working licenses or PDK qualification.

## Layout

| Path | Purpose |
| --- | --- |
| src/, test/, info.yaml | Added by official template import |
| model/ | Cycle-level Python ISA model; host SPI wire timing is not modeled |
| tools/ | Working assembler; physical host loader remains future work |
| programs/ | Runnable timed-pulse example; UART/SPI/I2C programs remain future work |
| verification/ | Software functional tests; future RTL/protocol/Questa/formal harnesses |
| macros/ | Portable custom-macro deliverables and interface contracts |
| scripts/ | Reproducible setup and checks |
| config/ | Committed version references; local settings are ignored |
| docs/ | Architecture, setup, handoffs and decisions |
| runs/, cadence-work/ | Ignored run output and authoritative local Cadence workspace |

Keep PDKs, credentials and proprietary assets out of Git. Follow the template's license for imported materials; choose and document a compatible license for original project work before public submission.
