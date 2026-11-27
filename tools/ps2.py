"""Build the keyboard Echo image using the same receiver as the scan-code image."""

from pathlib import Path

from tools.assembler import assemble, hex_text


def echo_program():
    programs = Path(__file__).resolve().parents[1] / "programs"
    prefix = (programs / "ps2_echo.asm.in").read_text()
    receiver = (programs / "ps2_rx.asm").read_text()
    return assemble(prefix + "\n" + receiver)


if __name__ == "__main__":
    print(hex_text(echo_program()), end="")
