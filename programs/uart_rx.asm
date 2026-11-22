; 115200 baud 8N1 at 20 MHz, P2 idle high. One bit is 174 clocks.
    WAIT P2, 1, 0       ; Establish idle after START or recovery.
start_bit:
    WAIT P2, 0, 0
    DELAY 86
    BRPIN P2, 1, start_bit  ; Reject a short low pulse at mid-start.
    LOOP 8
    DELAY 172
data_bit:
    RXBIT P2, LSB
    DELAY 172
    DJNZ data_bit
    BRPIN P2, 1, valid_stop
    TRAP 0x80           ; Framing error. Discard incomplete byte.
valid_stop:
    PUT_RX 1            ; Report overrun if the FIFO is still full.
    JMP start_bit
