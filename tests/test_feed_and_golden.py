"""
Unit tests for Market Data Feed Handlers and Python Golden Vector Verification
Supports both standard library `unittest` and `pytest`.
"""

import os
import sys
import json
import unittest

# Add tools and sim/golden paths
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
sys.path.insert(0, os.path.join(REPO_ROOT, "sim", "golden"))

import hardware_test_helper
import lob_golden_adapter
from lob_telemetry_visualizer import LOBVisualizer

class TestFeedAndGoldenModel(unittest.TestCase):

    def test_telemetry_invalidates_stale_quotes(self):
        view = LOBVisualizer(demo=True)
        self.assertTrue(view.process_line("[BBO] B:000DC2B0 | A:000DE2A0 | V:1 | E:00"))
        self.assertTrue(view.book_valid)
        self.assertTrue(view.process_line("[BBO] B:000DC2B0 | A:000DE2A0 | V:0 | E:0A"))
        self.assertFalse(view.book_valid)
        self.assertEqual(view.error_code, 0x0A)

    def test_moldudp64_packet_formatting(self):
        """Verify NASDAQ ITCH 5.0 Type 'A' Add Order message serialization inside MoldUDP64."""
        seq = 42
        oid = 987654321
        side = 'B'
        shares = 1000
        stock = "AAPL"
        price = 1502500  # $150.2500

        pkt = hardware_test_helper.create_moldudp64_add_order(
            seq_num=seq,
            order_ref=oid,
            side=side,
            shares=shares,
            stock=stock,
            price=price
        )

        # MoldUDP64 header: 10s (session) + 8B (seq) + 2B (count) = 20 bytes
        # ITCH message: 2B (len) + 1B (type) + 2B (locate) + 2B (tracking) + 6B (ts) + 8B (ref) + 1B (side) + 4B (shares) + 8B (stock) + 4B (price) = 38 bytes
        self.assertEqual(len(pkt), 58, f"Expected 58-byte MoldUDP64 frame, got {len(pkt)}")
        self.assertEqual(pkt[:10], b"SESSION001")
        self.assertEqual(pkt[20:22], (36).to_bytes(2, "big"))  # ITCH message length is 36 bytes
        self.assertEqual(chr(pkt[22]), 'A')                    # Msg Type 'A'
        self.assertEqual(pkt[46:54], stock.encode('ascii').ljust(8, b' '))

    def test_canonical_event_packing(self):
        """Verify bit packing into 256-bit canonical hardware events matches lob_defines.vh."""
        evt = lob_golden_adapter.pack_canonical_event(
            ver=1,
            op=1,      # ADD
            side=0,    # BUY
            oid=1001,
            noid=0,
            shares=500,
            pidx=120,
            oow=0,
            seq=1
        )

        self.assertIsInstance(evt, int)
        self.assertGreater(evt, 0)
        # Bit 255:252 -> version 1
        self.assertEqual((evt >> 252) & 0xF, 1)
        # Bit 251:248 -> opcode 1 (ADD)
        self.assertEqual((evt >> 248) & 0xF, 1)
        # Bit 247 -> side 0 (BUY)
        self.assertEqual((evt >> 247) & 0x1, 0)
        # Bit 239:176 -> order id 1001
        self.assertEqual((evt >> 176) & 0xFFFFFFFFFFFFFFFF, 1001)
        # Bit 111:80 -> shares 500
        self.assertEqual((evt >> 80) & 0xFFFFFFFF, 500)
        # Bit 79:67 -> price index 120
        self.assertEqual((evt >> 67) & 0x1FFF, 120)

    def test_golden_vectors_schema(self):
        """Verify golden_vectors.json contains valid 256-bit hex events and reasonable bounds."""
        vectors_path = os.path.join(REPO_ROOT, "sim", "golden", "golden_vectors.json")
        self.assertTrue(os.path.exists(vectors_path), "golden_vectors.json must exist")

        with open(vectors_path, "r") as f:
            vectors = json.load(f)

        self.assertEqual(len(vectors), 32, f"Expected 32 golden vectors, found {len(vectors)}")

        for step in vectors:
            self.assertIn("step_index", step)
            self.assertIn("op_name", step)
            self.assertIn("raw_hex", step)
            self.assertEqual(len(step["raw_hex"]), 64, "Raw event hex must be exactly 64 characters (256 bits)")
            int(step["raw_hex"], 16)  # Verify valid hexadecimal
            self.assertGreaterEqual(step["expected_active_orders"], 0)
            self.assertGreaterEqual(step["expected_best_bid_price"], 0)
            self.assertGreaterEqual(step["expected_best_ask_price"], 0)

if __name__ == "__main__":
    unittest.main()
