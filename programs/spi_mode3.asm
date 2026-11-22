; SPI mode 3 (CPOL=1, CPHA=1). One full-duplex MSB-first byte per CS assertion.
; At 20 MHz the clock runs at 1 MHz. P0=CS_N, P1=MOSI, P2=MISO, P3=SCK.
    OUT     0x0b, 0x09    ; Set CS high and clock idle before enabling the pins.
    OE      0x0b, 0x0b
next_byte:
    GET_TX  0
    LOOP    8
    DELAY   9
    OUT     0x01, 0x00
    DELAY   9
bit_loop:
    OUT     0x08, 0x00    ; Leading edge launches data.
    TXBIT   P1, MSB
    DELAY   8
    OUT     0x08, 0x08    ; Trailing edge samples data.
    DELAY   1
    RXBIT   P2, MSB       ; Read the synchronized sample from the trailing edge.
    DELAY   6
    DJNZ    bit_loop
    OUT     0x01, 0x01    ; End the frame before waiting for RX FIFO space.
    PUT_RX  0
    JMP     next_byte
