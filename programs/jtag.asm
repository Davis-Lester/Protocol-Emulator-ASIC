; One FIFO byte clocks one JTAG cycle. P0=TMS, P1=TDI, P2=TDO, P3=TCK.
    OUT 0x0b,0x01
    OE  0x0b,0x0b
cycle:
    GET_TX 0
    TXBIT P0,LSB
    TXBIT P1,LSB
    CLEAR_RX
    DELAY 5
    OUT 8,8
    DELAY 1
    RXBIT P2,MSB     ; Synchronizer returns TDO from the rising TCK edge in bit 0.
    DELAY 7
    OUT 8,0
    PUT_RX 0
    JMP cycle
