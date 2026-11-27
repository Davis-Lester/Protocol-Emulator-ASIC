; PS/2 keyboard to host. P2 = clock, P3 = data. Both pins are inputs.
; WAIT counts of 4000 allow 200 us per in-frame transition at 20 MHz.
frame:
    WAIT P2,1,4000
    WAIT P2,0,0           ; Keyboard can stay idle indefinitely.
    BRPIN P3,1,bad_frame
    LOOP 8
even_ones:
    WAIT P2,1,4000
    WAIT P2,0,4000
    RXBIT P3,LSB
    BRPIN P3,1,count_odd
count_even:
    DJNZ even_ones
    WAIT P2,1,4000
    WAIT P2,0,4000
    BRPIN P3,1,stop_bit   ; Even data popcount requires a one parity bit.
    JMP bad_parity
odd_ones:
    WAIT P2,1,4000
    WAIT P2,0,4000
    RXBIT P3,LSB
    BRPIN P3,1,count_even
count_odd:
    DJNZ odd_ones
    WAIT P2,1,4000
    WAIT P2,0,4000
    BRPIN P3,1,bad_parity
stop_bit:
    WAIT P2,1,4000
    WAIT P2,0,4000
    BRPIN P3,0,bad_frame
    PUT_RX 1
    JMP frame
bad_frame:
    TRAP 0x81
bad_parity:
    TRAP 0x82
