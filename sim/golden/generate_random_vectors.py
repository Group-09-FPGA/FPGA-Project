#!/usr/bin/env python3
"""Generate valid random orders and independent dictionary-book expectations."""
import argparse
import random
from pathlib import Path

BASE = 123456
TICK = 37
COUNT = 512


def generate(output, seed):
    rng = random.Random(seed)
    book = {}
    events, expected = [], []
    counts = {op: 0 for op in range(1, 6)}

    def fresh_id():
        while True:
            ref = rng.getrandbits(64)
            if ref and ref not in book:
                return ref

    for seq in range(1, COUNT + 1):
        # Twelve initial IDs deliberately share hash set zero, exercising
        # eight hash ways and the collision stash without exceeding capacity.
        if seq <= 12:
            op, oid = 1, (seq << 20) | seq
        elif not book:
            op, oid = 1, fresh_id()
        else:
            op = rng.choice([1, 1, 2, 3, 4, 5] if len(book) < 64 else [2, 3, 4, 5])
            oid = fresh_id() if op == 1 else rng.choice(list(book))
        side = shares = index = noid = 0
        if op == 1:
            side, shares = rng.randrange(2), rng.randint(1, 10000)
            index = 0 if seq == 1 else 8191 if seq == 2 else rng.randrange(8192)
            book[oid] = side, shares, index
        elif op in (2, 3):
            old_side, old_qty, old_index = book[oid]
            shares = rng.randint(1, old_qty)
            if shares == old_qty:
                del book[oid]
            else:
                book[oid] = old_side, old_qty - shares, old_index
        elif op == 4:
            del book[oid]
        else:
            old_side, _, _ = book.pop(oid)
            noid, shares, index = fresh_id(), rng.randint(1, 10000), rng.randrange(8192)
            while noid == oid:
                noid = fresh_id()
            book[noid] = old_side, shares, index
        counts[op] += 1
        word = ((1 << 252) | (op << 248) | (side << 247) | (oid << 176) |
                (noid << 112) | (shares << 80) | (index << 67) | (seq << 32))
        events.append(f'{word:064x}')
        bids = [(qty, pidx) for s, qty, pidx in book.values() if s == 0]
        asks = [(qty, pidx) for s, qty, pidx in book.values() if s == 1]
        bid_index = max((p for _, p in bids), default=None)
        ask_index = min((p for _, p in asks), default=None)
        fields = [(1, 1), (len(book), 12),
                  (0 if bid_index is None else BASE + bid_index * TICK, 32),
                  (sum(q for q, p in bids if p == bid_index), 32),
                  (0 if ask_index is None else BASE + ask_index * TICK, 32),
                  (sum(q for q, p in asks if p == ask_index), 32)]
        result = 0
        for value, width in fields:
            result = (result << width) | value
        expected.append(f'{result:036x}')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'random_events.hex').write_text('\n'.join(events) + '\n')
    (output / 'random_expected.hex').write_text('\n'.join(expected) + '\n')
    print(f'Random seed {seed}: {COUNT} events, canonical op counts {counts}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--seed', type=int, default=20261102)
    args = parser.parse_args()
    generate(args.output, args.seed)
