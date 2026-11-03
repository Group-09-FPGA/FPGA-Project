import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from book_inspector import BookMirror, BoardStorageMirror, TRACE_FIELDS, decode_storage_trace
from order_journey import hash_set, next_advanced_order


def event(order, seq):
    return {"kind": order.kind, "ref": order.ref, "side": order.side,
            "shares": order.shares, "price": order.price,
            "new_ref": order.new_ref, "seq": seq}


class BookInspectorTests(unittest.TestCase):
    def test_fpga_trace_drives_storage_and_matches_host_prediction(self):
        def encoded(**values):
            value = 0
            for name, width in TRACE_FIELDS:
                value = (value << width) | values.get(name, 0)
            return f"{value:079X}"

        board = BoardStorageMirror()
        host = BookMirror()
        add = {"kind": "A", "ref": 1000, "side": "B", "shares": 100,
               "price": 905000, "seq": 1}
        host.apply(add)
        slot = host.orders[1000].slot
        set_index = hash_set(1000)
        add_trace = encoded(valid=1, op=1, ref=1000, slot_valid=1,
                            slot_addr=slot, slot_data=(1 << 46) | (5 << 32) | 100,
                            ins_valid=1, ins_set=set_index, ins_idx=0,
                            price0_valid=1, price0_addr=5, price0_qty=100)
        self.assertEqual(decode_storage_trace(add_trace)["slot_addr"], slot)
        self.assertTrue(board.apply_trace(add_trace,
                        {"D": 1, "bid": 905000, "ask": 0, "bid_qty": 100,
                         "ask_qty": 0, "active": 1}))
        self.assertTrue(board.compare_prediction(host))
        self.assertEqual(board.price_levels(), {("B", 905000): (100, 1)})

        host.apply({"kind": "E", "ref": 1000, "shares": 40, "seq": 2})
        partial_trace = encoded(valid=1, op=2, ref=1000, slot_valid=1,
                                slot_addr=slot, slot_data=(1 << 46) | (5 << 32) | 60,
                                price0_valid=1, price0_addr=5, price0_qty=60)
        self.assertTrue(board.apply_trace(partial_trace,
                        {"D": 2, "bid": 905000, "ask": 0, "bid_qty": 60,
                         "ask_qty": 0, "active": 1}))
        self.assertTrue(board.compare_prediction(host))
        self.assertEqual(board.events[-1]["shares"], 40)

        host.apply({"kind": "D", "ref": 1000, "seq": 3})
        delete_trace = encoded(valid=1, op=4, ref=1000, slot_valid=1,
                               slot_addr=slot, slot_data=(5 << 32),
                               inv_valid=1, inv_set=set_index, inv_idx=0,
                               price0_valid=1, price0_addr=5, price0_qty=0)
        self.assertTrue(board.apply_trace(delete_trace,
                        {"D": 3, "bid": 0, "ask": 0, "bid_qty": 0,
                         "ask_qty": 0, "active": 0}))
        self.assertTrue(board.compare_prediction(host))
        self.assertEqual(board.price_levels(), {})

        self.assertFalse(board.apply_trace(delete_trace,
                         {"D": 5, "bid": 0, "ask": 0, "bid_qty": 0,
                          "ask_qty": 0, "active": 0}))
        self.assertIn("trace gap", board.warning)

    def test_advanced_journey_returns_to_empty_book_and_preserves_replace_slot(self):
        mirror = BookMirror()
        replaced_slot = None
        for index in range(13):
            if index == 8:
                replaced_slot = mirror.orders[1001].slot
            mirror.apply(event(next_advanced_order(index), index + 1))
            if index == 8:
                self.assertEqual(mirror.orders[1002].slot, replaced_slot)
        self.assertEqual(mirror.quote(), {"bid": 0, "ask": 0,
                                          "bid_qty": 0, "ask_qty": 0, "active": 0})
        self.assertEqual(len(mirror.free_slots), 2048)
        self.assertEqual(len(mirror.events), 13)

    def test_colliding_orders_fill_ways_then_stash(self):
        refs = [ref for ref in range(100000) if hash_set(ref) == 0][:9]
        self.assertEqual(len(refs), 9)
        mirror = BookMirror()
        for index, ref in enumerate(refs):
            mirror.apply({"kind": "A", "ref": ref, "side": "B", "shares": 10,
                          "price": 905000, "seq": index + 1})
        self.assertEqual([mirror.orders[ref].way for ref in refs[:8]], list(range(8)))
        self.assertIsNone(mirror.orders[refs[8]].way)
        self.assertEqual(mirror.orders[refs[8]].stash_index, 0)

    def test_board_mismatch_is_visible(self):
        mirror = BookMirror()
        mirror.apply({"kind": "A", "ref": 1000, "side": "B", "shares": 100,
                      "price": 905000, "seq": 1},
                     {"bid": 900000, "ask": 0, "bid_qty": 100,
                      "ask_qty": 0, "active": 1})
        self.assertFalse(mirror.last_match)
        self.assertIn("unreliable", mirror.warning)

    def test_price_level_remains_until_last_order_is_gone(self):
        mirror = BookMirror()
        mirror.apply({"kind": "A", "ref": 10, "side": "B", "shares": 100,
                      "price": 905000, "seq": 1})
        mirror.apply({"kind": "A", "ref": 11, "side": "B", "shares": 50,
                      "price": 905000, "seq": 2})
        mirror.apply({"kind": "A", "ref": 12, "side": "S", "shares": 20,
                      "price": 910000, "seq": 3})
        self.assertEqual(mirror.price_levels(), {("B", 905000): (150, 2),
                                                 ("S", 910000): (20, 1)})
        mirror.apply({"kind": "X", "ref": 10, "shares": 40, "seq": 4})
        self.assertEqual(mirror.price_levels()[("B", 905000)], (110, 2))
        mirror.apply({"kind": "E", "ref": 10, "shares": 60, "seq": 5})
        self.assertEqual(mirror.price_levels()[("B", 905000)], (50, 1))
        mirror.apply({"kind": "D", "ref": 11, "seq": 6})
        self.assertNotIn(("B", 905000), mirror.price_levels())
        self.assertEqual(mirror.price_levels(), {("S", 910000): (20, 1)})
        mirror.apply({"kind": "C", "ref": 12, "shares": 20, "seq": 7})
        self.assertEqual(mirror.price_levels(), {})


if __name__ == "__main__":
    unittest.main()
