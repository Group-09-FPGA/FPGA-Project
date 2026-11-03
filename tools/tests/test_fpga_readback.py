import sys
import queue
import threading
import socket
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from book_inspector import BoardStorageMirror
from fpga_readback import (ReadbackAudit, SnapshotCollector, decode_hash_cell,
                           decode_slot, event_queries, parse_response, query, WIDTHS)
from order_book_dashboard import DashboardState, serial_worker, socket_listener


class ReadbackTest(unittest.TestCase):
    def test_relay_excludes_snapshot_traffic_for_sleeping_sender(self):
        class FakePort:
            def __init__(self):
                self.lines = queue.Queue()
            def readline(self):
                try:
                    return self.lines.get(timeout=0.01)
                except queue.Empty:
                    return b""

        with tempfile.TemporaryDirectory() as directory:
            path = directory + "/relay.sock"
            listener = socket_listener(path)
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.settimeout(3)
            client.connect(path)
            port, updates, stop = FakePort(), queue.Queue(), threading.Event()
            thread = threading.Thread(target=serial_worker,
                                      args=(port, listener, updates, stop), daemon=True)
            thread.start()
            try:
                # A sender waits between orders without draining its socket.
                # Thousands of snapshot replies must remain dashboard-only.
                for _ in range(1000):
                    port.lines.put(b"@H0000=" + b"0" * 152 + b"\r\n")
                confirmation = b"[BBO] B:00000000 | A:00000000 | V:1 | E:00\n"
                port.lines.put(confirmation)
                self.assertEqual(client.recv(4096), confirmation)
            finally:
                stop.set()
                thread.join(timeout=1)
                client.close()
                listener.close()

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
        self.assertEqual(parse_response(b"@B0000=00000020\r\n"), ("B", 0, 32))
        self.assertEqual(parse_response(("@E0000=" + "0" * 99 + "\r\n").encode()),
                         ("E", 0, 0))
        self.assertIsNone(parse_response(("@E0000=" + "0" * 87 + "\r\n").encode()))

    def test_cold_snapshot_rebuilds_live_book_without_prior_events(self):
        ref, slot = 0x1001, 2047
        hash_word = (1 << 75) | (slot << 64) | ref
        slot_word = (1 << 46) | (5 << 32) | 10
        quote_word = ((1 << 174) | (1 << 173) | (905000 << 141) |
                      (10 << 109) | (1 << 32) | 1)
        trace_word = ((1 << 315) | (1 << 311) | (ref << 247) |
                      (1 << 182) | (slot << 171) | (slot_word << 124))
        event_word = (1 << 362) | (((10 << 13) | 5) << 316) | trace_word
        board = {("B", 0): 1 << 5, ("H", 5): hash_word,
                 ("S", slot): slot_word, ("P", 5): 10, ("L", 5): 1,
                 ("Q", 0): quote_word, ("E", 0): event_word}
        board.update({("F", address): address for address in range(2039, 2047)})
        collector = SnapshotCollector()
        collector.start(1, 1)
        while not collector.complete:
            pair = collector.next_query()
            self.assertIsNotNone(pair)
            kind, addr = pair
            word = board.get(pair, 0)
            response = f"@{kind}{addr:04X}={word:0{WIDTHS[kind]}X}\r\n"
            self.assertTrue(collector.accept(response, 1))
        mirror = BoardStorageMirror()
        frame = {"D": 1, "active": 1, "base": 900000, "tick": 1000,
                 "bid": 905000, "ask": 0, "bid_qty": 10, "ask_qty": 0}
        with self.assertRaisesRegex(ValueError, "BASE or TICK"):
            mirror.load_snapshot(collector.values, {**frame, "base": None},
                                 decode_hash_cell, decode_slot)
        mirror.load_snapshot(collector.values, frame, decode_hash_cell, decode_slot)
        self.assertTrue(mirror.snapshot_ready)
        self.assertTrue(mirror.last_match)
        self.assertEqual(mirror.orders[ref].slot, slot)
        self.assertEqual(mirror.price_levels(), {("B", 905000): (10, 1)})
        self.assertEqual(mirror.free_top[-1], 2046)
        self.assertEqual(mirror.events[0]["shares"], 10)
        self.assertEqual(mirror.events[0]["price"], 905000)
        state = DashboardState()
        state.frame = {**frame, "valid": True, "error": 0}
        state.load_quotes(collector.values, 1)
        self.assertEqual([(point.event, point.bid, point.ask) for point in state.points],
                         [(1, 905000, 0)])

    def test_cancel_journal_preserves_requested_shares_after_cold_attach(self):
        old_slot_word = (5 << 32) | 3  # The slot holds remaining shares, not canceled shares.
        trace = ((1 << 315) | (3 << 311) | (123 << 247) |
                 (1 << 182) | (2047 << 171) | (old_slot_word << 124))
        meta = 7 << 13
        event = (1 << 362) | (meta << 316) | trace
        mirror = BoardStorageMirror()
        frame = {"D": 1, "active": 0, "base": 900000, "tick": 1000,
                 "bid": 0, "ask": 0, "bid_qty": 0, "ask_qty": 0}
        mirror.load_snapshot({("E", 0): event}, frame, decode_hash_cell, decode_slot)
        self.assertEqual(mirror.events[0]["kind"], "CANCEL")
        self.assertEqual(mirror.events[0]["shares"], 7)

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
