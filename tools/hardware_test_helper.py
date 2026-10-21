#!/usr/bin/env python3
"""
Hardware Bringup and Telemetry Monitor for Nexys A7-100T LOB System
===================================================================
Target: Digilent Nexys A7-100T (XC7A100T-1CSG324C)
UART:   115200 Baud, 8-N-1 (/dev/ttyUSB1)
UDP:    Port 10443 (MoldUDP64 / ITCH 5.0 Market Data)
"""

import sys
import time
import socket
import struct
import argparse

try:
    import serial
except ImportError:
    serial = None

def monitor_uart(port="/dev/ttyUSB1", baud=115200):
    if serial is None:
        print("[ERROR] pyserial is not installed. Run: uv pip install pyserial")
        sys.exit(1)

    print(f"[*] Opening serial monitor on {port} @ {baud} baud...")
    try:
        ser = serial.Serial(port, baud, timeout=0.5)
        print("[*] Connected! Waiting for LOB hardware telemetry streams...")
        print("    (Press Ctrl+C to stop)")
        while True:
            line = ser.readline()
            if line:
                try:
                    text = line.decode('utf-8', errors='replace').strip()
                    print(f"[{time.strftime('%H:%M:%S')}] {text}")
                except Exception as e:
                    print(f"[{time.strftime('%H:%M:%S')}] RAW: {line}")
    except KeyboardInterrupt:
        print("\n[*] Exiting UART monitor.")
    except Exception as e:
        print(f"[ERROR] Failed to read from {port}: {e}")

def create_moldudp64_add_order(seq_num, order_ref, side, shares, stock, price):
    """
    Constructs a MoldUDP64 frame containing a single NASDAQ ITCH 5.0 Add Order (Type 'A') message.
    """
    session = b"SESSION001"
    msg_count = 1
    mold_hdr = struct.pack(">10sQH", session, seq_num, msg_count)

    msg_len = 36
    msg_type = ord('A')
    locate = 1
    tracking = 0
    ts_bytes = b'\x00\x00\x00\x01\x23\x45'
    side_byte = ord(side)
    stock_bytes = stock.encode('ascii').ljust(8, b' ')

    itch_body = struct.pack(">HBHH", msg_len, msg_type, locate, tracking) + \
                ts_bytes + \
                struct.pack(">QBI8sI", order_ref, side_byte, shares, stock_bytes, price)

    return mold_hdr + itch_body

def create_moldudp64_order_pair(seq_num, bid_ref, bid_shares, bid_price,
                                ask_ref, ask_shares, ask_price):
    """Put two consecutive ITCH Add Orders in one MoldUDP64 datagram."""
    bid = create_moldudp64_add_order(seq_num, bid_ref, 'B', bid_shares, "AAPL", bid_price)
    ask = create_moldudp64_add_order(seq_num + 1, ask_ref, 'S', ask_shares, "AAPL", ask_price)
    return struct.pack(">10sQH", b"SESSION001", seq_num, 2) + bid[20:] + ask[20:]

def create_itch_replace_order(old_ref, new_ref, shares, price):
    """Length-prefixed ITCH 5.0 Replace Order message (35-byte body)."""
    body = struct.pack(">BHH6sQQII", ord('U'), 1, 0,
                       b'\x00\x00\x00\x01\x23\x45',
                       old_ref, new_ref, shares, price)
    return struct.pack(">H", len(body)) + body

def create_moldudp64_replace_pair(seq_num, old_bid_ref, new_bid_ref,
                                  bid_shares, bid_price, old_ask_ref,
                                  new_ask_ref, ask_shares, ask_price):
    """Replace the current bid and ask using two ITCH U messages."""
    return (struct.pack(">10sQH", b"SESSION001", seq_num, 2) +
            create_itch_replace_order(old_bid_ref, new_bid_ref,
                                      bid_shares, bid_price) +
            create_itch_replace_order(old_ask_ref, new_ask_ref,
                                      ask_shares, ask_price))

def send_market_orders(target_ip="192.168.1.10", target_port=10443, count=5):
    print(f"[*] Crafting and transmitting test market orders to {target_ip}:{target_port}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    # Send Add Order: Buy 500 shares AAPL @ $90.50 (905000 ticks)
    pkt = create_moldudp64_order_pair(1, 1001, 500, 905000,
                                      1002, 300, 910000)
    sock.sendto(pkt, (target_ip, target_port))
    print(" -> Sent BID: AAPL 500 @ 905000 (Ref 1001)")
    print(" -> Sent ASK: AAPL 300 @ 910000 (Ref 1002)")

    sock.close()
    print("[*] Injection complete. Observe board LEDs, 7-Segment display, and UART!")

def stream_market_orders(target_ip="192.168.1.10", target_port=10443, delay=0.5):
    import random
    print(f"[*] Continuously streaming live market orders to {target_ip}:{target_port}...")
    print("    (Press Ctrl+C to stop)")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    seq = 1
    ref = 2000
    bid_p = 920000
    ask_p = 960000
    old_bid_ref = None
    old_ask_ref = None

    try:
        while True:
            # Random walk aligned to hardware tick size (1000 ticks = $0.10)
            # The FPGA accepts prices >= 900000 and uses 1000-unit ticks.
            # Keep a broad, uncrossed range while every update moves visibly.
            bid_p = max(901000, min(940000, bid_p + random.choice([-10000, -7000, -5000, 5000, 7000, 10000])))
            ask_p = max(945000, min(980000, ask_p + random.choice([-10000, -7000, -5000, 5000, 7000, 10000])))

            first_seq = seq
            if old_bid_ref is None:
                pkt = create_moldudp64_order_pair(
                    seq, ref + 1, random.randint(100, 1000), bid_p,
                    ref + 2, random.randint(100, 1000), ask_p)
            else:
                pkt = create_moldudp64_replace_pair(
                    seq, old_bid_ref, ref + 1, random.randint(100, 1000), bid_p,
                    old_ask_ref, ref + 2, random.randint(100, 1000), ask_p)
            sock.sendto(pkt, (target_ip, target_port))
            seq += 2
            old_bid_ref, old_ask_ref = ref + 1, ref + 2
            ref += 2

            print(f"[{time.strftime('%H:%M:%S')}] Updated BBO -> Bid: ${bid_p/10000:.4f} | Ask: ${ask_p/10000:.4f} (Seq {first_seq}-{seq - 1})")
            time.sleep(delay)
    except KeyboardInterrupt:
        print("\n[*] Streaming stopped.")
    finally:
        sock.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Nexys A7-100T Hardware LOB Test Helper")
    parser.add_argument("--uart", action="store_true", help="Monitor UART telemetry on /dev/ttyUSB1")
    parser.add_argument("--inject", action="store_true", help="Inject sample MoldUDP64/ITCH packets")
    parser.add_argument("--stream", action="store_true", help="Continuously stream market orders (live feed)")
    parser.add_argument("--delay", type=float, default=0.5, help="Delay between stream updates in seconds (default: 0.5)")
    parser.add_argument("--ip", default="192.168.1.10", help="Target IP for Ethernet injection")
    parser.add_argument("--port", type=int, default=10443, help="Target UDP Port (default: 10443)")
    args = parser.parse_args()

    if args.uart:
        monitor_uart()
    elif args.inject:
        send_market_orders(target_ip=args.ip, target_port=args.port)
    elif args.stream:
        stream_market_orders(target_ip=args.ip, target_port=args.port, delay=args.delay)
    else:
        parser.print_help()
