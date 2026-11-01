#!/usr/bin/env python3
"""Display-only UART dashboard with a local relay for order_journey.py.

Run this first, then run order_journey.py with the shown --uart-socket path.
The dashboard never sends Ethernet packets or injects FPGA orders.
"""

import argparse
import curses
import os
import queue
import socket
import threading
import time
from collections import deque
from dataclasses import dataclass

from order_journey import parse_frame, serial


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


def serial_worker(port, listener, updates, stop):
    clients = []
    try:
        while not stop.is_set():
            if listener:
                try:
                    while True:
                        client, _ = listener.accept()
                        client.settimeout(0.05)
                        clients.append(client)
                except BlockingIOError:
                    pass
            raw = port.readline()
            if not raw:
                continue
            updates.put(raw)
            for client in clients[:]:
                try:
                    client.sendall(raw)
                except OSError:
                    clients.remove(client)
                    client.close()
    except Exception as exc:
        updates.put(exc)
    finally:
        for client in clients:
            client.close()


def demo_worker(updates, stop):
    sequence = [(0, 0), (905000, 0), (905000, 949000),
                (907000, 949000), (907000, 948000), (906000, 948000)]
    for n, (bid, ask) in enumerate(sequence):
        if stop.is_set():
            return
        qty_b = 150 if bid else 0
        qty_a = 75 if ask else 0
        updates.put(f"[BBO] B:{bid:08X} | A:{ask:08X} | V:1 | E:00 | QB:{qty_b:08X} | QA:{qty_a:08X} | N:{min(n, 4):03X} | R:{n:08X} | U:{n:08X} | M:{n:08X} | I:{n:08X} | F:{n:08X} | D:{n:08X}\n".encode())
        stop.wait(1.5)


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
    axis_values = [p.event if axis == "events" else p.when for p in selected]
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
    start = str(first.event) if axis == "events" else time.strftime("%H:%M:%S", time.localtime(first.when))
    end = str(last.event) if axis == "events" else time.strftime("%H:%M:%S", time.localtime(last.when))
    axis_label = f"{start} ─────── {end}  {axis}"
    put(screen, y + rows + 1, left, axis_label[:max(0, x0 + width - left - 1)], curses.A_DIM)


def draw(screen, state, axis, history, history_offset, demo, relay):
    screen.erase()
    height, width = screen.getmaxyx()
    if height < 27 or width < 70:
        put(screen, 1, 2, "Enlarge terminal to at least 70 × 27. Press Q to quit.")
        screen.refresh()
        return
    curses.curs_set(0)
    if history:
        put(screen, 0, 2, "CONFIRMED QUOTE HISTORY", curses.A_BOLD)
        put(screen, 1, 2, "Board event       Received        Best bid       Best ask", curses.A_DIM)
        entries = list(reversed(state.points))
        visible = max(1, height - 5)
        for row, point in enumerate(entries[history_offset:history_offset + visible], 2):
            put(screen, row, 2, f"#{point.event:<15} {time.strftime('%H:%M:%S', time.localtime(point.when)):<15} {money(point.bid):<14} {money(point.ask)}")
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
    put(screen, height - 3, 2, "Green = rising · Red = falling · Grey = unchanged", curses.A_DIM)
    put(screen, height - 2, 2, "[T] Time / event axis   [H] Quote history   [Q] Quit", curses.A_REVERSE)
    if relay:
        put(screen, height - 1, 2, f"Sender UART relay: {relay}", curses.A_DIM)
    screen.refresh()


def run_ui(screen, state, updates, stop, demo, relay):
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_WHITE, -1)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_RED, -1)
    curses.mousemask(curses.BUTTON1_CLICKED)
    screen.timeout(100)
    axis = "events"
    history = False
    history_offset = 0
    while True:
        while True:
            try:
                item = updates.get_nowait()
            except queue.Empty:
                break
            if isinstance(item, Exception):
                raise item
            state.ingest(item)
        draw(screen, state, axis, history, history_offset, demo, relay)
        key = screen.getch()
        if key == curses.KEY_MOUSE:
            try:
                _, mx, my, _, _ = curses.getmouse()
                if my == screen.getmaxyx()[0] - 2:
                    if history:
                        key = ord("h") if 2 <= mx < 18 else ord("q") if 34 <= mx < 45 else -1
                    else:
                        key = (ord("t") if 2 <= mx < 25 else
                               ord("h") if 25 <= mx < 47 else
                               ord("q") if 47 <= mx < 58 else -1)
            except curses.error:
                continue
        if key in (ord("q"), ord("Q")):
            return
        if key in (ord("t"), ord("T")):
            axis = "time" if axis == "events" else "events"
        if key in (ord("h"), ord("H")):
            history = not history
            history_offset = 0
        if history and key in (curses.KEY_DOWN, ord("j")):
            history_offset = min(max(0, len(state.points) - 1), history_offset + 1)
        if history and key in (curses.KEY_UP, ord("k")):
            history_offset = max(0, history_offset - 1)


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
    port = listener = None
    try:
        if args.demo:
            worker = threading.Thread(target=demo_worker, args=(updates, stop), daemon=True)
        else:
            port = serial.Serial(args.port, 115200, timeout=0.1)
            listener = socket_listener(args.socket)
            worker = threading.Thread(target=serial_worker, args=(port, listener, updates, stop), daemon=True)
        worker.start()
        curses.wrapper(run_ui, state, updates, stop, args.demo, None if args.demo else args.socket)
    finally:
        stop.set()
        if 'worker' in locals():
            worker.join(timeout=1)
        if listener:
            listener.close()
            if os.path.exists(args.socket):
                os.unlink(args.socket)
        if port:
            port.close()


if __name__ == "__main__":
    main()
