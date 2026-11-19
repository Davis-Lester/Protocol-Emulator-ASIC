# Programmable protocol emulator ASIC

Starter workspace for the Jane Street protocol-emulator competition: programmable pin timing, with UART, SPI and I2C implemented as programs. Target: Tiny Tapeout IHP CMOS5L, 8x4 tiles. Architecture is not frozen and no functional RTL or tapeout result is claimed.

## Start here

1. Run `python scripts/workflow.py check` and `python scripts/workflow.py doctor`.
2. With network access, run `python scripts/workflow.py bootstrap-template`. This imports the official Tiny Tapeout template and records its exact commit in `config/template-lock.json`.
3. Read the imported `README.tinytapeout.md`, `test/README.md`, `info.yaml` and `.github/workflows/` before running the official flow. The importer sets only the tile size to 8x4; rename the example top module, update metadata and replace the example tests when implementing the engine.
4. Run the unchanged template baseline and save its results before adding architecture or custom macros.
5. Follow [the environment setup](docs/SETUP.md), [milestones](docs/PLAN.md), and [handoff](docs/HANDOFF.md).

The official Tiny Tapeout flow is authoritative for submission. Cadence provides custom-block design and characterization; Questa provides additional verification; Vivado is optional FPGA validation. No Cadence-only tapeout flow is substituted for Tiny Tapeout.

## Commands

```text
python scripts/workflow.py check
python scripts/workflow.py doctor
python scripts/workflow.py bootstrap-template
```

`check` validates this starter workspace only. It does not simulate RTL or run DRC, LVS, timing, or precheck. `doctor` reports executable discovery, not working licenses or PDK qualification.

## Layout

| Path | Purpose |
| --- | --- |
| src/, test/, info.yaml | Added by official template import |
| model/ | Future cycle-accurate reference model |
| tools/ | Future assembler and host loader |
| programs/ | Future protocol programs |
| verification/ | Verification plan and future Questa/formal harnesses |
| macros/ | Portable custom-macro deliverables and interface contracts |
| scripts/ | Reproducible setup and checks |
| config/ | Committed version references; local settings are ignored |
| docs/ | Architecture, setup, handoffs and decisions |
| runs/, cadence-work/ | Ignored run output and authoritative local Cadence workspace |

Keep PDKs, credentials and proprietary assets out of Git. Follow the template's license for imported materials; choose and document a compatible license for original project work before public submission.
