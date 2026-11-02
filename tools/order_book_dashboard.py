#!/usr/bin/env python3
"""Display-only UART dashboard with a local relay for order_journey.py.

Run this first, then run order_journey.py with the shown --uart-socket path.
The dashboard never sends Ethernet packets or injects FPGA orders.
"""

import argparse
import curses
import json
import os
import queue
import socket
import threading
import time
from collections import deque
from dataclasses import dataclass

from order_journey import next_advanced_order, parse_frame, serial
from book_inspector import BookMirror, BoardStorageMirror, decode_storage_trace
from fpga_readback import (ReadbackAudit, decode_hash_cell, decode_slot,
                           parse_response, query, SnapshotCollector)


@dataclass(frozen=True)
class Point:
    when: float
    event: int
    bid: int
    ask: int


class DashboardState:
    def __init__(self):
        self.frame = None
        self.last_good = None
        self.last_seen = 0.0
        self.points = deque(maxlen=128)
        self.changes = deque(maxlen=100)
        self.invalid = False

    def ingest(self, raw, when=None):
        frame = parse_frame(raw.decode("ascii", errors="replace") if isinstance(raw, bytes) else raw)
        if frame is None:
            return False
        when = time.time() if when is None else when
        if self.frame and frame["D"] is not None and self.frame["D"] is not None and frame["D"] < self.frame["D"]:
            self.points.clear()
            self.changes.clear()
            self.last_good = None
        old = self.last_good
        self.frame = frame
        self.last_seen = when
        self.invalid = not frame["valid"] or frame["error"] != 0
        if self.invalid:
            return True
        self.last_good = frame
        event = frame["D"] if frame["D"] is not None else len(self.points)
        if not self.points or event != self.points[-1].event or (frame["bid"], frame["ask"]) != (self.points[-1].bid, self.points[-1].ask):
            self.points.append(Point(when, event, frame["bid"], frame["ask"]))
        if old:
            for label, key in (("BID", "bid"), ("ASK", "ask")):
                if old[key] != frame[key]:
                    direction = "rose" if frame[key] > old[key] else "fell"
                    self.changes.appendleft((when, event, label, direction, old[key], frame[key]))
        return True

    def load_quotes(self, values, seq):
        """Rebuild retained quote history entirely from the FPGA quote ring."""
        points = []
        for event in range(max(1, seq - 127), seq + 1):
            word = values.get(("Q", (event - 1) & 127))
            if word is None or (word & 0xFFFFFFFF) != event:
                continue
            points.append(Point(None, event, (word >> 141) & 0xFFFFFFFF,
                                (word >> 76) & 0xFFFFFFFF))
        self.points = deque(points, maxlen=128)
        if self.invalid and points:
            latest = values[("Q", (points[-1].event - 1) & 127)]
            self.last_good = {**self.frame, "bid": points[-1].bid,
                              "ask": points[-1].ask,
                              "bid_qty": (latest >> 109) & 0xFFFFFFFF,
                              "ask_qty": (latest >> 44) & 0xFFFFFFFF,
                              "active": (latest >> 32) & 0xFFF}
        self.changes.clear()
        for old, new in zip(points, points[1:]):
            for label, key in (("BID", "bid"), ("ASK", "ask")):
                before, after = getattr(old, key), getattr(new, key)
                if before != after:
                    self.changes.appendleft((None, new.event, label,
                                             "rose" if after > before else "fell", before, after))


def money(raw):
    return "—" if raw is None or raw == 0 else f"${raw / 10000:.4f}"


def socket_listener(path):
    if os.path.exists(path):
        probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            probe.settimeout(0.2)
            probe.connect(path)
        except OSError:
            os.unlink(path)
        else:
            raise RuntimeError(f"dashboard relay already running at {path}")
        finally:
            probe.close()
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(path)
    os.chmod(path, 0o600)
    listener.listen(2)
    listener.setblocking(False)
    return listener


def serial_worker(port, listener, updates, stop, event_listener=None, requests=None):
    clients = []
    queued = deque()
    pending = None
    last_scheduled = 0
    readback_failures = 0
    try:
        while not stop.is_set():
            if requests:
                try:
                    while True:
                        pair = requests.get_nowait()
                        if pair not in queued and (pending is None or pair != pending[:2]):
                            queued.append(pair)
                except queue.Empty:
                    pass
                if pending is None and not queued:
                    try:
                        queued.append(requests.get(timeout=0.02))
                    except queue.Empty:
                        pass
            if event_listener:
                try:
                    while True:
                        payload = event_listener.recv(4096)
                        updates.put(("host_event", json.loads(payload)))
                except BlockingIOError:
                    pass
            if listener:
                try:
                    while True:
                        client, _ = listener.accept()
                        client.settimeout(0.05)
                        clients.append(client)
                except BlockingIOError:
                    pass
            if queued and pending is None and readback_failures < 2:
                kind, addr = queued.popleft()
                port.write(query(kind, addr))
                pending = kind, addr, last_scheduled, time.monotonic()
            raw = port.readline()
            if raw:
                reply = parse_response(raw)
                if reply:
                    matched = pending and reply[:2] == pending[:2]
                    updates.put(("readback", raw, pending[2] if matched else None))
                    if matched:
                        pending = None
                        readback_failures = 0
                else:
                    frame = parse_frame(raw.decode("ascii", errors="replace"))
                    if frame and frame.get("D") is not None and frame["D"] < last_scheduled:
                        queued.clear()
                        pending = None
                        last_scheduled = 0
                        readback_failures = 0
                    if frame and frame.get("D") and frame["D"] > last_scheduled:
                        last_scheduled = frame["D"]
                    updates.put(raw)
                # The sender consumes BBO confirmations, not RAM readback.
                # Forwarding snapshot traffic fills its socket while it sleeps
                # between orders and can disconnect an otherwise healthy link.
                for client in clients[:] if not reply else []:
                    try:
                        client.sendall(raw)
                    except OSError:
                        clients.remove(client)
                        client.close()
            if pending and time.monotonic() - pending[3] > 2.0:
                pending = None
                readback_failures += 1
    except Exception as exc:
        updates.put(exc)
    finally:
        for client in clients:
            client.close()


def demo_worker(updates, stop):
    sample = BookMirror()
    for n in range(14):
        if stop.is_set():
            return
        if n:
            order = next_advanced_order(n - 1)
            event = {"kind": order.kind, "ref": order.ref, "side": order.side,
                     "shares": order.shares, "price": order.price,
                     "new_ref": order.new_ref, "seq": n}
            sample.apply(event)
        quote = sample.quote()
        updates.put(f"[BBO] B:{quote['bid']:08X} | A:{quote['ask']:08X} | V:1 | E:00 | QB:{quote['bid_qty']:08X} | QA:{quote['ask_qty']:08X} | N:{quote['active']:03X} | R:{n:08X} | U:{n:08X} | M:{n:08X} | I:{n:08X} | F:{n:08X} | D:{n:08X}\n".encode())
        if n:
            event["board"] = {**quote, "D": n}
            updates.put(("host_event", event))
        stop.wait(5.5)


def put(screen, y, x, value, attr=0):
    height, width = screen.getmaxyx()
    if 0 <= y < height and 0 <= x < width:
        try:
            screen.addnstr(y, x, str(value), width - x - 1, attr)
        except curses.error:
            pass


def draw_chart(screen, y, chart_height, title, points, key, axis, x0, width):
    put(screen, y, x0 + 2, title, curses.A_BOLD)
    left, right = x0 + 13, max(x0 + 14, x0 + width - 3)
    graph_width = right - left + 1
    values = [getattr(p, key) for p in points]
    if not values:
        put(screen, y + 2, left, "Waiting for FPGA quotes…", curses.A_DIM)
        return
    nonzero = [v for v in values if v]
    if not nonzero:
        put(screen, y + 2, left, "No orders on this side yet", curses.A_DIM)
        return
    lo, hi = min(nonzero), max(nonzero)
    if lo == hi:
        lo -= 1000
        hi += 1000
    else:
        pad = max(1000, (hi - lo) // 5)
        lo -= pad
        hi += pad
    rows = max(5, chart_height - 2)
    for row in range(rows):
        value = hi - (hi - lo) * row // (rows - 1)
        if row in {0, rows // 4, rows // 2, (rows * 3) // 4, rows - 1}:
            put(screen, y + 1 + row, x0 + 1, f"{value / 10000:8.4f}", curses.A_DIM)
        put(screen, y + 1 + row, x0 + 12, "┤", curses.A_DIM)
    selected = points[-min(len(points), max(2, graph_width // 3)):]
    positions = []
    use_time = axis == "time" and all(p.when is not None for p in selected)
    axis_values = [p.when if use_time else p.event for p in selected]
    axis_min, axis_max = min(axis_values), max(axis_values)
    for i, point in enumerate(selected):
        value = getattr(point, key)
        x = left + (round((axis_values[i] - axis_min) * (graph_width - 1) / (axis_max - axis_min))
                    if axis_max > axis_min else i * (graph_width - 1) // max(1, len(selected) - 1))
        row = None if value == 0 else round((hi - value) * (rows - 1) / (hi - lo))
        positions.append((x, row, value))
    for i, (x, row, value) in enumerate(positions):
        if row is None:
            continue
        attr = curses.color_pair(1)
        if i:
            px, prow, pvalue = positions[i - 1]
            if prow is not None:
                attr = curses.color_pair(2 if value > pvalue else 3 if value < pvalue else 1)
                for col in range(px, x + 1):
                    put(screen, y + 1 + prow, col, "─", attr)
                for r in range(min(prow, row), max(prow, row) + 1):
                    put(screen, y + 1 + r, x, "│", attr)
        put(screen, y + 1 + row, x, "●", attr | curses.A_BOLD)
    first, last = selected[0], selected[-1]
    start = time.strftime("%H:%M:%S", time.localtime(first.when)) if use_time else str(first.event)
    end = time.strftime("%H:%M:%S", time.localtime(last.when)) if use_time else str(last.event)
    axis_label = f"{start} ─────── {end}  {'time' if use_time else 'events'}"
    put(screen, y + rows + 1, left, axis_label[:max(0, x0 + width - left - 1)], curses.A_DIM)


NAV_FOOTER = "Q Quit | 1 Market 2 Orders 3 Hash 4 Events 5 Status 6 Levels 7 Slots"
MARKET_HINT = "Green = rising · Red = falling · Grey = unchanged    [T] Axis  [H] Quote history"


def draw_mirror_page(screen, state, mirror, page, offset, selected_set, selected_slot, readback=None):
    height, width = screen.getmaxyx()
    board_source = isinstance(mirror, BoardStorageMirror)
    base = state.frame["base"] if state.frame and state.frame.get("base") is not None else 900000
    tick = state.frame["tick"] if state.frame and state.frame.get("tick") else 1000
    put(screen, 0, 2, "FPGA ORDER BOOK  /  " + page.upper(), curses.A_BOLD)
    put(screen, 1, 2, ("FPGA STORAGE · " +
                         (f"{len(readback.current)} RAM words in latest snapshot"
                          if readback and readback.current else "reading FPGA snapshot") +
                         " · host prediction checked separately"
                         if board_source else "HOST MIRROR · predicted from confirmed orders; RAM contents are not read over UART"), curses.A_DIM)
    if state.invalid:
        put(screen, 2, 2, "FPGA BOOK INVALID · storage shown from last completed snapshot", curses.color_pair(3) | curses.A_BOLD)
    elif readback and readback.mismatches:
        put(screen, 2, 2, list(readback.mismatches.values())[-1], curses.color_pair(3) | curses.A_BOLD)
    elif mirror.warning:
        put(screen, 2, 2, mirror.warning, curses.color_pair(3) | curses.A_BOLD)
    elif board_source and not mirror.snapshot_ready:
        put(screen, 2, 2, "Reading the current FPGA book and retained journals", curses.A_DIM)
    elif not board_source and not mirror.events:
        put(screen, 2, 2, "Waiting for sender events; run order_journey.py with --uart-socket", curses.A_DIM)
    elif mirror.last_match is True:
        put(screen, 2, 2, "Mirror BBO and active count match the latest FPGA confirmation", curses.color_pair(2))
    content_bottom = height - 3
    if page == "orders":
        put(screen, 4, 2, f"ACTIVE ORDERS  {len(mirror.orders)} / 2048", curses.A_BOLD)
        put(screen, 5, 2, "SLOT   ORDER ID     SIDE      SHARES       PRICE      P_IDX  HASH SET  WAY       RAM", curses.A_DIM)
        orders = sorted(mirror.orders.values(), key=lambda o: o.slot, reverse=True)
        for row, order in enumerate(orders[offset:offset + max(0, content_bottom - 6)], 6):
            location = str(order.way) if order.way is not None else f"stash {order.stash_index}"
            raw_slot = readback.current_value("S", order.slot) if readback else None
            stored = decode_slot(raw_slot, base, tick) if raw_slot is not None else None
            raw_hash = (readback.current_value("H", order.set_index) if order.way is not None else
                        readback.current_value("X", order.stash_index)) if readback else None
            cell = decode_hash_cell((raw_hash >> (order.way * 76)) & ((1 << 76) - 1) if order.way is not None else raw_hash) if raw_hash is not None else None
            ref = cell["ref"] if cell and cell["slot"] == order.slot else order.ref
            side = stored["side"] if stored else order.side
            shares = stored["shares"] if stored else order.shares
            price = stored["price"] if stored else order.price
            pidx = (price - base) // tick
            hash_key = ("H", order.set_index) if order.way is not None else ("X", order.stash_index)
            ram_mark = "✓" if stored and cell and ("S", order.slot) in readback.verified and hash_key in readback.verified else "!" if stored or cell else "…"
            put(screen, row, 2, f"{order.slot:4}   {ref:<12} {'BUY' if side == 'B' else 'SELL':<8} {shares:>8}   {money(price):<11} {pidx:>5}  {order.set_index:>4}      {location:<9} {ram_mark}")
        put(screen, height - 3, 2, "↑/↓ scroll · Slot and hash way read from FPGA RAM" if board_source else
            "↑/↓ scroll · Slot/way is a host prediction", curses.A_DIM)
    elif page == "hash":
        put(screen, 4, 2, "HASH TABLE · 1024 SETS × 8 WAYS + 8 STASH ENTRIES", curses.A_BOLD)
        put(screen, 5, 2, "Each cell is one set; digit = occupied ways · · = empty", curses.A_DIM)
        rows_visible = min(32, max(1, content_bottom - 8))
        base_row = (selected_set // 32 // rows_visible) * rows_visible
        for r in range(rows_visible):
            set_row = base_row + r
            if set_row >= 32:
                break
            cells = []
            for c in range(32):
                index = set_row * 32 + c
                raw_set = readback.current_value("H", index) if readback else None
                used = (sum(decode_hash_cell((raw_set >> (way * 76)) & ((1 << 76) - 1)) is not None
                            for way in range(8)) if raw_set is not None else
                        sum(ref is not None for ref in mirror.ways.get(index, ())))
                cells.append("▣" if index == selected_set else str(used) if used else "·")
            put(screen, 7 + r, 2, f"{set_row * 32:04} " + " ".join(cells))
        right = max(72, width // 2)
        put(screen, 6, right, f"SELECTED SET {selected_set:04}  (XOR of order ID slices)", curses.A_BOLD)
        raw_set = readback.current_value("H", selected_set) if readback else None
        ways = mirror.ways.get(selected_set, [None] * 8)
        for way, ref in enumerate(ways):
            if raw_set is not None:
                cell = decode_hash_cell((raw_set >> (way * 76)) & ((1 << 76) - 1))
                detail = f"ID {cell['ref']} → slot {cell['slot']}" if cell else "empty"
            else:
                order = mirror.orders.get(ref) if ref is not None else None
                detail = f"ID {ref} → slot {order.slot}" if order else "empty"
            put(screen, 8 + way, right, f"way {way}  {detail}")
        put(screen, 17, right, "Source: FPGA hash RAM" if raw_set is not None else "Source: FPGA occupancy bitmap", curses.A_DIM)
        put(screen, 18, right, f"Free slots {mirror.free_count if board_source else len(mirror.free_slots)}   Active {len(mirror.orders)}")
        put(screen, 20, right, "COLLISION STASH", curses.A_BOLD)
        for index, ref in enumerate(mirror.stash):
            if 21 + index >= content_bottom:
                break
            raw_stash = readback.current_value("X", index) if readback else None
            cell = decode_hash_cell(raw_stash) if raw_stash is not None else None
            detail = (f"ID {cell['ref']} → slot {cell['slot']}" if cell else "empty") if raw_stash is not None else (f"ID {ref} → set {mirror.orders[ref].set_index}" if ref is not None else "empty")
            put(screen, 21 + index, right, f"stash {index}  {detail}")
        put(screen, height - 3, 2, "Arrows: select set · N: next occupied set · ▣: selected", curses.A_DIM)
    elif page == "events":
        put(screen, 4, 2, f"FPGA EVENT JOURNAL  {min(len(mirror.events), 256)} / 256 stored" if board_source else
            f"CONFIRMED HOST EVENTS  {len(mirror.events)}", curses.A_BOLD)
        put(screen, 5, 2, "SEQ    TYPE       ORDER ID      SIDE      SHARES       PRICE      NEW ID", curses.A_DIM)
        events = list(reversed(mirror.events[-256:] if board_source else mirror.events))
        for row, event in enumerate(events[offset:offset + max(0, content_bottom - 6)], 6):
            raw_event = readback.current_value("E", (event["seq"] - 1) & 255) if readback else None
            event_key = ("E", (event["seq"] - 1) & 255)
            in_ring = raw_event is not None and raw_event >> 362 == event["seq"]
            journal_mark = "RAM ✓" if in_ring and event_key in readback.verified else "RAM !" if in_ring else "trace"
            record = decode_storage_trace(f"{raw_event & ((1 << 316) - 1):079X}") if in_ring else None
            kind = {1: "ADD", 2: "EXECUTE", 3: "CANCEL", 4: "DELETE", 5: "REPLACE"}.get(record["op"], "UNKNOWN") if record else event["kind"]
            ref = record["ref"] if record else event["ref"]
            new_ref = record["new_ref"] if record and record["op"] == 5 else event["new_ref"]
            shares = str(event["shares"]) if event["shares"] is not None else "—"
            put(screen, row, 2, f"{event['seq']:4}   {kind:<10} {ref:<13} {event['side']:<9} {shares:>8}   {money(event['price']):<11} {new_ref or '—'}  {journal_mark}")
        put(screen, height - 3, 2, "↑/↓ scroll · FPGA journal with canonical shares and RAM writes", curses.A_DIM)
    elif page == "levels":
        put(screen, 4, 2, "PRICE RAM · AGGREGATED QUANTITY BY SIDE AND PRICE INDEX", curses.A_BOLD)
        levels = mirror.price_levels()
        max_qty = max((qty for qty, _ in levels.values()), default=1)
        pane = width // 2
        for side, title, start_x, reverse in (("B", "BID LEVELS", 2, True),
                                              ("S", "ASK LEVELS", pane + 2, False)):
            put(screen, 6, start_x, title, curses.A_BOLD)
            put(screen, 7, start_x, "PRICE        P_IDX   QTY    ORDERS   DEPTH", curses.A_DIM)
            prices = sorted((price for (kind, price) in levels if kind == side), reverse=reverse)
            visible_rows = max(0, content_bottom - 9)
            side_offset = min(offset, max(0, len(prices) - visible_rows)) if visible_rows else 0
            for row, price in enumerate(prices[side_offset:side_offset + visible_rows], 8):
                qty, count = levels[(side, price)]
                addr = (8192 if side == "S" else 0) | ((price - base) // tick)
                ram_qty = readback.current_value("P", addr) if readback else None
                ram_count = readback.current_value("L", addr) if readback else None
                if ram_qty is not None:
                    qty = ram_qty
                if ram_count is not None:
                    count = ram_count
                bar_width = min(max(0, pane - 43), 28)
                bar = "█" * max(1, round(qty / max_qty * bar_width)) if bar_width else ""
                put(screen, row, start_x, f"{money(price):<12} {(price - base) // tick:>5} {qty:>7} {count:>7}   {bar}")
            if not prices:
                put(screen, 8, start_x, "No active levels", curses.A_DIM)
        put(screen, height - 3, 2, "↑/↓ scroll · Quantities and counts read from FPGA price RAM" if board_source else
            "↑/↓ scroll · Price levels summed from host-mirrored orders", curses.A_DIM)
    elif page == "slots":
        put(screen, 4, 2, "SLOT TABLE · 2048 ENTRIES / LIFO FREE STACK", curses.A_BOLD)
        put(screen, 5, 2, "Each cell is a slot: ■ occupied  · free  ▣ selected", curses.A_DIM)
        by_slot = {order.slot: order for order in mirror.orders.values()}
        rows_visible = min(32, max(1, content_bottom - 8))
        base_row = (selected_slot // 64 // rows_visible) * rows_visible
        for r in range(rows_visible):
            slot_row = base_row + r
            if slot_row >= 32:
                break
            cells = []
            for c in range(64):
                slot = slot_row * 64 + c
                cells.append("▣" if slot == selected_slot else "■" if slot in by_slot else "·")
            put(screen, 7 + r, 2, f"{slot_row * 64:04} " + "".join(cells))
        right = max(72, width // 2)
        put(screen, 6, right, f"SELECTED SLOT {selected_slot:04}", curses.A_BOLD)
        order = by_slot.get(selected_slot)
        raw_slot = readback.current_value("S", selected_slot) if readback else None
        stored = decode_slot(raw_slot, base, tick) if raw_slot is not None else None
        if order:
            raw_hash = (readback.current_value("H", order.set_index) if order.way is not None else
                        readback.current_value("X", order.stash_index)) if readback else None
            cell = decode_hash_cell((raw_hash >> (order.way * 76)) & ((1 << 76) - 1) if order.way is not None else raw_hash) if raw_hash is not None else None
            ref = cell["ref"] if cell and cell["slot"] == selected_slot else order.ref
            put(screen, 8, right, f"Order ID     {ref}")
            put(screen, 9, right, f"Side         {'BUY' if (stored['side'] if stored else order.side) == 'B' else 'SELL'}")
            put(screen, 10, right, f"Shares       {stored['shares'] if stored else order.shares}")
            put(screen, 11, right, f"Price        {money(stored['price'] if stored else order.price)}")
            put(screen, 12, right, f"Hash set     {order.set_index}")
            put(screen, 13, right, f"Way / stash  {order.way if order.way is not None else f'stash {order.stash_index}'}")
        else:
            put(screen, 8, right, "Free slot")
        put(screen, 15, right, "Selected slot: FPGA RAM" if raw_slot is not None else "Selected slot: awaiting RAM query", curses.A_DIM)
        put(screen, 17, right, "FREE STACK", curses.A_BOLD)
        put(screen, 19, right, f"Free {mirror.free_count if board_source else len(mirror.free_slots)}  ·  Active {len(mirror.orders)}")
        free_addr = (mirror.free_count if board_source else len(mirror.free_slots)) - 1
        ram_top = readback.current_value("F", free_addr) if readback and free_addr >= 0 else None
        fallback_top = mirror.free_top[-1] if board_source and mirror.free_top else mirror.free_slots[-1] if not board_source and mirror.free_slots else 'none'
        put(screen, 20, right, f"Next allocation: slot {ram_top if ram_top is not None else fallback_top}")
        put(screen, 22, right, "Top of LIFO stack:", curses.A_DIM)
        stack_rows = max(0, min(8, content_bottom - 24))
        top_slots = (mirror.free_top if board_source else mirror.free_slots)[-stack_rows:] if stack_rows else []
        for i, slot in enumerate(reversed(top_slots)):
            put(screen, 23 + i, right, f"{i + 1:>2}. slot {slot}")
        put(screen, height - 3, 2, "Arrows: select slot · N: next occupied slot · FPGA RAM snapshot" if board_source else
            "Arrows: select slot · N: next occupied slot · Host prediction", curses.A_DIM)
    elif page == "status":
        frame = state.frame
        put(screen, 4, 2, "BOARD TELEMETRY", curses.A_BOLD)
        fields = (("R", "Ethernet frames"), ("U", "UDP packets"), ("M", "Mold messages"),
                  ("I", "ITCH events"), ("F", "FIFO accepted"), ("D", "Book completed"))
        for row, (key, label) in enumerate(fields, 6):
            put(screen, row, 3, f"{label:<22} {frame[key] if frame and frame[key] is not None else '—'}")
        put(screen, 14, 2, "BOOK", curses.A_BOLD)
        put(screen, 16, 3, f"Valid: {frame['valid'] if frame else '—'}   Error: 0x{frame['error']:02X}" if frame else "No board telemetry")
        put(screen, 17, 3, f"Bid: {money(frame['bid'])} × {frame['bid_qty']}   Ask: {money(frame['ask'])} × {frame['ask_qty']}" if frame else "")
        put(screen, 18, 3, f"Active orders: {frame['active']}" if frame else "")
        put(screen, 21, 2, "PROVENANCE", curses.A_BOLD)
        put(screen, 23, 3, "Quotes and counters: directly reported by FPGA UART")
        put(screen, 24, 3, "Orders, hash ways, slots, levels: fresh FPGA RAM snapshot" if board_source else
            "Orders, hash ways and slot IDs: host model prediction")
        put(screen, 25, 3, (f"Host prediction vs FPGA RAM: {mirror.prediction_match if mirror.prediction_match is not None else 'waiting for full sender replay'}"
                            if board_source else "Aggregate BBO/quantity/count compared with FPGA"))
    put(screen, height - 2, 2, NAV_FOOTER, curses.A_REVERSE)
    screen.refresh()


def draw(screen, state, mirror, page, axis, history_offset, selected_set, selected_slot, demo, relay, readback=None):
    screen.erase()
    height, width = screen.getmaxyx()
    if height < 27 or width < 70:
        put(screen, 1, 2, "Enlarge terminal to at least 70 × 27. Press Q to quit.")
        screen.refresh()
        return
    curses.curs_set(0)
    if page in ("orders", "hash", "events", "status", "levels", "slots"):
        draw_mirror_page(screen, state, mirror, page, history_offset,
                         selected_set, selected_slot, readback)
        return
    if page == "history":
        put(screen, 0, 2, "CONFIRMED QUOTE HISTORY", curses.A_BOLD)
        put(screen, 1, 2, "Board event       Received        Best bid       Best ask", curses.A_DIM)
        entries = list(reversed(state.points))
        visible = max(1, height - 5)
        for row, point in enumerate(entries[history_offset:history_offset + visible], 2):
            received = time.strftime('%H:%M:%S', time.localtime(point.when)) if point.when is not None else "—"
            put(screen, row, 2, f"#{point.event:<15} {received:<15} {money(point.bid):<14} {money(point.ask)}")
        put(screen, height - 2, 2, "[H] Dashboard   [↑/↓] Scroll   [Q] Quit", curses.A_REVERSE)
        put(screen, height - 1, 2, f"Showing {len(entries)} most recent confirmed samples (maximum 128)", curses.A_DIM)
        screen.refresh()
        return
    live = state.frame is not None and time.time() - state.last_seen < 3.0
    status = "SIMULATED" if demo else "UART LIVE" if live else "UART WAITING"
    validity = "BOOK INVALID" if state.invalid else "BOOK VALID" if state.last_good else "NO QUOTE"
    put(screen, 0, 2, "FPGA ORDER BOOK", curses.A_BOLD)
    put(screen, 0, max(30, width - len(status) - len(validity) - 6), f"{status}  ·  {validity}", curses.color_pair(3) if state.invalid else curses.color_pair(2) if live else curses.A_DIM)
    frame = state.last_good
    bid = money(frame["bid"]) if frame else "—"
    ask = money(frame["ask"]) if frame else "—"
    spread = money(frame["ask"] - frame["bid"]) if frame and frame["bid"] and frame["ask"] and frame["ask"] >= frame["bid"] else "—"
    put(screen, 2, 2, f"BID {bid} × {frame['bid_qty'] if frame and frame['bid_qty'] is not None else '—'}", curses.A_BOLD)
    put(screen, 2, width // 3, f"ASK {ask} × {frame['ask_qty'] if frame and frame['ask_qty'] is not None else '—'}", curses.A_BOLD)
    put(screen, 2, width * 2 // 3, f"SPREAD {spread}", curses.A_BOLD)
    if state.invalid:
        put(screen, 3, 2, f"INVALID BOOK · error 0x{state.frame['error']:02X} · last good quotes shown · reset/replay required", curses.color_pair(3) | curses.A_BOLD)
    pane = width // 2
    content_top = 4
    content_bottom = height - 4
    available = content_bottom - content_top
    chart_height = (available - 1) // 2
    second_chart_y = content_top + chart_height + 1
    for y in range(content_top, content_bottom):
        put(screen, y, pane, "│", curses.A_DIM)
    draw_chart(screen, content_top, chart_height, "BID HISTORY", list(state.points), "bid", axis, 0, pane)
    draw_chart(screen, second_chart_y, chart_height, "ASK HISTORY", list(state.points), "ask", axis, 0, pane)
    put(screen, 4, pane + 2, "ETHERNET → ORDER BOOK", curses.A_BOLD)
    labels = (("R", "01  Ethernet frames"), ("U", "02  UDP packets"),
              ("M", "03  Mold messages"), ("I", "04  ITCH events"),
              ("F", "05  Event FIFO"), ("D", "06  Book completed"))
    stage_stride = max(2, available * 3 // 5 // len(labels))
    for i, (key, label) in enumerate(labels):
        value = state.frame[key] if state.frame and state.frame[key] is not None else "—"
        stage_y = content_top + 1 + i * stage_stride
        put(screen, stage_y, pane + 3, f"{label:<24} {value}", curses.A_DIM if not state.frame else 0)
        if i < len(labels) - 1:
            put(screen, stage_y + 1, pane + 5, "↓", curses.A_DIM)
    status_y = content_top + 2 + len(labels) * stage_stride
    put(screen, status_y, pane + 2, "BOOK STATUS", curses.A_BOLD)
    if state.frame:
        put(screen, status_y + 1, pane + 3, f"Active orders  {state.frame['active'] if state.frame['active'] is not None else '—'}    Error 0x{state.frame['error']:02X}")
    updates_y = status_y + 3
    put(screen, updates_y, pane + 2, "QUOTE UPDATES", curses.A_BOLD)
    for i, item in enumerate(list(state.changes)[:max(0, content_bottom - updates_y - 1)]):
        when, event, label, direction, old, new = item
        put(screen, updates_y + 1 + i, pane + 3, f"#{event} {label} {direction}: {money(old)} → {money(new)}", curses.color_pair(2 if direction == "rose" else 3))
    put(screen, height - 3, 2, MARKET_HINT, curses.A_DIM)
    put(screen, height - 2, 2, NAV_FOOTER, curses.A_REVERSE)
    if relay:
        put(screen, height - 1, 2, f"Sender UART relay: {relay}", curses.A_DIM)
    screen.refresh()


def run_ui(screen, state, mirror, prediction, updates, stop, demo, relay, requests=None):
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_WHITE, -1)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_RED, -1)
    curses.mousemask(curses.BUTTON1_CLICKED)
    screen.timeout(100)
    axis = "events"
    page = "market"
    history_offset = 0
    selected_set = 0
    selected_slot = 2047
    readback = None if demo else ReadbackAudit()
    snapshot = None if demo else SnapshotCollector()
    last_requested_set = None
    last_requested_slot = None
    while True:
        while True:
            try:
                item = updates.get_nowait()
            except queue.Empty:
                break
            if isinstance(item, Exception):
                raise item
            if isinstance(item, tuple) and item[0] == "readback":
                parsed = parse_response(item[1])
                if snapshot and snapshot.accept(item[1], item[2]):
                    if snapshot.complete and state.frame and state.frame["D"] == snapshot.seq:
                        try:
                            mirror.load_snapshot(snapshot.values, state.frame,
                                                 decode_hash_cell, decode_slot)
                        except ValueError as exc:
                            mirror.warning = str(exc)
                        else:
                            state.load_quotes(snapshot.values, snapshot.seq)
                            readback.values = snapshot.values.copy()
                            readback.current = set(snapshot.values)
                            readback.verified = set(snapshot.values)
                            readback.supported = True
                            readback.mismatches.clear()
                            if prediction is not None and len(prediction.events) == snapshot.seq:
                                mirror.compare_prediction(prediction)
                elif parsed and mirror.snapshot_ready and state.frame and item[2] == state.frame["D"]:
                    readback.ingest(item[1], mirror, state.frame, item[2])
            elif isinstance(item, tuple) and item[0] == "host_event":
                event = item[1]
                try:
                    if prediction is None:
                        mirror.apply(event, event.get("board"))
                    else:
                        prediction.apply(event, event.get("board"))
                        if mirror.snapshot_ready and len(prediction.events) == mirror.last_event:
                            mirror.compare_prediction(prediction)
                except (KeyError, ValueError) as exc:
                    mirror.warning = f"Host mirror stopped: {exc}"
            else:
                previous_event = state.frame["D"] if state.frame else None
                state.ingest(item)
                if previous_event is None and state.frame:
                    last_requested_set = None
                    last_requested_slot = None
                if state.frame and previous_event is not None and state.frame["D"] is not None and state.frame["D"] < previous_event:
                    mirror.reset()
                    if readback:
                        readback.reset()
                    last_requested_set = None
                    last_requested_slot = None
                    if prediction is not None:
                        prediction.reset()
                if snapshot and state.frame and state.frame["D"] is not None and snapshot.seq != state.frame["D"]:
                    if state.frame["active"] is None:
                        mirror.warning = "FPGA telemetry is missing the active-order count"
                    else:
                        snapshot.start(state.frame["D"], state.frame["active"])
                        mirror.snapshot_ready = False
                        mirror.last_match = None
                        mirror.warning = None
                        readback.current.clear()
                        readback.verified.clear()
                        last_requested_set = None
                        last_requested_slot = None
        if snapshot and requests and not snapshot.complete:
            next_pair = snapshot.next_query()
            if next_pair:
                requests.put(next_pair)
        if requests and snapshot.complete and page == "hash" and selected_set != last_requested_set:
            requests.put(("H", selected_set))
            last_requested_set = selected_set
        if requests and snapshot.complete and page == "slots" and selected_slot != last_requested_slot:
            requests.put(("S", selected_slot))
            last_requested_slot = selected_slot
        draw(screen, state, mirror, page, axis, history_offset, selected_set,
             selected_slot, demo, relay, readback)
        screen.timeout(5 if snapshot and snapshot.seq is not None and not snapshot.complete else 100)
        key = screen.getch()
        if key == curses.KEY_MOUSE:
            try:
                _, mx, my, _, _ = curses.getmouse()
                if my == screen.getmaxyx()[0] - 2:
                    if page == "history":
                        key = ord("h") if 2 <= mx < 18 else ord("q") if 34 <= mx < 45 else -1
                    else:
                        key = -1
                        for label, action in (("Q Quit", "q"), ("1 Market", "1"),
                                              ("2 Orders", "2"), ("3 Hash", "3"),
                                              ("4 Events", "4"), ("5 Status", "5"),
                                              ("6 Levels", "6"), ("7 Slots", "7")):
                            start = 2 + NAV_FOOTER.find(label)
                            if start <= mx < start + len(label):
                                key = ord(action)
                                break
                elif page == "market" and my == screen.getmaxyx()[0] - 3:
                    t_start = 2 + MARKET_HINT.find("[T] Axis")
                    h_start = 2 + MARKET_HINT.find("[H] Quote history")
                    key = (ord("t") if t_start <= mx < t_start + len("[T] Axis") else
                           ord("h") if h_start <= mx < h_start + len("[H] Quote history") else -1)
            except curses.error:
                continue
        if key in (ord("q"), ord("Q")):
            return
        if key in (ord("t"), ord("T")):
            axis = "time" if axis == "events" else "events"
        if key in (ord("1"), ord("2"), ord("3"), ord("4"), ord("5"), ord("6"), ord("7")):
            page = {ord("1"): "market", ord("2"): "orders", ord("3"): "hash",
                    ord("4"): "events", ord("5"): "status", ord("6"): "levels",
                    ord("7"): "slots"}[key]
            history_offset = 0
        if key in (ord("h"), ord("H")):
            page = "market" if page == "history" else "history"
            history_offset = 0
        if page == "history" and key in (curses.KEY_DOWN, ord("j")):
            history_offset = min(max(0, len(state.points) - 1), history_offset + 1)
        if page == "history" and key in (curses.KEY_UP, ord("k")):
            history_offset = max(0, history_offset - 1)
        if page in ("orders", "events", "levels") and key in (curses.KEY_DOWN, ord("j")):
            limit = len(mirror.orders) if page == "orders" else len(mirror.events) if page == "events" else len({(o.side, o.price) for o in mirror.orders.values()})
            history_offset = min(max(0, limit - 1), history_offset + 1)
        if page in ("orders", "events", "levels") and key in (curses.KEY_UP, ord("k")):
            history_offset = max(0, history_offset - 1)
        if page == "hash":
            if key == curses.KEY_LEFT:
                selected_set = max(0, selected_set - 1)
            elif key == curses.KEY_RIGHT:
                selected_set = min(1023, selected_set + 1)
            elif key == curses.KEY_UP:
                selected_set = max(0, selected_set - 32)
            elif key == curses.KEY_DOWN:
                selected_set = min(1023, selected_set + 32)
            elif key in (ord("n"), ord("N")):
                occupied = sorted({order.set_index for order in mirror.orders.values()})
                if occupied:
                    selected_set = next((item for item in occupied if item > selected_set), occupied[0])
        if page == "slots":
            if key == curses.KEY_LEFT:
                selected_slot = max(0, selected_slot - 1)
            elif key == curses.KEY_RIGHT:
                selected_slot = min(2047, selected_slot + 1)
            elif key == curses.KEY_UP:
                selected_slot = max(0, selected_slot - 64)
            elif key == curses.KEY_DOWN:
                selected_slot = min(2047, selected_slot + 64)
            elif key in (ord("n"), ord("N")):
                occupied = sorted(order.slot for order in mirror.orders.values())
                if occupied:
                    selected_slot = next((item for item in occupied if item > selected_slot), occupied[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/ttyUSB1", help="physical FPGA UART port")
    parser.add_argument("--socket", default=f"/tmp/fpga-lob-uart-{os.getuid()}.sock", help="local relay path for order_journey.py")
    parser.add_argument("--demo", action="store_true", help="sample quotes; no board or sender relay")
    args = parser.parse_args()
    if not args.demo and serial is None:
        parser.error("pyserial is required (pip install pyserial)")
    stop = threading.Event()
    updates = queue.Queue()
    state = DashboardState()
    mirror = BookMirror() if args.demo else BoardStorageMirror()
    prediction = None if args.demo else BookMirror()
    readback_requests = None if args.demo else queue.Queue()
    port = listener = event_listener = None
    try:
        if args.demo:
            worker = threading.Thread(target=demo_worker, args=(updates, stop), daemon=True)
        else:
            port = serial.Serial(args.port, 115200, timeout=0.1)
            listener = socket_listener(args.socket)
            event_path = args.socket + ".events"
            if os.path.exists(event_path):
                os.unlink(event_path)
            event_listener = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            event_listener.bind(event_path)
            os.chmod(event_path, 0o600)
            event_listener.setblocking(False)
            worker = threading.Thread(target=serial_worker,
                                      args=(port, listener, updates, stop, event_listener, readback_requests), daemon=True)
        worker.start()
        curses.wrapper(run_ui, state, mirror, prediction, updates, stop, args.demo,
                       None if args.demo else args.socket, readback_requests)
    finally:
        stop.set()
        if 'worker' in locals():
            worker.join(timeout=1)
        if listener:
            listener.close()
            if os.path.exists(args.socket):
                os.unlink(args.socket)
        if event_listener:
            event_listener.close()
            if os.path.exists(args.socket + ".events"):
                os.unlink(args.socket + ".events")
        if port:
            port.close()


if __name__ == "__main__":
    main()
