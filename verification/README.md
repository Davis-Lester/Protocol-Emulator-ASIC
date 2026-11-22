# Verification

## Software functional tests

Run from the repo root with Python 3.10+:

```text
python scripts/workflow.py test-model
```

This runs standard-library unittest discovery in verification/. It does not
collect the imported cocotb tests under test/, which require their own simulator.

- `test_assembler.py`: all 16 golden instruction encodings, labels, field/program
  bounds, malformed source and hex-image validation.
- `test_engine.py`: exact pulse/branch/delay cycles, maximum delay and loop count,
  input synchronization, timeout boundary success, FIFO ordering/backpressure,
  shift direction, open-drain behavior, illegal instructions, PC bounds,
  reset/deselection, load validity and stopped-only controls. Hand-encoded model
  programs are independent of the assembler field table.
- `test_cli.py`: real assembler/model processes, binary byte order, CSV/VCD edge
  times and nonzero failures for malformed source/images, faults and cycle limits.

The pulse RTL uses the pin driver and cycle comparison in [test/](../test/README.md).
Its first Questa run is recorded in [the handoff](../docs/HANDOFF.md).
Independent UART/SPI-controller/I2C program checks, physical CDC review and
engine synthesis remain open.
