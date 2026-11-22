# Programmable protocol emulator ASIC

This Tiny Tapeout project targets IHP CMOS5L and 8x4 tiles. The Python assembler
and cycle model support all 16 instructions. The RTL loads 64 x 24-bit program
memory over SPI. The example programs generate timed pulses, transmit or receive UART,
drive a full-duplex SPI peripheral, and control a 7-bit I2C target. See [the architecture](docs/ARCHITECTURE.md).

## Run the pin tests

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

## Talk to an SPI peripheral

Connect P0 to CS_N, P1 to MOSI, P2 to MISO and P3 to SCK. Use a pull-up on
CS_N if the peripheral must stay deselected when the engine releases its pins.
The host loading interface on `ui[2:0]` always uses mode 0. Select the
peripheral mode by loading the corresponding program.

| Program | SCK idle | Peripheral samples MOSI on |
| --- | --- | --- |
| [spi_mode0.asm](programs/spi_mode0.asm) | Low | Rising edge |
| [spi_mode1.asm](programs/spi_mode1.asm) | Low | Falling edge |
| [spi_mode2.asm](programs/spi_mode2.asm) | High | Falling edge |
| [spi_mode3.asm](programs/spi_mode3.asm) | High | Rising edge |

1. With the engine stopped, issue CLEAR to discard previous FIFO contents and
   CONFIG_OD with mask zero for push-pull outputs. Assemble the chosen image,
   then send BEGIN_LOAD, its WRITE_WORD commands and COMMIT_LOAD.
2. Enqueue a byte with WRITE_TX and send START. Each queued byte produces
   eight MSB-first clocks under one CS assertion. At a 20 MHz project clock,
   SCK runs at 1 MHz, with 500 ns from CS assertion to the first edge and
   500 ns from the final edge to CS release.
3. When RX_VALID rises, use READ_RX to get the corresponding peripheral byte.
   Enqueue more bytes while TX_READY is high. An empty TX queue leaves CS high
   and SCK idle. A full RX queue can hold up delivery of the most recent reply.
   CS returns high before that wait, and reading a byte allows the program to resume.
4. Read the last expected reply before sending STOP for a clean finish.
   STOP during a transfer aborts it and releases the pins.

These examples frame each byte separately. A peripheral that needs command,
address and data under one CS assertion needs a program that holds P0 low across
those bytes.

## Talk to an I2C target

Connect P2 to SCL and P3 to SDA, each with an external pull-up to a compatible
I/O supply. Leave P7 unconnected so its pad reads back the level it drives. The program
drives a host control bit on P7 and branches on its synchronized value. This
lets a target hold SDA low across an ACK while stretching SCL. The target sees
only SCL and SDA. This example uses one controller with a 20 MHz project clock.

For example, write register index 0x5A to target 0x53 and read two bytes back
under a repeated START. From the repository root run

```sh
python -m tools.i2c --rate 400 --address 0x53 --write 5a --read 2 -o i2c.hex
```

1. With the engine stopped, send CLEAR and CONFIG_OD with mask `0x0C`. Load
   the hex words with BEGIN_LOAD and WRITE_WORD, then COMMIT_LOAD. The write
   image uses 46 words. Direct and combined reads use the same 64-word image.
   Use `--rate 100` for the slower timing.
2. Queue up to four of the printed bytes using WRITE_TX and issue START.
   This example produces `A6 80 5A C0 A7 00 00 80`. Only `A6 5A` and
   the repeated address `A7` are transmitted as data bytes on I2C. The
   remaining bytes tell the program when to continue, restart, ACK, or NACK.
3. Feed the remaining bytes whenever TX_READY is set. Service RX_VALID with
   READ_RX while waiting, especially for reads longer than four bytes. The
   engine holds SCL low while it waits for either FIFO. Check FAULT while
   servicing both queues because a target NACK can end the transfer early.
4. The program sends the last-byte NACK on reads and generates STOP
   automatically. Wait for RUNNING to clear and drain any remaining replies.
   A target NACK generates STOP and fault `0x81`. A pin WAIT that expires
   releases all outputs and reports `0x03`. Each WAIT permits 1,000 sampling
   clocks (50 us), including synchronization. Clear stale FIFO bytes and
   faults with CLEAR before starting a new transaction on an idle bus.

Omit `--read` for a write, omit `--write` for a direct read, and omit both
for an address-only write probe. After loading an image, software can change
the address, payload, and length on each transaction using
`tools.i2c.transaction`. The image selects the speed and whether the
transaction ends in a read. Host SPI bandwidth, FIFO waits and clock stretching
can reduce transaction throughput. Arbitration, target mode and 10-bit
addressing are outside this program's scope.

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
| programs/ | Timed pulse, UART TX/RX and SPI controller examples |
| verification/ | Assembler and cycle-model tests |
| macros/ | Portable custom-macro deliverables and interface contracts |
| scripts/ | Reproducible setup and checks |
| config/ | Committed version references; local settings are ignored |
| docs/ | Architecture, setup, handoffs and decisions |
| runs/, cadence-work/ | Ignored run output and authoritative local Cadence workspace |

Keep PDKs, credentials and proprietary assets out of Git. Follow the template's license for imported materials; choose and document a compatible license for original project work before public submission.
