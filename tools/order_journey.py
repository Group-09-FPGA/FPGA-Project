#!/usr/bin/env python3
"""Narrated, one-message-at-a-time FPGA order-book demonstration."""

import argparse
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

try:
    import serial
except ImportError:
    serial = None


FRAME = re.compile(
    r"\[BBO\]\s+B:([0-9A-Fa-f]{8})\s*\|\s*A:([0-9A-Fa-f]{8})"
    r"\s*\|\s*V:([01])\s*\|\s*E:([0-9A-Fa-f]{2})"
    r"(?:\s*\|\s*QB:([0-9A-Fa-f]{8})\s*\|\s*QA:([0-9A-Fa-f]{8})"
    r"\s*\|\s*N:([0-9A-Fa-f]{3}))?"
)

COLOR = sys.stdout.isatty() and "NO_COLOR" not in os.environ and os.environ.get("TERM") != "dumb"


def active_wifi_broadcast():
    """Return (interface, address, broadcast) for the connected IPv4 Wi-Fi LAN."""
    try:
        result = subprocess.run(
            ["ip", "-j", "-4", "addr", "show"],
            check=True, capture_output=True, text=True,
        )
        interfaces = json.loads(result.stdout)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Could not inspect network interfaces: {exc}") from exc

    candidates = []
    for interface in interfaces:
        name = interface.get("ifname", "")
        if (not os.path.isdir(f"/sys/class/net/{name}/wireless")
                or "LOWER_UP" not in interface.get("flags", [])):
            continue
        for address in interface.get("addr_info", []):
            if (address.get("family") == "inet"
                    and address.get("scope") == "global"
                    and address.get("broadcast")):
                candidates.append((name, address["local"], address["broadcast"]))

    if len(candidates) != 1:
        raise RuntimeError(
            f"Expected one connected Wi-Fi IPv4 broadcast address, found {len(candidates)}. "
            "Use --target-ip ADDRESS to choose the board-facing LAN broadcast."
        )
    return candidates[0]


def tint(value, code):
    return f"\033[{code}m{value}\033[0m" if COLOR else str(value)


def heading(title):
    print(f"\n  {tint(title, '1;36')}\n  {tint('─' * 74, '2')}", flush=True)


def field(label, value):
    print(f"    {tint(f'{label:<18}', '2')} {value}", flush=True)


def selector(key, label):
    return f"{tint(f'[{key}]', '1;36')} {label}"


def ask(label):
    return input(f"    {tint('›', '1;36')} {label}: ").strip()


def hint(message):
    print(f"    {tint('!', '1;33')} {message}")


def bbo(label, book):
    bid = f"BID {money(book['bid'])} × {book['bid_qty']}"
    ask = f"ASK {money(book['ask'])} × {book['ask_qty']}"
    print(f"    {tint(label, '1')}  {tint(bid, '1;32')}   │   {tint(ask, '1;35')}   │   active {book['active']}", flush=True)


def create_moldudp64_add_order(seq, order_ref, side, shares, stock, price):
    body = struct.pack(">BHH6sQBI8sI", ord("A"), 1, 0,
                       b"\x00\x00\x00\x01\x23\x45", order_ref, ord(side),
                       shares, stock.encode("ascii").ljust(8, b" "), price)
    return struct.pack(">10sQHH", b"SESSION001", seq, 1, len(body)) + body


def create_moldudp64_delete_order(seq, order_ref):
    body = struct.pack(">BHH6sQ", ord("D"), 1, 0,
                       b"\x00\x00\x00\x01\x23\x45", order_ref)
    return struct.pack(">10sQHH", b"SESSION001", seq, 1, len(body)) + body


def create_moldudp64_event(seq, event):
    """Encode one supported ITCH order event in one MoldUDP64 packet."""
    prefix = struct.pack(">BHH6sQ", ord(event.kind), 1, 0,
                         b"\x00\x00\x00\x01\x23\x45", event.ref)
    if event.kind in ("A", "F"):
        body = prefix + struct.pack(">BI8sI", ord(event.side), event.shares,
                                    b"LOBDEMO ", event.price)
        if event.kind == "F":
            body += b"DEMO"
    elif event.kind in ("E", "C"):
        body = prefix + struct.pack(">IQ", event.shares, seq)
        if event.kind == "C":
            body += struct.pack(">BI", ord("Y"), event.price)
    elif event.kind == "X":
        body = prefix + struct.pack(">I", event.shares)
    elif event.kind == "D":
        body = prefix
    elif event.kind == "U":
        body = prefix + struct.pack(">QII", event.new_ref, event.shares, event.price)
    else:
        raise ValueError(f"unsupported ITCH event: {event.kind}")
    return struct.pack(">10sQHH", b"SESSION001", seq, 1, len(body)) + body


@dataclass(frozen=True)
class Order:
    kind: str
    ref: int
    side: str
    shares: int
    price: int
    new_ref: int = 0


def parse_frame(line):
    match = FRAME.search(line)
    if not match:
        return None
    values = match.groups()
    frame = {
        "bid": int(values[0], 16), "ask": int(values[1], 16),
        "valid": values[2] == "1", "error": int(values[3], 16),
        "bid_qty": int(values[4], 16) if values[4] else None,
        "ask_qty": int(values[5], 16) if values[5] else None,
        "active": int(values[6], 16) if values[6] else None,
    }
    for key in ("R", "U", "M", "I", "F", "D"):
        counter = re.search(r"\|\s*" + key + r":([0-9A-Fa-f]{8})", line)
        frame[key] = int(counter.group(1), 16) if counter else None
    storage = re.search(r"\|\s*T:([0-9A-Fa-f]{79})(?=\s|$)", line)
    frame["storage_trace"] = storage.group(1) if storage else None
    for key in ("BASE", "TICK"):
        setting = re.search(r"\|\s*" + key + r":([0-9A-Fa-f]{8})", line)
        frame[key.lower()] = int(setting.group(1), 16) if setting else None
    return frame


def quote(book):
    bids = [order for order in book.values() if order.side == "B"]
    asks = [order for order in book.values() if order.side == "S"]
    bid = max((order.price for order in bids), default=0)
    ask = min((order.price for order in asks), default=0)
    return {
        "bid": bid, "ask": ask,
        "bid_qty": sum(order.shares for order in bids if order.price == bid),
        "ask_qty": sum(order.shares for order in asks if order.price == ask),
        "active": len(book), "valid": True, "error": 0,
    }


def matches(frame, expected):
    if frame is None or not frame["valid"] or frame["error"]:
        return False
    keys = ("bid", "ask", "bid_qty", "ask_qty", "active")
    return all(frame[key] is not None and frame[key] == expected[key] for key in keys)


def money(ticks):
    return "--" if not ticks else f"${ticks / 10000:.4f}"


def hash_set(order_ref):
    """Mirror lob_core.hash_oid's XOR of 10-bit order-ID slices."""
    return (
        (order_ref & 0x3ff) ^ ((order_ref >> 10) & 0x3ff) ^
        ((order_ref >> 20) & 0x3ff) ^ ((order_ref >> 30) & 0x3ff) ^
        ((order_ref >> 40) & 0x3ff) ^ ((order_ref >> 50) & 0x3ff) ^
        ((order_ref >> 60) & 0xf)
    )


def stage(number, title, detail, delay, animate=True):
    if animate and sys.stdout.isatty() and delay:
        for progress in ("▸··", "▸▸·", "▸▸▸"):
            print(f"\r  {number:02d}  {progress} {title:<23} {detail}", end="", flush=True)
            time.sleep(delay / 3)
        print("\r" + " " * 130 + "\r", end="", flush=True)
    print(f"    {tint(f'{number:02d}', '2')}  {tint('✓', '1;32')}  {title:<23} {tint(detail, '2')}", flush=True)


def next_order(index, book):
    # Four adds per side, then retire an older order before adding another.
    if index >= 8 and index % 3 == 2:
        side = "B" if (index // 3) % 2 == 0 else "S"
        candidates = [order for order in book.values() if order.side == side]
        if candidates:
            oldest = min(candidates, key=lambda order: order.ref)
            return Order("DELETE", oldest.ref, oldest.side, 0, oldest.price)
    side = "B" if index % 2 == 0 else "S"
    ref = 1000 + index
    price = (905000 + (index % 16) * 1000) if side == "B" else (950000 - (index % 16) * 1000)
    return Order("ADD", ref, side, 100 + (index % 4) * 100, price)


def next_advanced_order(index):
    """Exercise price priority, depth, partial/full reductions, and all order types."""
    ref = 1000 + (index // 13) * 10
    return (
        Order("A", ref, "B", 100, 905000),
        Order("F", ref + 1, "S", 200, 949000),
        Order("A", ref + 3, "B", 150, 907000),
        Order("A", ref + 4, "B", 50, 907000),
        Order("A", ref + 5, "S", 75, 948000),
        Order("E", ref + 3, "B", 40, 907000),
        Order("C", ref + 5, "S", 75, 948000),
        Order("X", ref + 4, "B", 20, 907000),
        Order("U", ref + 1, "S", 180, 947000, ref + 2),
        Order("D", ref + 3, "B", 0, 907000),
        Order("X", ref + 4, "B", 30, 907000),
        Order("D", ref + 2, "S", 0, 947000),
        Order("D", ref, "B", 0, 905000),
    )[index % 13]


def apply_advanced_order(book, event):
    if event.kind in ("A", "F"):
        book[event.ref] = event
    elif event.kind in ("E", "C", "X"):
        old = book[event.ref]
        if event.shares >= old.shares:
            del book[event.ref]
        else:
            book[event.ref] = Order(old.kind, old.ref, old.side,
                                    old.shares - event.shares, old.price)
    elif event.kind == "U":
        del book[event.ref]
        book[event.new_ref] = Order("A", event.new_ref, event.side,
                                    event.shares, event.price)
    elif event.kind == "D":
        del book[event.ref]


def prompt_number(label, low, high=None, default=None):
    while True:
        suffix = f" [{default}]" if default is not None else ""
        raw = ask(f"{label}{suffix}")
        if not raw and default is not None:
            return default
        try:
            value = int(raw)
        except ValueError:
            hint("Enter a whole number.")
            continue
        if value >= low and (high is None or value <= high):
            return value
        hint(f"Enter {low}–{high}." if high is not None else f"Enter at least {low}.")


def prompt_price(default):
    while True:
        raw = ask(f"Price in dollars [{default / 10000:.2f}]")
        try:
            cents = Decimal(raw) if raw else Decimal(default) / 10000
            ticks = cents * 10000
            if ticks == ticks.to_integral_value() and 900000 <= ticks <= 9091000 and ticks % 1000 == 0:
                return int(ticks)
        except InvalidOperation:
            pass
        hint("Use $90.00–$909.10 in $0.10 steps (example: 90.70).")


def choose_existing_order(book, display_only=False):
    if not book:
        hint("No active orders yet. Add an order first.")
        return None
    orders = sorted(book.values(), key=lambda order: (order.side, -order.price if order.side == "B" else order.price, order.ref))
    heading("ACTIVE ORDERS · REMAINING SHARES")
    for number, order in enumerate(orders, 1):
        side = tint('BUY ', '1;32') if order.side == 'B' else tint('SELL', '1;35')
        print(f"    {selector(number, f'ID {order.ref:<6}')}  {side}  {order.shares:>6} shares  {money(order.price)}")
    if display_only:
        return None
    print(f"\n    {selector(0, 'Back to actions')}")
    while True:
        raw = ask("Select order number")
        if raw.isdecimal() and 0 <= int(raw) <= len(orders):
            return orders[int(raw) - 1] if int(raw) else None
        hint(f"Choose 0–{len(orders)} from the list.")


def choose_interactive_order(book, used_refs):
    """Build one valid event from a guided terminal menu; None ends the session."""
    actions = {"1": "A", "2": "F", "3": "E", "4": "C", "5": "X", "6": "D", "7": "U"}
    while True:
        expected = quote(book)
        heading("INTERACTIVE ORDER MENU")
        bbo("Current", expected)
        print(f"\n    {selector(1, 'Add order'.ljust(20))} {selector(2, 'Attributed add')}")
        print(f"    {selector(3, 'Execute'.ljust(20))} {selector(4, 'Priced execute')}")
        print(f"    {selector(5, 'Cancel shares'.ljust(20))} {selector(6, 'Delete order')}")
        print(f"    {selector(7, 'Replace order'.ljust(20))} {selector(8, 'Show orders')}")
        print(f"    {selector(0, 'Finish')}\n")
        choice = ask("Choose action").lower()
        if choice in ("0", "q", "quit", "exit"):
            return None
        if choice == "8":
            choose_existing_order(book, display_only=True)
            continue
        kind = actions.get(choice, choice.upper() if choice.upper() in actions.values() else None)
        if kind is None:
            hint("Choose a menu number or ITCH letter A/F/E/C/X/D/U.")
            continue
        if kind in ("A", "F"):
            while True:
                side = ask("Side [B] Buy / [S] Sell").upper()
                if side in ("B", "S"):
                    break
                hint("Enter B or S.")
            shares = prompt_number("Shares", 1, 0xffffffff, 100)
            price = prompt_price(905000 if side == "B" else 949000)
            ref = max(used_refs, default=999) + 1
            event = Order(kind, ref, side, shares, price)
        else:
            old = choose_existing_order(book)
            if old is None:
                continue
            if kind in ("E", "C", "X"):
                shares = prompt_number("Shares to execute" if kind in ("E", "C") else "Shares to cancel", 1, old.shares, old.shares)
                price = prompt_price(old.price) if kind == "C" else old.price
                event = Order(kind, old.ref, old.side, shares, price)
            elif kind == "U":
                shares = prompt_number("New remaining shares", 1, 0xffffffff, old.shares)
                price = prompt_price(old.price)
                event = Order(kind, old.ref, old.side, shares, price, max(used_refs, default=999) + 1)
            else:
                event = Order(kind, old.ref, old.side, 0, old.price)
        summary = f"{kind} · ID {event.ref} · {'BUY' if event.side == 'B' else 'SELL'}"
        if kind == "U":
            summary += f" → ID {event.new_ref} · {event.shares} shares at {money(event.price)}"
        elif kind in ("A", "F", "C"):
            summary += f" · {event.shares} shares at {money(event.price)}"
        elif kind in ("E", "X"):
            summary += f" · {event.shares} shares"
        heading("REVIEW ORDER")
        field("Ready to send", summary)
        print(f"\n    {selector('Enter', 'Send')}   {selector('b', 'Back to actions')}   {selector('q', 'Finish')}")
        confirm = ask("Confirm").lower()
        if confirm in ("q", "quit", "exit"):
            return None
        if confirm in ("b", "back"):
            continue
        if confirm:
            hint("Press Enter, b, or q.")
            continue
        return event


def read_until(port, expected, timeout, counter_target=None, event_ref=None):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        raw = port.readline()
        if not raw:
            continue
        frame = parse_frame(raw.decode("ascii", errors="replace"))
        if frame is None:
            continue
        last = frame
        counters_ok = counter_target is None or all(
            frame[key] is not None and frame[key] >= counter_target[key]
            for key in counter_target
        )
        quote_ok = (frame["valid"] and frame["error"] == 0) if expected is None else matches(frame, expected)
        trace = frame.get("storage_trace")
        event_ok = event_ref is None or (trace is not None and
                    ((int(trace, 16) >> 247) & ((1 << 64) - 1)) == event_ref)
        if quote_ok and counters_ok and event_ok:
            return frame, True
        if not frame["valid"] or frame["error"]:
            return frame, False
    return last, False


class SocketLineReader:
    """Read FPGA UART lines relayed by the display-only dashboard."""

    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(0.15)
        try:
            self.sock.connect(path)
        except OSError:
            self.sock.close()
            raise
        self.buffer = bytearray()

    def readline(self):
        while True:
            end = self.buffer.find(b"\n")
            if end >= 0:
                line = bytes(self.buffer[:end + 1])
                del self.buffer[:end + 1]
                return line
            try:
                chunk = self.sock.recv(4096)
            except socket.timeout:
                return b""
            if not chunk:
                raise OSError("UART dashboard relay disconnected")
            self.buffer.extend(chunk)

    def close(self):
        self.sock.close()


def publish_confirmed_event(socket_path, event, sequence, frame):
    """Give the dashboard a host-side event record after FPGA confirmation."""
    payload = json.dumps({
        "kind": event.kind, "ref": event.ref, "side": event.side,
        "shares": event.shares, "price": event.price, "new_ref": event.new_ref,
        "seq": sequence, "board": {key: frame[key] for key in
                                    ("bid", "ask", "bid_qty", "ask_qty", "active", "D")},
    }).encode("ascii")
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as event_sock:
        event_sock.sendto(payload, socket_path + ".events")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-ip", metavar="ADDRESS",
                        help="IPv4 destination (default: active Wi-Fi broadcast address)")
    parser.add_argument("--port", type=int, default=10443)
    parser.add_argument("--uart-port", default="/dev/ttyUSB1")
    parser.add_argument("--uart-socket", metavar="PATH",
                        help="read board UART from a running dashboard relay instead of opening --uart-port")
    parser.add_argument("--interval", type=float, default=5.5, help="minimum seconds between orders")
    parser.add_argument("--count", type=int, default=None, help="orders to send; 0 means continuous (interactive defaults to unlimited)")
    parser.add_argument("--advanced", action="store_true",
                        help="13-event A/F/E/C/X/U/D showcase; ends with an empty book")
    parser.add_argument("--mixed-input", action="store_true",
                        help="allow board orders; confirm network counters and valid FPGA state instead of host-only book totals")
    parser.add_argument("--interactive", action="store_true",
                        help="choose each action and its fields from prompts; ignores --interval")
    parser.add_argument("--stage-delay", type=float, default=0.22)
    parser.add_argument("--timeout", type=float, default=3.0, help="UART confirmation timeout")
    parser.add_argument("--demo", action="store_true", help="clearly labelled simulated board, no network or UART")
    args = parser.parse_args(argv)
    if args.count is None:
        args.count = 0 if args.interactive else (13 if args.advanced else 10)
    if args.interval <= 0 or args.count < 0 or args.stage_delay < 0 or args.timeout <= 0:
        parser.error("interval and timeout must be positive; count and stage-delay cannot be negative")
    if not args.demo and not args.uart_socket and serial is None:
        parser.error("pyserial is required for live board confirmation (pip install pyserial)")
    if args.target_ip is None:
        if args.demo:
            args.target_ip = "auto"
        else:
            try:
                wifi_interface, wifi_address, args.target_ip = active_wifi_broadcast()
            except RuntimeError as exc:
                parser.error(str(exc))
            print(f"Wi-Fi {wifi_interface} ({wifi_address}) → broadcast {args.target_ip}:{args.port}", flush=True)

    uart = None
    sock = None
    try:
        if not args.demo:
            uart = (SocketLineReader(args.uart_socket) if args.uart_socket
                    else serial.Serial(args.uart_port, 115200, timeout=0.15))
            print("Waiting for a valid FPGA book on UART..." if args.mixed_input else
                  "Waiting for an empty, valid FPGA book on UART...", flush=True)
            baseline, ok = read_until(uart, None if args.mixed_input else quote({}), 3.0)
            if not ok or baseline is None or any(baseline[key] is None for key in ("R", "U", "M", "I", "F", "D")):
                print(f"Board is not at an empty valid book (last frame: {baseline}). Reset FPGA, wait for initialization, then rerun.", file=sys.stderr)
                print("Live journey requires the newly built trace-enabled bitstream.", file=sys.stderr)
                return 2
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        mode = "SIMULATED WALKTHROUGH" if args.demo else "LIVE FPGA + UART CONFIRMATION"
        if args.advanced or args.interactive:
            mode += " · ADVANCED A/F/E/C/X/U/D"
        pacing = "choose each event" if args.interactive else f"{args.interval:g}s minimum spacing"
        print(f"\n{'═' * 78}\n  NEXYS A7 · LIMIT ORDER BOOK · ORDER JOURNEY\n  {mode}  |  one ITCH message per UDP packet  |  {pacing}\n{'═' * 78}", flush=True)
        legend = ("SIMULATED stages and BBO; no hardware is contacted."
                  if args.demo else "✓ host generated; FPGA stage counters and BBO come from board UART.")
        print(f"  Legend: {legend}\n", flush=True)
        book = {}
        used_refs = set()
        index = 0
        while args.count == 0 or index < args.count:
            if args.interactive:
                order = choose_interactive_order(book, used_refs)
                if order is None:
                    break
            else:
                order = next_advanced_order(index) if args.advanced else next_order(index, book)
            started = time.monotonic()
            seq = baseline["M"] + 1 if args.mixed_input and not args.demo else index + 1
            advanced_event = args.advanced or args.interactive
            if advanced_event:
                packet = create_moldudp64_event(seq, order)
                apply_advanced_order(book, order)
                used_refs.add(order.new_ref if order.kind == "U" else order.ref)
            elif order.kind == "ADD":
                packet = create_moldudp64_add_order(seq, order.ref, order.side, order.shares, "LOBDEMO", order.price)
                book[order.ref] = order
            else:
                packet = create_moldudp64_delete_order(seq, order.ref)
                del book[order.ref]
            expected = quote(book)
            payload = packet[22:]
            operation = {
                "A": "ADD", "F": "ADD WITH ATTRIBUTION", "E": "EXECUTE",
                "C": "EXECUTE WITH PRICE", "X": "CANCEL", "D": "DELETE", "U": "REPLACE",
            }.get(order.kind, order.kind)
            print(f"\n{tint('═' * 78, '1;36')}\n  {tint(f'ORDER {seq:03d}', '1;36')}  ·  {tint(operation, '1')}  ·  {tint('BUY' if order.side == 'B' else 'SELL', '1;32' if order.side == 'B' else '1;35')}  ·  ID {order.ref}")
            heading("ORDER DETAILS")
            if order.kind in ("ADD", "A", "F"):
                print(f"  Book locate 1  |  {order.shares} shares  |  {money(order.price)}  |  ITCH type {'F' if order.kind == 'F' else 'A'}")
            elif advanced_event and order.kind == "U":
                print(f"  Replace ID {order.ref} → {order.new_ref}; {order.shares} shares at {money(order.price)}  |  ITCH type U")
            elif advanced_event and order.kind in ("E", "C", "X"):
                detail = f"  Reduce ID {order.ref} by {order.shares} shares"
                if order.kind == "C":
                    detail += f"; execution price {money(order.price)} (resting book price unchanged)"
                print(f"{detail}  |  ITCH type {order.kind}")
            else:
                print(f"  Remove order {order.ref} at {money(order.price)}  |  ITCH type D")
            heading("PACKET ON THE WIRE")
            field("ITCH bytes", payload.hex(' '))
            field("Mold header", packet[:20].hex(' '))
            field("Length prefix", packet[20:22].hex(' '))
            if advanced_event:
                op = {"A": "ADD", "F": "ADD", "E": "EXECUTE", "C": "EXECUTE",
                      "X": "CANCEL", "D": "DELETE", "U": "REPLACE"}[order.kind]
                detail = f"OP={op} OID={order.ref} SEQ={seq}"
                if order.kind in ("A", "F"):
                    detail += f" SIDE={order.side} SHARES={order.shares} PRICE_INDEX={(order.price - 900000) // 1000}"
                elif order.kind == "U":
                    detail += f" NEW_OID={order.new_ref} SHARES={order.shares} PRICE_INDEX={(order.price - 900000) // 1000}"
                elif order.kind != "D":
                    detail += f" SHARES={order.shares}"
                field("Canonical event", detail)
            elif order.kind == "ADD":
                price_index = (order.price - 900000) // 1000
                field("Canonical event", f"OP=ADD SIDE={order.side} OID={order.ref} SHARES={order.shares} PRICE_INDEX={price_index} SEQ={seq}")
            else:
                field("Canonical event", f"OP=DELETE OID={order.ref} SEQ={seq}")
            heading("ORDER JOURNEY")
            d = args.stage_delay
            stage(1, "Order ingestion", "one exchange order selected", d)
            stage(2, "ITCH encoding", f"type {chr(payload[0])}; message length {len(payload)} B; locate 1", d)
            stage(3, "MoldUDP64 envelope", f"session SESSION001; sequence {seq}; count 1; payload {len(packet)} B", d)
            stage(4, "UDP/IP handoff", f"sendto {args.target_ip}:{args.port}; UDP payload {len(packet)} B", d)
            if not args.demo:
                sent = sock.sendto(packet, (args.target_ip, args.port))
                if sent != len(packet):
                    raise OSError(f"short UDP send: {sent}/{len(packet)} bytes")
            heading("HOST ORDER SUBSET" if args.mixed_input else "EXPECTED BOOK")
            bbo("Host subset" if args.mixed_input else "Expected", expected)
            heading("FPGA PATH")
            if args.demo:
                stage(5, "Ethernet → RMII", "simulated accepted frame", d)
                stage(6, "Network parser", "simulated accepted UDP payload", d)
                stage(7, "Mold → ITCH", "simulated decoded order event", d)
                stage(8, "Event FIFO", "simulated crossing to core clock", d)
                stage(9, "LOB accelerator", "simulated order and BBO update", d)
                heading("RESULT")
                print(f"    {tint('SIMULATED', '1;33')}  No packet sent; no hardware observation.\n", flush=True)
            else:
                target = {key: baseline[key] + 1 for key in ("R", "U", "M", "I", "F", "D")}
                frame, ok = read_until(uart, None if args.mixed_input else expected,
                                       args.timeout, target, order.ref if args.mixed_input else None)
                if not ok:
                    heading("RESULT")
                    print(f"    {tint('NOT CONFIRMED', '1;31')}  Last UART: {frame}", flush=True)
                    print("  Feed stopped to avoid a misleading demonstration. Check link/UART, reset FPGA and replay from sequence 1.", file=sys.stderr)
                    return 1
                stage(5, "Ethernet → RMII", f"board accepted frame #{frame['R']} (CRC checked)", d)
                stage(6, "Network parser", f"board accepted UDP packet #{frame['U']}", d)
                stage(7, "Mold → ITCH", f"Mold message #{frame['M']}; ITCH event #{frame['I']}", d)
                stage(8, "Event FIFO", f"canonical event accepted #{frame['F']}", d)
                storage = (f"hash set {hash_set(order.ref)} → {hash_set(order.new_ref)}"
                           if advanced_event and order.kind == "U"
                           else f"hash set {hash_set(order.ref)}")
                stage(9, "LOB accelerator", f"{storage}; event completed #{frame['D']}", d)
                heading("RESULT")
                bbo("Board UART", frame)
                print(f"    {tint('NETWORK ACCEPTED / FPGA VALID' if args.mixed_input else 'BOARD VERIFIED', '1;32')}  V=1 E=00", flush=True)
                field("Board outputs", "LD3=valid, LD4/5=bid/ask; seven-segment SW=00 bid, SW=01 ask")
                field("Other readers", "CPU MMIO and VGA read BBO")
                if args.uart_socket and not args.mixed_input:
                    try:
                        publish_confirmed_event(args.uart_socket, order, seq, frame)
                    except OSError as exc:
                        print(f"    Dashboard event mirror unavailable: {exc}", file=sys.stderr)
                baseline = frame
            index += 1
            if not args.interactive and (args.count == 0 or index < args.count):
                remaining = args.interval - (time.monotonic() - started)
                if remaining > 0:
                    print(f"  Next order in {remaining:.1f}s  (Ctrl+C to stop)", flush=True)
                    time.sleep(remaining)
        print(f"\nCompleted {index} single-order journeys.")
        return 0
    except KeyboardInterrupt:
        print("\nStopped by user.")
        return 130
    except EOFError:
        print("\nNo terminal input available; interactive demo stopped.", file=sys.stderr)
        return 1
    except (OSError, ValueError) as exc:
        print(f"Demo stopped: {exc}", file=sys.stderr)
        return 1
    finally:
        if uart is not None:
            uart.close()
        if sock is not None:
            sock.close()


if __name__ == "__main__":
    sys.exit(main())
