# Software tools

## Assembler

Use Python 3.10+ from the repository root; no dependencies need installation:

```text
python -m tools.assembler programs/pulse.asm -o runs/pulse.hex
python -m tools.assembler programs/pulse.asm -o runs/pulse.bin --format bin
```

Source uses the mnemonics and operand order in `docs/ARCHITECTURE.md`.
Separate operands with commas. Decimal, `0x` hexadecimal and `0b` binary integers
are accepted. Pin operands may be `P0` through `P7`; shift direction may be `LSB`
or `MSB` (equivalent to 0 or 1). Mnemonics/labels are case-insensitive. `#` or `;`
starts a comment. Forward/backward branch labels are supported. There are no
expressions, macros or executable source directives.

```text
again:
    OUT 0x01, 0x01
    DELAY 19
    OUT 0x01, 0x00
    JMP again
```

The assembler enforces instruction ranges, nonzero DELAY/LOOP/TRAP operands,
the 64-word limit, and branch targets inside the loaded program. Output masks
do not restrict which value bits may be present; only masked bits take effect.
Errors include source line numbers and produce a nonzero exit code.

Hex images contain one exactly six-digit word per line, in increasing word
address order. Binary images contain exactly three big-endian bytes per word,
with no header or padding. Both encode opcode[23:20] and operand[19:0] from the
version-one contract. Binary images are instruction data, not complete SPI
request frames. The model CLI reads hex, not binary images.

Assembler and model tests run via `python scripts/workflow.py test-model`.
The SPI wire-level host loader, FPGA/demo-board utilities, and protocol examples
remain future work. The Python model's atomic loading methods are not a physical
hardware loader.
