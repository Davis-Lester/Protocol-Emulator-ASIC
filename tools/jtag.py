"""Generate FIFO bytes for a four-wire JTAG controller on the protocol engine."""

import argparse


def reset_to_idle() -> bytes:
    """Force Test-Logic-Reset from any TAP state and enter Run-Test/Idle."""
    return bytes((1, 1, 1, 1, 1, 0))


def _entry(register):
    if register == "ir":
        return bytes((1, 1, 0, 0))
    if register == "dr":
        return bytes((1, 0, 0))
    raise ValueError("register must be ir or dr")


def scan(register: str, width: int, value: int = 0) -> bytes:
    """From idle, capture, shift width bits LSB first, update and return to idle."""
    if width < 1 or value < 0 or value.bit_length() > width:
        raise ValueError("scan requires a positive width and an unsigned value that fits")
    cycles = bytearray(_entry(register))
    for bit in range(width):
        tdi = (value >> bit) & 1
        cycles.append((tdi << 1) | (bit == width - 1))
    cycles.extend((1, 0))
    return bytes(cycles)


def decode_scan(register: str, width: int, replies: bytes) -> int:
    """Decode the replies to one complete scan, excluding navigation cycles."""
    start = len(_entry(register))
    if width < 1 or len(replies) != start + width + 2:
        raise ValueError("reply length must match one complete scan")
    bits = replies[start:start + width]
    if any(bit > 1 for bit in bits):
        raise ValueError("shift replies must be zero or one")
    return sum(bit << i for i, bit in enumerate(bits))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("reset", "ir", "dr"))
    parser.add_argument("width", type=int, nargs="?")
    parser.add_argument("value", type=lambda s: int(s, 0), nargs="?")
    args = parser.parse_args()
    if args.operation == "reset":
        if args.width is not None:
            parser.error("reset takes no operands")
        data = reset_to_idle()
    else:
        if args.width is None:
            parser.error("supply the target register width in bits")
        try:
            data = scan(args.operation, args.width, args.value or 0)
        except ValueError as exc:
            parser.error(str(exc))
    print(data.hex(" "))


if __name__ == "__main__":
    main()
