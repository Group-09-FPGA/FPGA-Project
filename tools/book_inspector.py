"""Predicted and board-traced order storage for dashboard pages."""

from dataclasses import dataclass
from order_journey import hash_set


TRACE_FIELDS = (("valid", 1), ("op", 4), ("ref", 64), ("new_ref", 64),
                ("slot_valid", 1), ("slot_addr", 11), ("slot_data", 47),
                ("inv_valid", 1), ("inv_set", 10), ("inv_idx", 3), ("inv_stash", 1),
                ("ins_valid", 1), ("ins_set", 10), ("ins_idx", 3), ("ins_stash", 1),
                ("price0_valid", 1), ("price0_addr", 14), ("price0_qty", 32),
                ("price1_valid", 1), ("price1_addr", 14), ("price1_qty", 32))
assert sum(width for _, width in TRACE_FIELDS) == 316


def decode_storage_trace(raw):
    if len(raw) != 79:
        raise ValueError("storage trace must contain 79 hex digits")
    value = int(raw, 16)
    decoded = {}
    remaining = 316
    for name, width in TRACE_FIELDS:
        remaining -= width
        decoded[name] = (value >> remaining) & ((1 << width) - 1)
    return decoded if decoded["valid"] else None


@dataclass
class StoredOrder:
    ref: int
    side: str
    shares: int
    price: int
    slot: int
    set_index: int
    way: int | None
    stash_index: int | None


class BookMirror:
    def __init__(self):
        self.orders = {}
        self.free_slots = list(range(2048))
        self.ways = {}
        self.stash = [None] * 8
        self.events = []
        self.last_match = None
        self.warning = None

    def reset(self):
        self.__init__()

    def _location(self, set_index, reusable=None):
        ways = self.ways.setdefault(set_index, [None] * 8)
        if reusable and reusable.set_index == set_index:
            return reusable.way, reusable.stash_index
        for way, ref in enumerate(ways):
            if ref is None:
                return way, None
        for index, ref in enumerate(self.stash):
            if ref is None:
                return None, index
        raise ValueError(f"hash set {set_index} and collision stash are full")

    def _unlink(self, order, release_slot):
        if order.way is not None:
            self.ways[order.set_index][order.way] = None
        else:
            self.stash[order.stash_index] = None
        del self.orders[order.ref]
        if release_slot:
            self.free_slots.append(order.slot)

    def _insert(self, ref, side, shares, price, slot=None, reusable=None):
        if ref in self.orders:
            raise ValueError(f"duplicate order ID {ref}")
        allocated = slot is None
        if slot is None:
            if not self.free_slots:
                raise ValueError("no free slots")
            slot = self.free_slots[-1]
        set_index = hash_set(ref)
        way, stash_index = self._location(set_index, reusable)
        if allocated:
            self.free_slots.pop()
        order = StoredOrder(ref, side, shares, price, slot, set_index, way, stash_index)
        if way is not None:
            self.ways[set_index][way] = ref
        else:
            self.stash[stash_index] = ref
        self.orders[ref] = order

    def apply(self, event, board_frame=None):
        kind = event["kind"]
        ref = int(event["ref"])
        shares = int(event.get("shares", 0))
        if kind in ("A", "F", "ADD"):
            self._insert(ref, event["side"], shares, int(event["price"]))
        elif kind in ("E", "C", "X"):
            old = self.orders[ref]
            if shares >= old.shares:
                self._unlink(old, release_slot=True)
            else:
                old.shares -= shares
        elif kind in ("D", "DELETE"):
            self._unlink(self.orders[ref], release_slot=True)
        elif kind == "U":
            old = self.orders[ref]
            new_ref = int(event["new_ref"])
            if new_ref in self.orders:
                raise ValueError(f"duplicate replacement ID {new_ref}")
            new_set = hash_set(new_ref)
            self._location(new_set, reusable=old)
            slot = old.slot
            side = old.side
            self._unlink(old, release_slot=False)
            self._insert(new_ref, side, shares, int(event["price"]), slot=slot,
                         reusable=old)
        else:
            raise ValueError(f"unsupported event {kind}")
        self.events.append(dict(event))
        if board_frame:
            expected = self.quote()
            self.last_match = all(board_frame.get(key) == expected[key]
                                  for key in ("bid", "ask", "bid_qty", "ask_qty", "active"))
            if not self.last_match:
                self.warning = "Host mirror differs from FPGA BBO; storage prediction is unreliable"

    def quote(self):
        bids = [o for o in self.orders.values() if o.side == "B"]
        asks = [o for o in self.orders.values() if o.side == "S"]
        bid = max((o.price for o in bids), default=0)
        ask = min((o.price for o in asks), default=0)
        return {"bid": bid, "ask": ask,
                "bid_qty": sum(o.shares for o in bids if o.price == bid),
                "ask_qty": sum(o.shares for o in asks if o.price == ask),
                "active": len(self.orders)}

    def price_levels(self):
        levels = {}
        for order in self.orders.values():
            key = (order.side, order.price)
            total, count = levels.get(key, (0, 0))
            levels[key] = (total + order.shares, count + 1)
        return levels


class BoardStorageMirror(BookMirror):
    """Reconstruct active storage from the RAM write controls sent by the FPGA."""

    def __init__(self):
        super().__init__()
        self.ram_levels = {}
        self.last_event = 0
        self.prediction_match = None

    def price_levels(self):
        counts = {}
        for order in self.orders.values():
            key = (order.side, order.price)
            counts[key] = counts.get(key, 0) + 1
        return {key: (qty, counts.get(key, 0)) for key, qty in self.ram_levels.items() if qty}

    def apply_trace(self, raw, board_frame, price_base=900000, tick=1000):
        trace = decode_storage_trace(raw)
        if trace is None:
            return False
        seq = board_frame["D"]
        if seq is None or seq <= self.last_event:
            return False
        if seq != self.last_event + 1:
            self.warning = f"Storage trace gap: expected event {self.last_event + 1}, got {seq}; reset and replay"
            return False
        ref, new_ref = trace["ref"], trace["new_ref"]
        old = self.orders.get(ref)
        old_side = old.side if old else "?"
        old_price = old.price if old else 0
        old_shares = old.shares if old else 0
        event_side = old_side
        event_price = old_price
        event_shares = 0
        op_names = {1: "ADD", 2: "EXECUTE", 3: "CANCEL", 4: "DELETE", 5: "REPLACE"}
        kind = op_names.get(trace["op"], f"OP{trace['op']}")
        if trace["inv_valid"]:
            if old is None:
                self.warning = f"Board removed unknown order {ref}; reset and replay"
                return False
            if trace["inv_stash"]:
                self.stash[trace["inv_idx"]] = None
            else:
                self.ways.setdefault(trace["inv_set"], [None] * 8)[trace["inv_idx"]] = None
            del self.orders[ref]
        if trace["slot_valid"]:
            slot_data = trace["slot_data"]
            slot_live = bool((slot_data >> 46) & 1)
            side = "S" if (slot_data >> 45) & 1 else "B"
            pidx = (slot_data >> 32) & 0x1FFF
            shares = slot_data & 0xFFFFFFFF
            price = price_base + pidx * tick
            slot = trace["slot_addr"]
            if trace["op"] in (2, 3):
                event_shares = old_shares - shares
            elif trace["op"] in (1, 5):
                event_shares = shares
                event_price = price
            if old is None:
                event_side = side
            if slot_live:
                target_ref = new_ref if trace["op"] == 5 else ref
                if trace["ins_valid"]:
                    set_index = trace["ins_set"]
                    way = None if trace["ins_stash"] else trace["ins_idx"]
                    stash_index = trace["ins_idx"] if trace["ins_stash"] else None
                    if way is None:
                        self.stash[stash_index] = target_ref
                    else:
                        self.ways.setdefault(set_index, [None] * 8)[way] = target_ref
                    if old is None and slot in self.free_slots:
                        self.free_slots.remove(slot)
                    self.orders[target_ref] = StoredOrder(target_ref, side, shares, price,
                                                           slot, set_index, way, stash_index)
                elif old is not None:
                    old.shares = shares
                    old.price = price
                    old.side = side
                else:
                    self.warning = f"Board updated unknown order {ref}; reset and replay"
                    return False
            elif old is not None:
                if not trace["inv_valid"]:
                    self.warning = f"Board cleared slot {slot} without hash invalidation"
                    return False
                self.free_slots.append(slot)
        for index in (0, 1):
            if trace[f"price{index}_valid"]:
                addr = trace[f"price{index}_addr"]
                key = ("S" if addr >> 13 else "B", price_base + (addr & 0x1FFF) * tick)
                qty = trace[f"price{index}_qty"]
                if qty:
                    self.ram_levels[key] = qty
                else:
                    self.ram_levels.pop(key, None)
        self.events.append({"seq": seq, "kind": kind, "ref": ref,
                            "new_ref": new_ref if trace["op"] == 5 else 0,
                            "side": event_side, "shares": event_shares,
                            "price": event_price})
        self.last_event = seq
        expected = self.quote()
        self.last_match = all(board_frame.get(key) == expected[key]
                              for key in ("bid", "ask", "bid_qty", "ask_qty", "active"))
        if not self.last_match:
            self.warning = "FPGA storage trace disagrees with FPGA BBO/count"
        return True

    def compare_prediction(self, predicted):
        actual = {ref: (o.side, o.shares, o.price, o.slot, o.set_index,
                        o.way, o.stash_index) for ref, o in self.orders.items()}
        expected = {ref: (o.side, o.shares, o.price, o.slot, o.set_index,
                          o.way, o.stash_index) for ref, o in predicted.orders.items()}
        self.prediction_match = actual == expected and self.price_levels() == predicted.price_levels()
        if self.prediction_match is False:
            self.warning = "Host prediction differs from FPGA storage trace"
        return self.prediction_match
