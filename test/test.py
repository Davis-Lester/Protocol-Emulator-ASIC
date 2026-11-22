from pathlib import Path

import cocotb
from cocotb.triggers import RisingEdge, with_timeout

from pulse_reference import compare, prepare


@cocotb.test()
async def test_engine_pins(dut):
    build = Path("sim_build")
    expected = prepare(build)
    dut.start_tests.value = 1
    await with_timeout(RisingEdge(dut.tests_done), 30, "ms")
    compare(build, expected)
