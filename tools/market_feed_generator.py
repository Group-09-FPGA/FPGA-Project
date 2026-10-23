#!/usr/bin/env python3
import socket
import time
import random
import struct

def create_moldudp64_add_order(seq_num, order_ref, side, shares, stock, price):
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

def create_moldudp64_cancel_order(seq_num, order_ref, shares):
    session = b"SESSION001"
    mold_hdr = struct.pack(">10sQH", session, seq_num, 1)
    # ITCH Type 'D' (Delete order): len=19, type='D', locate=1, tracking=0, ts(6B), order_ref(8B)
    body = struct.pack(">BHH6sQ", ord('D'), 1, 0, b'\x00\x00\x00\x01\x23\x45', order_ref)
    return mold_hdr + struct.pack(">H", len(body)) + body

def create_moldudp64_order_pair(seq_num, bid_ref, bid_shares, bid_price,
                                ask_ref, ask_shares, ask_price):
    bid = create_moldudp64_add_order(seq_num, bid_ref, 'B', bid_shares, "AAPL", bid_price)
    ask = create_moldudp64_add_order(seq_num + 1, ask_ref, 'S', ask_shares, "AAPL", ask_price)
    return struct.pack(">10sQH", b"SESSION001", seq_num, 2) + bid[20:] + ask[20:]

def main():
    target_ip = "192.168.1.10"
    target_port = 10443
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    seq = 1
    ref = 1000
    bid = 905000
    ask = 945000
    active_bids = []
    active_asks = []

    print("==========================================================")
    print("   LOB Live Market Feed Generator (Streaming to FPGA)")
    print("   Target: 192.168.1.10:10443 (MoldUDP64 / ITCH 5.0)")
    print("==========================================================")

    while True:
        # Move bid between $90.00 and $93.00
        bid = max(901000, min(930000, bid + random.choice([-2000, -1000, 1000, 2000])))
        # Move ask between $94.00 and $97.00
        ask = max(940000, min(970000, ask + random.choice([-2000, -1000, 1000, 2000])))

        # 1. Clean up old orders to keep depth healthy
        if len(active_bids) > 6:
            old_ref = active_bids.pop(0)
            pkt = create_moldudp64_cancel_order(seq, old_ref, 0)
            sock.sendto(pkt, (target_ip, target_port))
            seq += 1

        if len(active_asks) > 6:
            old_ref = active_asks.pop(0)
            pkt = create_moldudp64_cancel_order(seq, old_ref, 0)
            sock.sendto(pkt, (target_ip, target_port))
            seq += 1

        # 2. Inject new best bid & ask pair
        b_ref = ref
        a_ref = ref + 1
        ref += 2
        active_bids.append(b_ref)
        active_asks.append(a_ref)

        pkt = create_moldudp64_order_pair(seq, b_ref, random.randint(100, 500), bid,
                                          a_ref, random.randint(100, 500), ask)
        sock.sendto(pkt, (target_ip, target_port))
        seq += 2

        print(f"[{time.strftime('%H:%M:%S')}] Live Feed (Seq {seq-2:4d}) -> Best Bid: ${bid/10000:7.4f} | Best Ask: ${ask/10000:7.4f} | Spread: ${(ask-bid)/10000:.4f}")
        time.sleep(0.7)

if __name__ == "__main__":
    main()
