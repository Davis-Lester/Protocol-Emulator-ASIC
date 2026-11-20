; Stream host WRITE_TX bytes as 115200-baud 8N1 on P1 at a 20 MHz clock.
; P1 remains driven high between bytes. Host STOP releases the pin.
    OUT     0x02, 0x02
    OE      0x02, 0x02
    DELAY   173
next_byte:
    GET_TX  0             ; Wait indefinitely for the next byte.
    LOOP    8
    OUT     0x02, 0x00    ; Start bit.
    DELAY   173
data_bit:
    TXBIT   P1, LSB
    DELAY   172
    DJNZ    data_bit
    OUT     0x02, 0x02    ; Stop bit, including the loop-back overhead.
    DELAY   170
    JMP     next_byte
