; Send 0x96 on P1 at nominal 115200 baud, 8N1, with a 20 MHz clock.
; Each bit lasts 174 clocks. Use an external pull-up to keep idle high after HALT.
    OUT     0x02, 0x02
    OE      0x02, 0x02
    LOAD_TX 0x96
    LOOP    8
    DELAY   171           ; Complete one driven idle bit before the start edge.
    OUT     0x02, 0x00    ; Start bit.
    DELAY   173
data_bit:
    TXBIT   P1, LSB
    DELAY   172           ; DJNZ and the following pin write take one clock each.
    DJNZ    data_bit
    OUT     0x02, 0x02    ; Stop bit.
    DELAY   173
    HALT
