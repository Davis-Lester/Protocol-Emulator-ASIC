"""Two-pass assembler for the 24-bit version-one protocol engine.

Run from the repo root: python -m tools.assembler programs/pulse.asm -o runs/pulse.hex
Only integer literals and branch labels are accepted; source is never evaluated.
"""

import argparse
from pathlib import Path
import re
import sys


class AssemblyError(ValueError):
    """Invalid assembly source or machine-code image."""


# Fields: (name, shift, width, minimum). Unlisted bits are always zero.
FORMS = {
    "HALT": (0x0, ()),
    "OUT": (0x1, (("mask", 8, 8, 0), ("value", 0, 8, 0))),
    "OE": (0x2, (("mask", 8, 8, 0), ("value", 0, 8, 0))),
    "DELAY": (0x3, (("count", 0, 16, 1),)),
    "WAIT": (0x4, (("pin", 17, 3, 0), ("level", 16, 1, 0), ("count", 0, 16, 0))),
    "JMP": (0x5, (("address", 0, 6, 0),)),
    "LOOP": (0x6, (("count", 0, 8, 1),)),
    "DJNZ": (0x7, (("address", 0, 6, 0),)),
    "GET_TX": (0x8, (("count", 0, 16, 0),)),
    "TXBIT": (0x9, (("pin", 0, 3, 0), ("direction", 3, 1, 0))),
    "RXBIT": (0xA, (("pin", 0, 3, 0), ("direction", 3, 1, 0))),
    "PUT_RX": (0xB, (("count", 0, 16, 0),)),
    "LOAD_TX": (0xC, (("value", 0, 8, 0),)),
    "BRPIN": (0xD, (("pin", 7, 3, 0), ("level", 6, 1, 0), ("address", 0, 6, 0))),
    "CLEAR_RX": (0xE, ()),
    "TRAP": (0xF, (("value", 0, 8, 1),)),
}
LABEL = re.compile(r"^([A-Za-z_][A-Za-z_0-9]*):")


def _integer(token, field, labels):
    token = token.upper()
    if field == "address" and token in labels:
        return labels[token]
    if field == "pin" and re.fullmatch(r"P[0-7]", token):
        return int(token[1])
    if field == "direction" and token in ("LSB", "MSB"):
        return int(token == "MSB")
    try:
        return int(token, 0)
    except ValueError as exc:
        raise AssemblyError(f"invalid {field} {token!r} (integer or valid branch label required)") from exc


def assemble(source):
    """Return 1-64 encoded words; labels and mnemonics are case-insensitive."""
    labels = {}
    instructions = []
    for line_number, raw in enumerate(source.splitlines(), 1):
        text = re.split(r"[#;]", raw, maxsplit=1)[0].strip()
        while match := LABEL.match(text):
            label = match[1].upper()
            if label in labels:
                raise AssemblyError(f"line {line_number}: duplicate label {label}")
            labels[label] = len(instructions)
            text = text[match.end():].strip()
        if text:
            parts = text.split(None, 1)
            args = [s.strip() for s in parts[1].split(",")] if len(parts) == 2 else []
            instructions.append((line_number, parts[0].upper(), args))
    if not 1 <= len(instructions) <= 64:
        raise AssemblyError("program must contain 1-64 instructions")
    words = []
    for line_number, mnemonic, args in instructions:
        try:
            if mnemonic not in FORMS:
                raise AssemblyError(f"unknown instruction {mnemonic!r}")
            opcode, fields = FORMS[mnemonic]
            if len(args) != len(fields):
                raise AssemblyError(f"{mnemonic} requires {len(fields)} comma-separated operands")
            word = opcode << 20
            for token, (name, shift, width, minimum) in zip(args, fields):
                value = _integer(token, name, labels)
                maximum = (1 << width) - 1
                if not minimum <= value <= maximum:
                    raise AssemblyError(f"{name} must be {minimum}..{maximum}, got {value}")
                if name == "address" and value >= len(instructions):
                    raise AssemblyError(f"branch target {value} is outside this program")
                word |= value << shift
            words.append(word)
        except AssemblyError as exc:
            raise AssemblyError(f"line {line_number}: {exc}") from exc
    return words


def hex_text(words):
    """One six-digit hexadecimal word per line, in increasing word address order."""
    return "".join(f"{word:06X}\n" for word in words)


def read_hex(path):
    words = []
    for line_number, raw in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        text = re.split(r"[#;]", raw, maxsplit=1)[0].strip()
        if not text:
            continue
        if not re.fullmatch(r"[0-9a-fA-F]{6}", text):
            raise AssemblyError(f"line {line_number}: expected one six-digit hex word")
        words.append(int(text, 16))
    if not 1 <= len(words) <= 64:
        raise AssemblyError("image must contain 1-64 words")
    return words


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument("--format", choices=("hex", "bin"), default="hex")
    args = parser.parse_args(argv)
    try:
        words = assemble(args.source.read_text(encoding="utf-8"))
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            if args.format == "bin":
                args.output.write_bytes(b"".join(word.to_bytes(3, "big") for word in words))
            else:
                args.output.write_text(hex_text(words), encoding="ascii")
        elif args.format == "bin":
            parser.error("--format bin requires --output")
        else:
            print(hex_text(words), end="")
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
