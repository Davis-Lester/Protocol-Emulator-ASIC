# Programmable protocol emulator ASIC

This Tiny Tapeout project targets IHP CMOS5L and 8x4 tiles. The Python assembler
and cycle model support all 16 instructions. The RTL loads 64 x 24-bit program
memory over SPI. The 16 instructions support timed pin output and separate UART transmit
and receive programs. See [the architecture](docs/ARCHITECTURE.md).

## Run the pulse and UART TX pin tests

From the repository root on Windows:

```powershell
python scripts/questa_engine.py --bin "C:\intelFPGA\23.1std\questa_fse\win64"
```

The runner assembles `programs/pulse.asm`, drives the physical SPI loading pins
in simulation and compares the sampled outputs and enables against the model at
every execution edge. It then loads [the UART program](programs/uart_tx.asm) over
SPI. The pin checker verifies a driven idle bit, start bit, eight data bits of
0x96 LSB first, one stop bit and release of P1. At 20 MHz each bit spans 174
clocks (8.70 us), giving 114943 baud, 0.22% below 115200. Use an external
pull-up to hold TX idle high once HALT releases P1. Each run saves its commands, tool versions, input hashes,
transcripts, CSV and result (as available) under `runs/questa-engine-*/`.
The official RTL and gate-level jobs use the same pin driver and comparison.

To stream UART bytes, load the 13-word [FIFO UART program](programs/uart_fifo_tx.asm)
and send START. While selected, `uo[4]` high means the four-byte TX FIFO has
space. For example, hold host CS low and transfer `07 01 A5 00 00` over
mode-0 SPI to enqueue 0xA5. The last two returned bytes are status and
response length. `00 00` means accepted and `05 00` means full. Retry
a full write once space is available. The program drives P1 high while
waiting, sends each byte as 8N1 and loops until STOP. To finish the last
frame, wait for its stop bit before sending STOP. The TX count covers
queued bytes and excludes the byte already in the shifter.

## Receive UART bytes

Load [uart_rx.asm](programs/uart_rx.asm), hold P2 high at idle, then issue START.
Drive 115200-baud 8N1 into P2 with a 20 MHz project clock. When `uo[3]`
(RX_VALID) rises, transfer `08 00 00 00 00` under one SPI CS assertion.
The last three returned bytes are `00 01 xx`, where `xx` is the oldest
received byte. A four-byte FIFO buffers arrivals while the host is busy.
A short start pulse is ignored. A low stop bit faults with code `80` hex.
A fifth byte received while the queue is full faults with code `05`.
Earlier bytes remain readable after either fault. Drain them, issue CLEAR,
return P2 to idle high and issue START to resume.

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
These files describe the Python model.

## Start here

1. Run `python scripts/workflow.py check` and `python scripts/workflow.py doctor`.
2. The official Tiny Tapeout template is already imported; its exact commit is recorded in `config/template-lock.json`. Do not rerun the importer over existing files.
3. Read `test/README.md` and `info.yaml` for RTL simulation and the engine source list.
4. The template adder reference is at commit `c9e002c`. Its physical results and the outstanding separate RTL simulation record are listed in the handoff.
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
| src/, test/, info.yaml | Engine RTL, pin-level simulation and Tiny Tapeout configuration |
| model/ | Cycle-level Python ISA model; host SPI wire timing is not modeled |
| tools/ | Assembler for the SPI-loadable instruction images |
| programs/ | Timed-pulse and fixed-byte UART TX programs |
| verification/ | Assembler and cycle-model tests |
| macros/ | Portable custom-macro deliverables and interface contracts |
| scripts/ | Reproducible setup and checks |
| config/ | Committed version references; local settings are ignored |
| docs/ | Architecture, setup, handoffs and decisions |
| runs/, cadence-work/ | Ignored run output and authoritative local Cadence workspace |

Keep PDKs, credentials and proprietary assets out of Git. Follow the template's license for imported materials; choose and document a compatible license for original project work before public submission.
