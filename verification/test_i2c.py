import unittest

from tools.i2c import program, transaction


class I2CHostTests(unittest.TestCase):
    def test_probe_and_multibyte_write(self):
        self.assertEqual(transaction(0x12), bytes.fromhex("24 00"))
        self.assertEqual(transaction(0x7f, b"\x00\xff"),
                         bytes.fromhex("fe 80 00 80 ff 00"))

    def test_direct_and_combined_read(self):
        self.assertEqual(transaction(0, read_count=3), bytes.fromhex("01 00 00 00 80"))
        self.assertEqual(transaction(0x53, b"\x5a", 2),
                         bytes.fromhex("a6 80 5a c0 a7 00 00 80"))

    def test_invalid_host_inputs(self):
        for address, count in ((-1, 0), (128, 0), (0x12, -1)):
            with self.subTest(address=address, count=count), self.assertRaises(ValueError):
                transaction(address, read_count=count)
        with self.assertRaises(ValueError):
            program(200, False)
