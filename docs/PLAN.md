# Milestones and acceptance criteria

1. Environment: import official template; record versions; pass its unchanged simulation and official GDS/precheck. No pass yet.
2. Custom integration experiment: tiny CMOS5L macro through the required flow, with clean applicable DRC/LVS and valid timing/power views. No macro yet.
3. Architecture: freeze pin mapping, instruction semantics, loading format, cycle timing, reset behavior and memory budget. No architecture frozen.
4. RTL baseline: deterministic programmable engine plus reference model, assembler and reloadable programs. Demonstrate UART, SPI and I2C with independent protocol checking.
5. Physical baseline: synthesize early, measure area, complete place-and-route and timing, run gate-level checks and precheck.
6. Custom datapath: replace a verified RTL block with a repeated custom layout macro; compare behavior and post-layout timing. Keep working baseline available.
7. Submission: review current rules/deadline, public licensing, architecture/ISA documentation, runnable examples, verification results and AI-use write-up.

Verification must cover reset and output safety, program loading, branch/delay cycle counts, counter edges, asynchronous input synchronization, waits/timeouts, output-enable behavior and I2C open-drain behavior. Test actual supported SPI modes and UART framing. Specify whether clock stretching, arbitration and target roles are supported; do not imply unsupported capabilities.

USB and Ethernet remain stretch goals. Choose instruction width, memory depth, engine count and clock target only after area estimates and protocol timing analysis.
