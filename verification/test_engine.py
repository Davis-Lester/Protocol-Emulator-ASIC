"""Behavioral checks use hand-encoded programs, independent of the assembler."""

import unittest

from model.engine import Engine, Fault, HostError


def started(words):
    engine = Engine()
    engine.load_program(words)
    engine.start()
    return engine


class EngineTests(unittest.TestCase):
    def test_pulse_exact_edges_and_release(self):
        engine = started([0x100100, 0x200101, 0x100101, 0x300013,
                          0x100100, 0x300004, 0])
        trace = engine.run(100)
        self.assertEqual(len(trace), 28)
        self.assertEqual([row.cycle for row in trace if row.uio_out & row.uio_oe & 1],
                         list(range(3, 23)))
        self.assertEqual([row.cycle for row in trace if row.uio_oe & 1], list(range(2, 28)))
        self.assertEqual((trace[-1].running, trace[-1].uio_out, trace[-1].uio_oe, engine.fault),
                         (False, 0, 0, Fault.NONE))
        self.assertEqual([row.cycle for row in trace if row.retired], [1, 2, 3, 22, 23, 27, 28])

    def test_delay_one_and_maximum(self):
        for count in (1, 65535):
            with self.subTest(count=count):
                engine = started([0x300000 | count, 0])
                for _ in range(count - 1):
                    self.assertFalse(engine.tick().retired)
                    self.assertEqual(engine.pc, 0)
                self.assertTrue(engine.tick().retired)
                self.assertEqual(engine.pc, 1)
                self.assertFalse(engine.tick().running)
                self.assertEqual(engine.cycle, count + 1)

    def test_adjacent_output_writes_take_one_cycle_each(self):
        trace = started([0x100101, 0x100100, 0]).run()
        self.assertEqual([(r.cycle, r.uio_out) for r in trace], [(1, 1), (2, 0), (3, 0)])

    def test_masks_preserve_unselected_bits(self):
        engine = started([0x10FFAA, 0x100F05, 0x20FFF0, 0x200303, 0])
        trace = engine.run()
        self.assertEqual(trace[1].uio_out, 0xA5)
        self.assertEqual(trace[3].uio_oe, 0xF3)

    def test_loop_and_branch_have_no_delay_slot(self):
        engine = started([0x600003, 0x700001, 0])
        trace = engine.run()
        self.assertEqual([r.pc_before for r in trace], [0, 1, 1, 1, 2])
        self.assertEqual([r.loop_count for r in trace], [3, 2, 1, 0, 0])
        engine = started([0x500002, 0xF00001, 0])
        self.assertEqual([r.pc_before for r in engine.run()], [0, 2])
        self.assertEqual(engine.fault, Fault.NONE)

    def test_loop_count_maximum(self):
        engine = started([0x6000FF, 0x700001, 0])
        engine.run(300)
        self.assertEqual((engine.cycle, engine.loop_count, engine.fault), (257, 0, Fault.NONE))

    def test_conditional_branch_and_untaken_out_of_range_target(self):
        # Pin 0 initially synchronized low: first branch skips a trap.
        engine = started([0xD00002, 0xF00001, 0])
        self.assertEqual([r.pc_before for r in engine.run()], [0, 2])
        # Expected high, target 63: untaken branch is legal in a two-word program.
        engine = started([0xD0007F, 0])
        engine.run()
        self.assertEqual(engine.fault, Fault.NONE)

    def test_input_synchronizer_and_wait_last_edge_success(self):
        engine = started([0x410003, 0])  # WAIT P0,1,3
        trace = [engine.tick(pins=1) for _ in range(3)]
        self.assertEqual([r.sampled_pins for r in trace], [0, 0, 1])
        self.assertEqual([r.retired for r in trace], [False, False, True])
        self.assertEqual(engine.fault, Fault.NONE)
        engine.tick(pins=1)
        self.assertFalse(engine.running)

    def test_wait_timeout_and_immediate_success(self):
        engine = started([0x410002, 0])  # high cannot synchronize before third edge
        engine.tick(pins=1)
        engine.tick(pins=1)
        self.assertEqual((engine.fault, engine.cycle), (Fault.WAIT_TIMEOUT, 2))
        engine = started([0x400001, 0])  # WAIT P0,0,1 succeeds immediately
        self.assertTrue(engine.tick().retired)

    def test_unbounded_wait_can_be_aborted(self):
        engine = started([0x20FF01, 0x410000, 0])
        engine.run(20)
        self.assertTrue(engine.running)
        self.assertEqual(engine.uio_oe, 1)
        row = engine.tick(stop=True)
        self.assertEqual((row.running, row.uio_oe, row.fault, row.word), (False, 0, 0, None))

    def test_get_tx_success_on_last_permitted_edge(self):
        engine = started([0x800003, 0])
        engine.tick()
        engine.tick()
        row = engine.tick(tx_write=0xA5)
        self.assertTrue(row.retired)
        self.assertEqual((row.tx_shift, row.tx_count, row.fault), (0xA5, 0, 0))

    def test_get_tx_timeout(self):
        engine = started([0x800001, 0])
        self.assertEqual(engine.tick().fault, Fault.TX_TIMEOUT)

    def test_tx_fifo_full_rejection_precedes_engine_pop(self):
        engine = started([0x800001, 0])
        for value in range(4):
            engine.write_tx(value)
        row = engine.tick(tx_write=99)
        self.assertIn("full", row.host_error)
        self.assertEqual((row.tx_shift, list(engine.tx_fifo)), (0, [1, 2, 3]))

    def test_rx_fifo_empty_rejection_precedes_engine_push(self):
        engine = started([0xB00001, 0])
        row = engine.tick(rx_read=True)
        self.assertIn("empty", row.host_error)
        self.assertIsNone(row.host_rx)
        self.assertEqual(engine.read_rx(), 0)

    def test_rx_fifo_full_wait_freed_on_last_permitted_edge(self):
        engine = started([0xB00003] * 5 + [0])
        for _ in range(6):  # four pushes, two failed checks on the fifth
            engine.tick()
        self.assertEqual(len(engine.rx_fifo), 4)
        row = engine.tick(rx_read=True)
        self.assertEqual((row.host_rx, row.rx_count, row.retired, row.fault), (0, 4, True, 0))

    def test_rx_fifo_timeout(self):
        engine = started([0xB00001] * 5 + [0])
        engine.run()
        self.assertEqual((engine.fault, engine.cycle), (Fault.RX_TIMEOUT, 5))

    def test_transmit_shift_orders_and_zero_fill(self):
        value = 0x96
        for msb in (False, True):
            with self.subTest(msb=msb):
                engine = started([0xC00096, 0x200202] + [0x900001 | (8 if msb else 0)] * 8 + [0])
                trace = engine.run()
                order = range(7, -1, -1) if msb else range(8)
                self.assertEqual([(r.uio_out >> 1) & 1 for r in trace[2:10]],
                                 [(value >> bit) & 1 for bit in order])
                self.assertEqual(trace[9].tx_shift, 0)
                self.assertEqual(trace[9].uio_oe, 2)

    def test_receive_shift_orders_and_clear(self):
        value = 0x96
        for msb in (False, True):
            with self.subTest(msb=msb):
                engine = started([0x300002] + [0xA00002 | (8 if msb else 0)] * 8
                                 + [0xB00001, 0xE00000, 0])
                order = range(7, -1, -1) if msb else range(8)
                # Pin samples applied at edges 1..8 reach execution at 3..10.
                for bit in order:
                    engine.tick(pins=((value >> bit) & 1) << 2)
                engine.run()
                self.assertEqual(engine.read_rx(), value)
                self.assertEqual(engine.rx_shift, 0)

    def test_open_drain_never_drives_high(self):
        engine = Engine()
        engine.load_program([0x20FFFF, 0x10FF0C, 0x100C00, 0])
        engine.configure_od(0x0C)
        engine.start()
        first, released, low, halted = engine.run()
        self.assertEqual(first.uio_oe & 0x0C, 0x0C)
        self.assertEqual((released.uio_out & 0x0C, released.uio_oe & 0x0C), (0, 0))
        self.assertEqual((low.uio_out & 0x0C, low.uio_oe & 0x0C), (0, 0x0C))
        self.assertEqual(halted.uio_oe, 0)

    def test_reserved_bits_and_zero_counts_fault(self):
        invalid = [0x000001, 0x110000, 0x210000, 0x310000, 0x300000,
                   0x500040, 0x600100, 0x600000, 0x700040, 0x810000,
                   0x900010, 0xA00010, 0xB10000, 0xC00100, 0xD00400,
                   0xE00001, 0xF00100, 0xF00000]
        for word in invalid:
            with self.subTest(word=f"{word:06X}"):
                engine = started([word])
                engine.tick()
                self.assertEqual(engine.fault, Fault.ILLEGAL_INSTRUCTION)
                self.assertEqual((engine.running, engine.uio_out, engine.uio_oe), (False, 0, 0))

    def test_fault_releases_pins_and_requires_clear(self):
        engine = started([0x10FF55, 0x20FFFF, 0xF000A5])
        engine.run()
        self.assertEqual((engine.fault, engine.trap_code, engine.uio_out, engine.uio_oe),
                         (Fault.PROGRAM_TRAP, 0xA5, 0, 0))
        engine.stop()
        with self.assertRaises(HostError):
            engine.start()
        engine.clear()
        self.assertTrue(engine.program_valid)
        self.assertEqual(engine.fault, Fault.NONE)
        engine.start()

    def test_loop_underflow_and_invalid_branch(self):
        for word, fault in ((0x700000, Fault.LOOP_UNDERFLOW),
                            (0x50003F, Fault.PC_RANGE), (0xD0003F, Fault.PC_RANGE)):
            with self.subTest(word=word):
                engine = started([word])
                engine.tick()
                self.assertEqual(engine.fault, fault)

    def test_fetch_past_program_end_never_wraps(self):
        for count in (1, 64):
            engine = started([0x100100] * count)
            engine.run(count + 1)
            self.assertEqual((engine.fault, engine.pc, engine.cycle),
                             (Fault.PC_RANGE, count, count + 1))

    def test_reset_invalidates_program_and_clears_all_control(self):
        engine = Engine()
        engine.load_program([0x20FFFF, 0x410000])
        engine.configure_od(0x0C)
        engine.write_tx(0x55)
        engine.start()
        engine.tick()
        stored = engine.memory.copy()
        engine.tick(reset=True, tx_write=99)
        self.assertEqual(engine.memory, stored)
        self.assertEqual((engine.running, engine.uio_oe, engine.od_mask, engine.program_valid,
                          engine.pc, len(engine.tx_fifo), engine.fault), (False, 0, 0, False, 0, 0, Fault.NONE))
        with self.assertRaises(HostError):
            engine.start()

    def test_deselection_requires_reset_and_reload(self):
        engine = started([0x20FFFF, 0x500000])
        engine.tick()
        engine.tick(ena=False)
        self.assertTrue(engine.needs_reset)
        self.assertEqual(engine.uio_oe, 0)
        engine.tick()
        with self.assertRaises(HostError):
            engine.load_program([0])
        engine.tick(reset=True)
        engine.load_program([0])
        engine.start()
        self.assertFalse(engine.tick().running)

    def test_load_requires_all_declared_words_and_rejects_overrun(self):
        engine = Engine()
        engine.begin_load(2)
        engine.write_word(0x100100)
        with self.assertRaises(HostError):
            engine.commit_load()
        with self.assertRaises(HostError):
            engine.start()
        engine.write_word(0)
        stored = engine.memory.copy()
        with self.assertRaises(HostError):
            engine.write_word(0xFFFFFF)
        self.assertEqual(engine.memory, stored)
        engine.commit_load()
        engine.start()
        engine.run()
        self.assertEqual(engine.fault, Fault.NONE)

    def test_load_and_config_rejected_while_running(self):
        engine = started([0x500000])
        stored = engine.memory.copy()
        for action in (lambda: engine.begin_load(1), lambda: engine.write_word(0),
                       engine.commit_load, lambda: engine.configure_od(255), engine.clear, engine.start):
            with self.subTest(action=action), self.assertRaises(HostError):
                action()
        self.assertEqual(engine.memory, stored)
        self.assertTrue(engine.running)

    def test_clear_preserves_program_and_od_but_empties_fifos(self):
        engine = Engine()
        engine.load_program([0xB00001, 0])
        engine.configure_od(0x0C)
        engine.write_tx(0x55)
        engine.start()
        engine.run()
        engine.clear()
        self.assertEqual((engine.program_valid, engine.od_mask, len(engine.tx_fifo), len(engine.rx_fifo)),
                         (True, 0x0C, 0, 0))

    def test_start_preserves_fifo_bytes(self):
        engine = Engine()
        engine.load_program([0x800001, 0])
        engine.write_tx(0xA5)
        engine.start()
        self.assertEqual(engine.tick().tx_shift, 0xA5)

    def test_host_api_rejects_out_of_range_inputs(self):
        engine = Engine()
        for count in (0, 65, -1, True):
            with self.assertRaises(HostError):
                engine.begin_load(count)
        engine.begin_load(1)
        for word in (-1, 1 << 24, True):
            with self.assertRaises(HostError):
                engine.write_word(word)
        for value in (-1, 256):
            with self.assertRaises(HostError):
                engine.write_tx(value)
            with self.assertRaises(HostError):
                engine.configure_od(value)
            with self.assertRaises(HostError):
                engine.tick(pins=value)
        with self.assertRaises(HostError):
            engine.read_rx()


if __name__ == "__main__":
    unittest.main()
