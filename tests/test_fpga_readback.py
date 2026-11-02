import sys
import queue
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from book_inspector import BoardStorageMirror
from fpga_readback import (ReadbackAudit, decode_hash_cell, event_queries,
                           parse_response, query)
from order_book_dashboard import serial_worker


class ReadbackTest(unittest.TestCase):
    def test_dashboard_worker_queries_uart(self):
        class FakePort:
            def __init__(self):
                self.lines = queue.Queue()
                self.writes = []

            def readline(self):
                try:
                    return self.lines.get(timeout=0.01)
                except queue.Empty:
                    return b""

            def write(self, data):
                self.writes.append(data)
                self.lines.put(b"@S07FF=000000000000\r\n")

        port = FakePort()
        updates, requests, stop = queue.Queue(), queue.Queue(), threading.Event()
        requests.put(("S", 2047))
        thread = threading.Thread(target=serial_worker,
                                  args=(port, None, updates, stop, None, requests), daemon=True)
        thread.start()
        try:
            self.assertEqual(updates.get(timeout=1)[0], "readback")
            self.assertEqual(port.writes, [b"?S07FF\n"])
        finally:
            stop.set()
            thread.join(timeout=1)

    def test_command_and_fixed_width_response(self):
        self.assertEqual(query("S", 2047), b"?S07FF\n")
        self.assertEqual(parse_response(b"@S07FF=400000000001\r\n"),
                         ("S", 2047, 0x400000000001))
        self.assertIsNone(parse_response(b"@S07FF=1\r\n"))
        with self.assertRaises(ValueError):
            query("S", 0x4000)

    def test_touched_reads_and_actual_comparison(self):
        mirror = BoardStorageMirror()
        frame = {"D": 1, "base": 900000, "tick": 1000,
                 "bid": 905000, "ask": 0, "bid_qty": 10,
                 "ask_qty": 0, "active": 1, "valid": True,
                 "storage_trace": None}
        # A real FPGA trace controls the mirrored slot and hash positions.
        trace = ((1 << 315) | (1 << 311) | (123 << 247) |
                 (1 << 182) | (2047 << 171) |
                 (((1 << 46) | (5 << 32) | 10) << 124) |
                 (1 << 108) | (123 << 47) |
                 (1 << 93) | (5 << 79) | (10 << 47))
        frame["storage_trace"] = f"{trace:079X}"
        self.assertTrue(mirror.apply_trace(frame["storage_trace"], frame))
        pairs = event_queries(frame)
        self.assertIn(("S", 2047), pairs)
        self.assertIn(("Q", 0), pairs)
        self.assertIn(("E", 0), pairs)
        audit = ReadbackAudit()
        hash_value = audit.expected("H", mirror.orders[123].set_index, mirror, frame)
        self.assertEqual(decode_hash_cell(hash_value & ((1 << 76) - 1)),
                         {"slot": 2047, "ref": 123})
        expected = audit.expected("S", 2047, mirror, frame)
        audit.ingest(f"@S07FF={expected:012X}\r\n", mirror, frame, 1)
        self.assertIn(("S", 2047), audit.verified)
        audit.ingest("@S07FF=000000000000\r\n", mirror, frame, 1)
        self.assertTrue(audit.mismatches)
        # A retired slot can retain its price index after valid clears.
        mirror.orders.clear()
        mirror.slot_words[2047] = 5 << 32
        self.assertEqual(audit.expected("S", 2047, mirror, frame), 5 << 32)


if __name__ == "__main__":
    unittest.main()
