import os
import queue
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import order_book_dashboard as dashboard
from order_journey import SocketLineReader, parse_frame


def frame(event, bid, ask, valid=1, error=0):
    return (f"[BBO] B:{bid:08X} | A:{ask:08X} | V:{valid} | E:{error:02X} "
            f"| QB:00000064 | QA:00000032 | N:002 "
            f"| R:{event:08X} | U:{event:08X} | M:{event:08X} "
            f"| I:{event:08X} | F:{event:08X} | D:{event:08X}\n").encode()


class FakePort:
    def __init__(self):
        self.lines = queue.Queue()

    def readline(self):
        try:
            return self.lines.get(timeout=0.05)
        except queue.Empty:
            return b""


class DashboardTests(unittest.TestCase):
    def test_repeated_telemetry_does_not_add_false_chart_points(self):
        state = dashboard.DashboardState()
        first = frame(1, 905000, 949000)
        state.ingest(first, when=1)
        state.ingest(first, when=2)
        state.ingest(frame(2, 907000, 948000), when=3)
        self.assertEqual([point.event for point in state.points], [1, 2])
        self.assertEqual(len(state.changes), 2)
        self.assertEqual(state.changes[0][2:4], ("ASK", "fell"))

    def test_invalid_book_keeps_last_good_chart_without_accepting_quote(self):
        state = dashboard.DashboardState()
        state.ingest(frame(1, 905000, 949000), when=1)
        state.ingest(frame(2, 999000, 999000, valid=0, error=10), when=2)
        self.assertTrue(state.invalid)
        self.assertEqual(state.last_good["bid"], 905000)
        self.assertEqual(len(state.points), 1)
        state.ingest(frame(0, 0, 0), when=3)
        self.assertFalse(state.invalid)
        self.assertEqual([point.event for point in state.points], [0])

    def test_uart_relay_gives_sender_a_complete_frame(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "uart.sock")
            listener = dashboard.socket_listener(path)
            port = FakePort()
            updates = queue.Queue()
            stop = threading.Event()
            worker = threading.Thread(target=dashboard.serial_worker,
                                      args=(port, listener, updates, stop), daemon=True)
            worker.start()
            try:
                sender = SocketLineReader(path)
                try:
                    expected = frame(3, 907000, 948000)
                    time.sleep(0.1)  # Allow the relay thread to accept the client.
                    port.lines.put(expected)
                    received = sender.readline()
                    self.assertEqual(received, expected)
                    self.assertEqual(parse_frame(received.decode())["D"], 3)
                    self.assertEqual(updates.get(timeout=1), expected)
                finally:
                    sender.close()
            finally:
                stop.set()
                worker.join(timeout=1)
                listener.close()


if __name__ == "__main__":
    unittest.main()
