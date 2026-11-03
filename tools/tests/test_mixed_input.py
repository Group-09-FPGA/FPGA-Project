"""Mixed input confirms FPGA events without assuming a host-owned book."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from order_journey import read_until


class MixedInputTests(unittest.TestCase):
    def frame(self, ref, valid=True):
        trace = (1 << 315) | (1 << 311) | (ref << 247)
        return (f'[BBO] B:000DCF28 | A:00000000 | V:{int(valid)} | E:{"00" if valid else "0A"}'
                f' | QB:00000064 | QA:00000000 | N:002 | M:00000005 | D:00000008 | T:{trace:079X}\n').encode()

    def test_waits_for_own_reference_after_board_event(self):
        lines = iter([self.frame(222), self.frame(123)])
        class Port:
            def readline(self):
                return next(lines)
        frame, ok = read_until(Port(), None, 1, {'M': 5, 'D': 8}, event_ref=123)
        self.assertTrue(ok)
        self.assertEqual((int(frame['storage_trace'], 16) >> 247) & ((1 << 64)-1), 123)

    def test_invalid_book_still_stops_mixed_mode(self):
        raw = self.frame(123, False)
        class Port:
            def readline(self):
                return raw
        _, ok = read_until(Port(), None, 1, event_ref=123)
        self.assertFalse(ok)


if __name__ == '__main__':
    unittest.main()
