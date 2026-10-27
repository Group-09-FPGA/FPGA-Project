#!/usr/bin/env python3
"""Narrated, one-message-at-a-time FPGA order-book demonstration."""

import argparse
import re
import socket
import struct
import sys
import time
from dataclasses import dataclass

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
                                    b"AAPL    ", event.price)
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
    print(f"  {number:02d}  ✓  {title:<23} {detail}", flush=True)


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


def read_until(port, expected, timeout, counter_target=None):
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
        if matches(frame, expected) and counters_ok:
            return frame, True
        if not frame["valid"] or frame["error"]:
            return frame, False
    return last, False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-ip", default="192.168.1.255")
    parser.add_argument("--port", type=int, default=10443)
    parser.add_argument("--uart-port", default="/dev/ttyUSB1")
    parser.add_argument("--interval", type=float, default=10.0, help="minimum seconds between orders")
    parser.add_argument("--count", type=int, default=10, help="orders to send; 0 means continuous")
    parser.add_argument("--advanced", action="store_true",
                        help="13-event A/F/E/C/X/U/D showcase; ends with an empty book")
    parser.add_argument("--interactive", action="store_true",
                        help="press Enter before each message; ignores --interval")
    parser.add_argument("--stage-delay", type=float, default=0.22)
    parser.add_argument("--timeout", type=float, default=3.0, help="UART confirmation timeout")
    parser.add_argument("--demo", action="store_true", help="clearly labelled simulated board, no network or UART")
    args = parser.parse_args(argv)
    if args.interval <= 0 or args.count < 0 or args.stage_delay < 0 or args.timeout <= 0:
        parser.error("interval and timeout must be positive; count and stage-delay cannot be negative")
    if not args.demo and serial is None:
        parser.error("pyserial is required for live board confirmation (pip install pyserial)")

    uart = None
    sock = None
    try:
        if not args.demo:
            uart = serial.Serial(args.uart_port, 115200, timeout=0.15)
            print("Waiting for an empty, valid FPGA book on UART...", flush=True)
            baseline, ok = read_until(uart, quote({}), 3.0)
            if not ok or baseline is None or any(baseline[key] is None for key in ("R", "U", "M", "I", "F", "D")):
                print(f"Board is not at an empty valid book (last frame: {baseline}). Reset FPGA, wait for initialization, then rerun.", file=sys.stderr)
                print("Live journey requires the newly built trace-enabled bitstream.", file=sys.stderr)
                return 2
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        mode = "SIMULATED WALKTHROUGH" if args.demo else "LIVE FPGA + UART CONFIRMATION"
        if args.advanced:
            mode += " · ADVANCED A/F/E/C/X/U/D"
        pacing = "press Enter for each message" if args.interactive else f"{args.interval:g}s minimum spacing"
        print(f"\n{'═' * 78}\n  NEXYS A7 · LIMIT ORDER BOOK · ORDER JOURNEY\n  {mode}  |  one ITCH message per UDP packet  |  {pacing}\n{'═' * 78}", flush=True)
        print("  Legend: ✓ host generated; FPGA stage counters and BBO come from board UART.\n", flush=True)
        book = {}
        index = 0
        while args.count == 0 or index < args.count:
            if args.interactive:
                input(f"\nPress Enter to send event {index + 1:03d} (Ctrl+C to stop)... ")
            started = time.monotonic()
            order = next_advanced_order(index) if args.advanced else next_order(index, book)
            seq = index + 1
            if args.advanced:
                packet = create_moldudp64_event(seq, order)
                apply_advanced_order(book, order)
            elif order.kind == "ADD":
                packet = create_moldudp64_add_order(seq, order.ref, order.side, order.shares, "AAPL", order.price)
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
            print(f"\n{'─' * 78}\n  ORDER {seq:03d}  ·  {operation}  ·  {'BUY' if order.side == 'B' else 'SELL'}  ·  ID {order.ref}")
            if order.kind in ("ADD", "A", "F"):
                print(f"  AAPL  |  {order.shares} shares  |  {money(order.price)}  |  ITCH type {'F' if order.kind == 'F' else 'A'}")
            elif args.advanced and order.kind == "U":
                print(f"  Replace ID {order.ref} → {order.new_ref}; {order.shares} shares at {money(order.price)}  |  ITCH type U")
            elif args.advanced and order.kind in ("E", "C", "X"):
                print(f"  Reduce ID {order.ref} by {order.shares} shares  |  ITCH type {order.kind}")
            else:
                print(f"  Remove order {order.ref} at {money(order.price)}  |  ITCH type D")
            print(f"  ITCH bytes: {payload.hex(' ')}", flush=True)
            print(f"  Mold header: {packet[:20].hex(' ')}  |  ITCH length prefix: {packet[20:22].hex(' ')}")
            if args.advanced:
                op = {"A": "ADD", "F": "ADD", "E": "EXECUTE", "C": "EXECUTE",
                      "X": "CANCEL", "D": "DELETE", "U": "REPLACE"}[order.kind]
                detail = f"OP={op} OID={order.ref} SEQ={seq}"
                if order.kind in ("A", "F"):
                    detail += f" SIDE={order.side} SHARES={order.shares} PRICE_INDEX={(order.price - 900000) // 1000}"
                elif order.kind == "U":
                    detail += f" NEW_OID={order.new_ref} SHARES={order.shares} PRICE_INDEX={(order.price - 900000) // 1000}"
                elif order.kind != "D":
                    detail += f" SHARES={order.shares}"
                print(f"  Expected canonical event: {detail}")
            elif order.kind == "ADD":
                price_index = (order.price - 900000) // 1000
                print(f"  Expected canonical event: OP=ADD SIDE={order.side} OID={order.ref} SHARES={order.shares} PRICE_INDEX={price_index} SEQ={seq}")
            else:
                print(f"  Expected canonical event: OP=DELETE OID={order.ref} SEQ={seq}")
            d = args.stage_delay
            stage(1, "Order ingestion", "one exchange order selected", d)
            stage(2, "ITCH encoding", f"type {chr(payload[0])}; message length {len(payload)} B; locate 1", d)
            stage(3, "MoldUDP64 envelope", f"session SESSION001; sequence {seq}; count 1; payload {len(packet)} B", d)
            stage(4, "UDP/IP handoff", f"sendto {args.target_ip}:{args.port}; UDP payload {len(packet)} B", d)
            if not args.demo:
                sent = sock.sendto(packet, (args.target_ip, args.port))
                if sent != len(packet):
                    raise OSError(f"short UDP send: {sent}/{len(packet)} bytes")
            print(f"  Expected BBO: BID {money(expected['bid'])} × {expected['bid_qty']}  |  ASK {money(expected['ask'])} × {expected['ask_qty']}  |  active {expected['active']}")
            if args.demo:
                stage(5, "Ethernet → RMII", "simulated accepted frame", d)
                stage(6, "Network parser", "simulated accepted UDP payload", d)
                stage(7, "Mold → ITCH", "simulated decoded order event", d)
                stage(8, "Event FIFO", "simulated crossing to core clock", d)
                stage(9, "LOB accelerator", "simulated order and BBO update", d)
                print("  BOARD RESULT: SIMULATED (no packet sent, no hardware observation)", flush=True)
            else:
                target = {key: baseline[key] + 1 for key in ("R", "U", "M", "I", "F", "D")}
                frame, ok = read_until(uart, expected, args.timeout, target)
                if not ok:
                    print(f"  BOARD RESULT: NOT CONFIRMED  |  last UART: {frame}", flush=True)
                    print("  Feed stopped to avoid a misleading demonstration. Check link/UART, reset FPGA and replay from sequence 1.", file=sys.stderr)
                    return 1
                stage(5, "Ethernet → RMII", f"board accepted frame #{frame['R']} (CRC checked)", d)
                stage(6, "Network parser", f"board accepted UDP packet #{frame['U']}", d)
                stage(7, "Mold → ITCH", f"Mold message #{frame['M']}; ITCH event #{frame['I']}", d)
                stage(8, "Event FIFO", f"canonical event accepted #{frame['F']}", d)
                storage = (f"hash set {hash_set(order.ref)} → {hash_set(order.new_ref)}"
                           if args.advanced and order.kind == "U"
                           else f"hash set {hash_set(order.ref)}")
                stage(9, "LOB accelerator", f"{storage}; event completed #{frame['D']}", d)
                print(f"  BOARD VERIFIED via UART: BID {money(frame['bid'])} × {frame['bid_qty']}  |  ASK {money(frame['ask'])} × {frame['ask_qty']}  |  active {frame['active']}  |  V=1 E=00", flush=True)
                print("  Board output mapping: LD3=book valid, LD4/5=bid/ask; seven-segment SW=00 bid, SW=01 ask; CPU MMIO and VGA read BBO.", flush=True)
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
