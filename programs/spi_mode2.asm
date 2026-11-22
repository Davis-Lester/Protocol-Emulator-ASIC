; SPI mode 2 (CPOL=1, CPHA=0). One full-duplex MSB-first byte per CS assertion.
; At 20 MHz the clock runs at 1 MHz. P0=CS_N, P1=MOSI, P2=MISO, P3=SCK.
    OUT     0x0b, 0x09    ; Set CS high and clock idle before enabling the pins.
    OE      0x0b, 0x0b
next_byte:
    GET_TX  0
    LOOP    8
    DELAY   9
    OUT     0x01, 0x00
    DELAY   1
bit_loop:
    TXBIT   P1, MSB       ; Set up the first bit before the leading edge.
    DELAY   7
    OUT     0x08, 0x00    ; Leading edge samples data.
    DELAY   1
    RXBIT   P2, MSB       ; Read the synchronized sample from the leading edge.
    DELAY   7
    OUT     0x08, 0x08    ; Trailing edge launches the next bit.
    DJNZ    bit_loop
    DELAY   8
    OUT     0x01, 0x01    ; End the frame before waiting for RX FIFO space.
    PUT_RX  0
    JMP     next_byte
