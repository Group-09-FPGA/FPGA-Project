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
                struct.pack(">QBIsI", order_ref, side_byte, shares, stock_bytes, price)
    
    return mold_hdr + itch_body

def send_market_orders(target_ip="192.168.1.10", target_port=10443, count=5):
    print(f"[*] Crafting and transmitting test market orders to {target_ip}:{target_port}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Send Add Order: Buy 500 shares AAPL @ $90.50 (905000 ticks)
    pkt1 = create_moldudp64_add_order(1, 1001, 'B', 500, "AAPL", 905000)
    sock.sendto(pkt1, (target_ip, target_port))
    print(" -> Sent BID: AAPL 500 @ 905000 (Ref 1001)")
    time.sleep(0.05)

    # Send Add Order: Sell 300 shares AAPL @ $91.00 (910000 ticks)
    pkt2 = create_moldudp64_add_order(2, 1002, 'S', 300, "AAPL", 910000)
    sock.sendto(pkt2, (target_ip, target_port))
    print(" -> Sent ASK: AAPL 300 @ 910000 (Ref 1002)")
    time.sleep(0.05)

    sock.close()
    print("[*] Injection complete. Observe board LEDs, 7-Segment display, and UART!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Nexys A7-100T Hardware LOB Test Helper")
    parser.add_argument("--uart", action="store_true", help="Monitor UART telemetry on /dev/ttyUSB1")
    parser.add_argument("--inject", action="store_true", help="Inject sample MoldUDP64/ITCH packets")
    parser.add_argument("--ip", default="192.168.1.10", help="Target IP for Ethernet injection")
    parser.add_argument("--port", type=int, default=10443, help="Target UDP Port (default: 10443)")
    args = parser.parse_args()

    if args.uart:
        monitor_uart()
    elif args.inject:
        send_market_orders(target_ip=args.ip, target_port=args.port)
    else:
        parser.print_help()
