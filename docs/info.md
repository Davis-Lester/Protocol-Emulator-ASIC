## How it works

The pulse engine stores up to 64 instructions of 24 bits each. The host loads
them through a mode-0 SPI target on ui[2:0] and reads responses on uo[0].
OUT sets selected output values, OE sets the corresponding output enables,
DELAY occupies a specified number of clock cycles, and HALT releases all eight
bidirectional pins. STOP, reset and execution faults also release the pins.
The initial system clock target is 20 MHz. The UART TX example uses LOAD_TX, TXBIT, LOOP and DJNZ to send 0x96
on P1 at nominal 115200 baud (8N1). FIFO support is planned. See [the architecture](ARCHITECTURE.md) for command bytes and timing.

## How to test

With the chip selected, clock reset low then release it with host CS high.
Send BEGIN_LOAD with the image length, WRITE_WORD for each assembled word in
big-endian order, COMMIT_LOAD, then START. With the supplied pulse program,
P0 should rise on execution edge 3, fall on edge 23 and release on edge 28.
RUNNING is uo[1] and FAULT is uo[2]. The simulator test drives this sequence
and compares every output edge to the Python reference.

## External hardware

A host microcontroller or FPGA supplies SPI. A logic analyzer can observe P0,
RUNNING and the system clock. A pull-up or pull-down on P0 allows the released
level to be distinguished from a driven level with an appropriate test pattern.
