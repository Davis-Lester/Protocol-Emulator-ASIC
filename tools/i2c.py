"""Build 100/400 kHz I2C transactions for the 20 MHz pin engine."""

import argparse
from pathlib import Path

from tools.assembler import assemble, hex_text


TEMPLATE = Path(__file__).resolve().parents[1] / "programs/i2c.asm.in"


def program(rate_khz: int, reading: bool) -> list[int]:
    """Assemble the image for writes or for transfers ending in a read."""
    # With ideal wires WAIT observes released SCL three execution edges later.
    # TX spends six low clocks on SDA hold, plus DJNZ, TXBIT and the SCL write.
    # RX uses the low phase for DJNZ and samples SDA in the high phase.
    if rate_khz not in (100, 400):
        raise ValueError("rate must be 100 or 400 kHz")
    low, high = (104, 96) if rate_khz == 100 else (28, 22)
    fields = dict(low=low, high=high, bus_free=low,
                  tx_low=low - 9, tx_high=high - 4,
                  rx_low=low - 2, rx_high=high - 5)
    tail = TEMPLATE.with_name("i2c_receive.asm.in").read_text() if reading else "    LOOP 1\n    JMP stop"
    finish = tail.format(**fields)
    return assemble(TEMPLATE.read_text().format(finish=finish, **fields))


def transaction(address: int, write: bytes = b"", read_count: int = 0) -> bytes:
    """Return the TX FIFO stream for the selected program. Empty write probes."""
    if not 0 <= address <= 0x7f or read_count < 0:
        raise ValueError("expected a 7-bit address and nonnegative read length")
    stream = bytearray()
    if write or not read_count:
        for value in bytes([address << 1]) + bytes(write):
            stream.extend((value, 0x80))  # Continue writing.
        stream[-1] = 0xc0 if read_count else 0  # Repeated START or finish.
    if read_count:
        stream.extend(((address << 1) | 1, 0))
        stream.extend(bytes(read_count - 1))  # ACK intermediate bytes.
        stream.append(0x80)  # Release SDA for the last byte's NACK.
    return bytes(stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rate", type=int, choices=(100, 400), required=True)
    parser.add_argument("--address", type=lambda s: int(s, 0), required=True)
    parser.add_argument("--write", default="", help="hex data bytes")
    parser.add_argument("--read", type=int, default=0, help="number of bytes to receive")
    parser.add_argument("-o", type=Path, required=True, help="output instruction hex")
    args = parser.parse_args()
    try:
        data = transaction(args.address, bytes.fromhex(args.write), args.read)
        words = program(args.rate, args.read > 0)
    except ValueError as exc:
        parser.error(str(exc))
    args.o.write_text(hex_text(words), encoding="ascii")
    print(f"{len(words)} words; WRITE_TX bytes: {data.hex(' ')}")


if __name__ == "__main__":
    main()
