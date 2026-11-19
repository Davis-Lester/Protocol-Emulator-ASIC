; One 20-cycle pulse on P0. At 20 MHz this is exactly 1 us in the model.
; Set idle value before enabling output, then include OUT's own cycle in width.
start:
    OUT   0x01, 0x00
    OE    0x01, 0x01
    OUT   0x01, 0x01     ; rising edge at cycle 3
    DELAY 19             ; 19 delay cycles + the next OUT = 20 cycles high
    OUT   0x01, 0x00     ; falling edge at cycle 23
    DELAY 4
    HALT                 ; release P0 at cycle 28
