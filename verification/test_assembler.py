"""Golden instruction words are transcribed from the architecture bit fields."""

from pathlib import Path
import tempfile
import unittest

from tools.assembler import AssemblyError, assemble, hex_text, read_hex


class AssemblerTests(unittest.TestCase):
    def test_all_sixteen_encodings_against_golden_words(self):
        source = """
            HALT
            OUT 0x12, 0x34
            OE 0xff, 0x80
            DELAY 65535
            WAIT P7, 1, 65535
            JMP last
            LOOP 255
            DJNZ 2
            GET_TX 0
            TXBIT P5, MSB
            RXBIT P2, LSB
            PUT_RX 65535
            LOAD_TX 0xa5
            BRPIN P7, 1, last
            CLEAR_RX
        last: TRAP 0xa5
        """
        self.assertEqual(assemble(source), [
            0x000000, 0x101234, 0x20FF80, 0x30FFFF,
            0x4FFFFF, 0x50000F, 0x6000FF, 0x700002,
            0x800000, 0x90000D, 0xA00002, 0xB0FFFF,
            0xC000A5, 0xD003CF, 0xE00000, 0xF000A5,
        ])

    def test_labels_comments_case_and_aliases(self):
        self.assertEqual(assemble("# comment\na: alias: out 0b1, 0\n jmp A ; again"),
                         [0x100100, 0x500000])

    def test_pulse_image_is_golden(self):
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(assemble((root / "programs/pulse.asm").read_text()),
                         [0x100100, 0x200101, 0x100101, 0x300013,
                          0x100100, 0x300004, 0x000000])

    def test_program_capacity(self):
        self.assertEqual(len(assemble("HALT\n" * 64)), 64)
        for text in ("", "; empty", "HALT\n" * 65):
            with self.subTest(text=text[:20]), self.assertRaises(AssemblyError):
                assemble(text)

    def test_rejects_invalid_source_with_line_number(self):
        bad_sources = (
            "NO_SUCH_INSTRUCTION", "OUT 1", "HALT 1", "OUT 1,,2", "OUT 256,0",
            "OUT -1,0", "DELAY 0", "DELAY 65536", "LOOP 0", "LOOP 256",
            "WAIT P8,1,0", "WAIT P0,2,0", "WAIT P0,1,-1", "TXBIT P0,2",
            "TRAP 0", "JMP missing", "JMP 63", "JMP end\nend:",
            "a: HALT\na: HALT", "OUT __import__('os'), 0",
        )
        for source in bad_sources:
            with self.subTest(source=source), self.assertRaisesRegex(AssemblyError, "line"):
                assemble(source)

    def test_address_63_is_valid_in_full_image(self):
        self.assertEqual(assemble("JMP final\n" + "HALT\n" * 62 + "final: HALT")[0], 0x50003F)

    def test_hex_read_write_and_reject_malformed_images(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "program.hex"
            path.write_text(hex_text([0x100101, 0x000000]))
            self.assertEqual(read_hex(path), [0x100101, 0])
            for text in ("", "1", "0x100101", "100101 000000", "GGGGGG", "000000\n" * 65):
                path.write_text(text)
                with self.subTest(text=text[:30]), self.assertRaises(AssemblyError):
                    read_hex(path)


if __name__ == "__main__":
    unittest.main()
