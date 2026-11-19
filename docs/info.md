## Implementation status

This project is at the architecture stage. The current `tt_um_example` RTL is
the imported combinational adder: `uo_out = ui_in + uio_in`, `uio_out = 0`,
`uio_oe = 0`. It does not implement the protocol pin names or host interface
listed in `info.yaml`. Those names document the planned engine. Do not use
them as a description of the current RTL or as evidence of working hardware.

## Planned operation

One reloadable pin engine will execute UART, SPI-controller or I2C-controller
programs, one protocol at a time, at an initial 20 MHz clock target. The initial
budget is 64 instructions of 24 bits, separate byte shifters and four-byte TX/RX
FIFOs. A separate SPI host interface will load programs, supply bytes and read
results. See [ARCHITECTURE.md](ARCHITECTURE.md) for instruction, pin, timing,
loading, reset and protocol-scope decisions. Capacity and speed are unverified.

The inherited module name and paired testbench remain unchanged until the
engine replaces the template. The planned engine module name is
`tt_um_davis_lester_protocol_emulator`; update info.yaml and all RTL/testbench
references together at that implementation step.

## How to test now

Run `python scripts/workflow.py check` for starter infrastructure validation.
On a supported simulation environment, use the imported `test/README.md` and
the official `test` and `gds` workflows. No protocol-engine tests exist yet.

## Planned external hardware

Use a host microcontroller or FPGA, the appropriate protocol peripheral and a
logic analyzer. I2C needs external SCL/SDA pull-ups and any required level
shifting. Optional pull-ups on SPI CS_N and UART TX preserve idle levels while
released. Select values for the actual board and bus loading.

The engine will use output-enable control to implement open-drain I2C. The
current template does not implement that behavior or any host command.
