"""Read-only UART queries for the FPGA's actual display memories."""

import re
from book_inspector import decode_storage_trace


WIDTHS = {"S": 12, "H": 152, "X": 19, "P": 8, "F": 3,
          "L": 3, "Q": 44, "E": 87}
RESPONSE = re.compile(rb"^@([SHXPFLQE])([0-9A-Fa-f]{4})=([0-9A-Fa-f]+)\r?\n?$")


def query(kind, address):
    if kind not in WIDTHS or not 0 <= address <= 0x3FFF:
        raise ValueError("invalid FPGA readback address")
    return f"?{kind}{address:04X}\n".encode("ascii")


def parse_response(raw):
    match = RESPONSE.fullmatch(raw if isinstance(raw, bytes) else raw.encode("ascii"))
    if not match:
        return None
    kind = match.group(1).decode("ascii")
    digits = match.group(3)
    if len(digits) != WIDTHS[kind]:
        return None
    return kind, int(match.group(2), 16), int(digits, 16)


def event_queries(frame):
    """Read touched storage and both FPGA-owned journal records after a commit."""
    seq = frame.get("D")
    if not seq or not frame.get("storage_trace"):
        return []
    trace = decode_storage_trace(frame["storage_trace"])
    if trace is None:
        return []
    found = []
    def add(kind, address):
        pair = kind, address
        if pair not in found:
            found.append(pair)
    if trace["slot_valid"]:
        add("S", trace["slot_addr"])
    if trace["inv_valid"]:
        add("X" if trace["inv_stash"] else "H",
            trace["inv_idx"] if trace["inv_stash"] else trace["inv_set"])
    if trace["ins_valid"]:
        add("X" if trace["ins_stash"] else "H",
            trace["ins_idx"] if trace["ins_stash"] else trace["ins_set"])
    for index in (0, 1):
        if trace[f"price{index}_valid"]:
            address = trace[f"price{index}_addr"]
            add("P", address)
            add("L", address)
    if frame.get("active") is not None and frame["active"] < 2048:
        add("F", 2047 - frame["active"])
    add("E", (seq - 1) & 255)
    add("Q", (seq - 1) & 127)
    return found


class ReadbackAudit:
    def __init__(self):
        self.values = {}
        self.mismatches = {}
        self.verified = set()
        self.current = set()
        self.supported = False

    def reset(self):
        self.__init__()

    def invalidate(self, pairs):
        for pair in pairs:
            self.verified.discard(pair)
            self.current.discard(pair)

    def ingest(self, response, mirror, frame, request_seq=None):
        parsed = parse_response(response)
        if parsed is None:
            return False
        self.supported = True
        kind, address, value = parsed
        self.values[(kind, address)] = value
        if (frame is None or request_seq != mirror.last_event or
                frame.get("D") != request_seq):
            return True
        self.current.add((kind, address))
        expected = self.expected(kind, address, mirror, frame)
        if expected is not None:
            if value == expected:
                self.verified.add((kind, address))
                self.mismatches.pop((kind, address), None)
            else:
                self.verified.discard((kind, address))
                self.mismatches[(kind, address)] = (
                    f"RAM {kind}{address:04X}: board {value:X}, trace {expected:X}")
        return True

    def current_value(self, kind, address):
        pair = kind, address
        return self.values.get(pair) if pair in self.current else None

    @staticmethod
    def expected(kind, address, mirror, frame):
        if kind == "S":
            if hasattr(mirror, "slot_words"):
                return mirror.slot_words.get(address, 0)
            order = next((o for o in mirror.orders.values() if o.slot == address), None)
            if order is None:
                return 0
            base = frame.get("base") if frame.get("base") is not None else 900000
            tick = frame.get("tick") or 1000
            pidx = (order.price - base) // tick
            return (1 << 46) | ((order.side == "S") << 45) | (pidx << 32) | order.shares
        if kind == "H":
            ways = mirror.ways.get(address, [None] * 8)
            value = 0
            for way in reversed(range(8)):
                ref = ways[way]
                order = mirror.orders.get(ref) if ref is not None else None
                cell = ((1 << 75) | (order.slot << 64) | ref) if order else 0
                value = (value << 76) | cell
            return value
        if kind == "X":
            ref = mirror.stash[address] if address < 8 else None
            order = mirror.orders.get(ref) if ref is not None else None
            return ((1 << 75) | (order.slot << 64) | ref) if order else 0
        if kind in ("P", "L"):
            base = frame.get("base") if frame.get("base") is not None else 900000
            tick = frame.get("tick") or 1000
            key = ("S" if address & 8192 else "B", base + (address & 8191) * tick)
            qty, count = mirror.price_levels().get(key, (0, 0))
            return qty if kind == "P" else count
        if kind == "F":
            return mirror.free_slots[address] if address < len(mirror.free_slots) else None
        if kind == "E":
            if address != ((mirror.last_event - 1) & 255):
                return None
            return (mirror.last_event << 316) | int(frame["storage_trace"], 16)
        if kind == "Q":
            if address != ((mirror.last_event - 1) & 127):
                return None
            # Quote ring follows the FPGA's post-commit BBO. Its bit layout
            # matches the existing 175-bit VGA snapshot.
            return ((int(frame["valid"]) << 174) |
                    (int(frame["bid"] != 0) << 173) |
                    (frame["bid"] << 141) | (frame["bid_qty"] << 109) |
                    (int(frame["ask"] != 0) << 108) |
                    (frame["ask"] << 76) | (frame["ask_qty"] << 44) |
                    (frame["active"] << 32) | frame["D"])
        return None


def decode_slot(value, base, tick):
    if not value >> 46 & 1:
        return None
    return {"side": "S" if value >> 45 & 1 else "B",
            "pidx": (value >> 32) & 0x1FFF,
            "price": base + ((value >> 32) & 0x1FFF) * tick,
            "shares": value & 0xFFFFFFFF}


def decode_hash_cell(value):
    return None if not value >> 75 & 1 else {"slot": (value >> 64) & 0x7FF,
                                               "ref": value & ((1 << 64) - 1)}
