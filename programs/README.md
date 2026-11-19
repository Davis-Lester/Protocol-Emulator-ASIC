# Protocol programs

## First runnable program: pulse.asm

Run `python scripts/workflow.py demo` from the repository root. It creates
`runs/pulse.hex`, `runs/pulse.csv`, and `runs/pulse.vcd`. Generated artifacts
remain ignored by Git. Inspect the CSV as text or open the VCD in a waveform
viewer if one is installed.

| Event | Rising edge | Time at 20 MHz |
| --- | --- | --- |
| Set idle output value low, still released | 1 | 50 ns |
| Enable P0 low | 2 | 100 ns |
| Drive P0 high | 3 | 150 ns |
| Drive P0 low | 23 | 1150 ns |
| HALT and release all pins | 28 | 1400 ns |

The high pulse is 20 cycles, or 1000 ns at an assumed 20 MHz. `DELAY 19` occupies
19 edges; the following OUT adds one more cycle between the two output writes.
This program demonstrates the Python model only; the template RTL has not been
replaced. Actual chip frequencies and pulse widths have not been measured.

UART, SPI and I2C programs and independent protocol checkers are still to come.
