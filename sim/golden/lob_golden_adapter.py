#!/usr/bin/env python3
"""
lob_golden_adapter.py - Translates Python golden model vectors to hardware canonical 256-bit events.
Target: Artix-7 LOB Accelerator (Phase 1)
Event layout: rtl/lob/lob_defines.vh.
"""

import sys
import os
import json
import argparse

DEFAULT_PRICE_BASE = 900000  # $90.0000
DEFAULT_TICK       = 1000    # $0.1000 tick

OP_MAP = {
    "AddOrderEvent": 1,
    "ExecuteOrderEvent": 2,
    "CancelOrderEvent": 3,
    "DeleteOrderEvent": 4,
    "ReplaceOrderEvent": 5,
}

SIDE_MAP = {
    "BUY": 0,
    "SELL": 1,
}

def pack_canonical_event(ver=1, op=1, side=0, oid=0, noid=0, shares=0, pidx=0, oow=0, seq=0):
    """
    Packs fields into a 256-bit canonical event integer matching lob_defines.vh:
    [255:252] ver (4b)
    [251:248] op (4b)
    [247]     side (1b)
    [246:240] rsvd1 (7b) = 0
    [239:176] oid (64b)
    [175:112] noid (64b)
    [111:80]  shares (32b)
    [79:67]   pidx (13b)
    [66]      oow (1b)
    [65:64]   rsvd2 (2b) = 0
    [63:32]   seq (32b)
    [31:0]    rsvd3 (32b) = 0
    """
    evt = 0
    evt |= (ver & 0xF) << 252
    evt |= (op & 0xF) << 248
    evt |= (side & 0x1) << 247
    # rsvd1 [246:240] = 0
    evt |= (oid & 0xFFFFFFFFFFFFFFFF) << 176
    evt |= (noid & 0xFFFFFFFFFFFFFFFF) << 112
    evt |= (shares & 0xFFFFFFFF) << 80
    evt |= (pidx & 0x1FFF) << 67
    evt |= (oow & 0x1) << 66
    # rsvd2 [65:64] = 0
    evt |= (seq & 0xFFFFFFFF) << 32
    # rsvd3 [31:0] = 0
    return evt

def convert_vector_file(input_path, output_json, output_txt, price_base=DEFAULT_PRICE_BASE, tick=DEFAULT_TICK):
    with open(input_path, "r") as f:
        vectors = json.load(f)

    converted = []
    txt_lines = []

    for item in vectors:
        step_idx = item["step_index"]
        ev = item["input_event"]
        exp = item["expected_state"]
        ev_type = ev.get("type")

        if ev_type not in OP_MAP:
            # Unprocessed events like TradeEvent, BrokenTradeEvent in LOB book
            continue

        op = OP_MAP[ev_type]
        side = SIDE_MAP.get(ev.get("side", ""), 0) if op == 1 else 0

        oid = ev.get("order_id", 0)
        noid = ev.get("new_order_id", 0)
        if op == 5:
            oid = ev.get("old_order_id", 0)

        shares = 0
        if op == 1:
            shares = ev.get("quantity", 0)
        elif op == 2:
            shares = ev.get("executed_qty", ev.get("executed_quantity", 0))
        elif op == 3:
            shares = ev.get("canceled_qty", ev.get("canceled_quantity", 0))
        elif op == 4:
            shares = 0  # DELETE requires shares == 0
        elif op == 5:
            shares = ev.get("new_quantity", ev.get("new_qty", 0))

        raw_price = ev.get("price", 0) if op == 1 else (ev.get("new_price", 0) if op == 5 else 0)

        pidx = 0
        oow = 0
        if op in (1, 5):
            if raw_price < price_base or ((raw_price - price_base) % tick != 0):
                oow = 1
                pidx = 0
            else:
                quotient = (raw_price - price_base) // tick
                if quotient >= 8192:
                    oow = 1
                    pidx = 0
                else:
                    pidx = quotient

        packed_int = pack_canonical_event(
            ver=1,
            op=op,
            side=side,
            oid=oid,
            noid=noid,
            shares=shares,
            pidx=pidx,
            oow=oow,
            seq=step_idx
        )

        hex_str = f"{packed_int:064x}"

        record = {
            "step_index": step_idx,
            "op_name": ev_type,
            "raw_hex": hex_str,
            "expected_success": exp.get("success", True),
            "expected_active_orders": exp.get("active_orders", 0),
            "expected_best_bid_price": exp.get("best_bid_price", 0),
            "expected_best_bid_qty": exp.get("best_bid_qty", 0),
            "expected_best_ask_price": exp.get("best_ask_price", 0),
            "expected_best_ask_qty": exp.get("best_ask_qty", 0),
            "expected_book_valid": exp.get("book_valid", True)
        }
        converted.append(record)

        # Formatted line for easy Verilog $fscanf reading:
        # hex_str exp_success exp_active exp_bid_p exp_bid_q exp_ask_p exp_ask_q
        txt_line = (f"{hex_str} {1 if record['expected_success'] else 0} "
                    f"{record['expected_active_orders']} {record['expected_best_bid_price']} "
                    f"{record['expected_best_bid_qty']} {record['expected_best_ask_price']} "
                    f"{record['expected_best_ask_qty']}")
        txt_lines.append(txt_line)

    with open(output_json, "w") as f:
        json.dump(converted, f, indent=2)

    with open(output_txt, "w") as f:
        f.write("\n".join(txt_lines) + "\n")

    print(f"Successfully converted {len(converted)} events.")
    print(f"JSON output: {output_json}")
    print(f"Verilog vector file: {output_txt}")

def main():
    parser = argparse.ArgumentParser(description="LOB Golden Vector Adapter")
    parser.add_argument("--input", default="/home/ronit/Documents/antigravity/intelligent-planck/testbench_vectors.json")
    parser.add_argument("--out-json", default="sim/golden/golden_vectors.json")
    parser.add_argument("--out-txt", default="sim/golden/golden_vectors.txt")
    parser.add_argument("--price-base", type=int, default=DEFAULT_PRICE_BASE)
    parser.add_argument("--tick", type=int, default=DEFAULT_TICK)
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.out_json), exist_ok=True)
    convert_vector_file(args.input, args.out_json, args.out_txt, args.price_base, args.tick)

if __name__ == "__main__":
    main()
