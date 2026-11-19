# Milestones and acceptance criteria

1. Environment: adder GDS, DRC/LVS, precheck and gate-level test reviewed at c9e002c. Separate RTL test record still needed.
2. Custom integration experiment: tiny CMOS5L macro through the required flow, with clean applicable DRC/LVS and valid timing/power views. No macro yet.
3. Architecture: initial pin mapping, instruction semantics, loading format, cycle timing, reset behavior and memory budget are selected in docs/ARCHITECTURE.md. Use this contract for the model/assembler and RTL. Memory capacity and clock target remain subject to early area/timing measurements; no fit or closure is claimed.
4. RTL baseline: SPI loading, OUT, OE, DELAY and HALT passed the Questa pin-level test and cycle-model comparison. The fixed-byte 115200-baud UART TX example passed an independent RTL pin check. Extend to FIFO-fed TX, UART RX, SPI and I2C.
5. Physical baseline: synthesize early, measure area, complete place-and-route and timing, run gate-level checks and precheck.
6. Custom datapath: replace a verified RTL block with a repeated custom layout macro; compare behavior and post-layout timing. Keep working baseline available.
7. Submission: review current rules/deadline, public licensing, architecture/ISA documentation, runnable examples, verification results and AI-use write-up.

Verification must cover reset and output safety, program loading, branch/delay cycle counts, counter edges, asynchronous input synchronization, waits/timeouts, output-enable behavior and I2C open-drain behavior. Test actual supported SPI modes and UART framing. Specify whether clock stretching, arbitration and target roles are supported; do not imply unsupported capabilities.

USB and Ethernet remain stretch goals. Initial choices are one engine, 24-bit instructions, 64 words and 20 MHz. Confirm or revise them after synthesis area estimates and protocol timing analysis, before treating capacity or speed as guaranteed.
