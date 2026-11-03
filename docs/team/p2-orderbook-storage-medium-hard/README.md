# Owner 2: The order book's memories and best price  (difficulty: medium-hard)

## Your 30-second pitch

> "I own the data structures of the order book. A **hash table** finds an order by its 64-bit id, a **slot table** stores each
> order's side, price and remaining shares, a **free list** hands out empty slots, a **price RAM** keeps the total quantity at every price level,
> an **occupancy tree** of bits finds the next best price in a handful of cycles, and the **BBO** registers hold and publish the best bid and ask.
> They are all simple storage blocks with one-cycle commands and fixed-latency answers; the sequencer, owned by owner 3, tells them what to do."

## Your modules

| Module | File | Lines | One-line job |
| --- | --- | --- | --- |
| `lob_defines.vh` | `rtl/lob/lob_defines.vh` | ~100 | capacities, opcodes, error codes, bit layouts, `HASH_OID` macro |
| `lob_hash_table` (+ `lob_hash_way_ram`) | `rtl/lob/lob_hash_table.v` | 327 | order id → slot number; 1024 sets × 8 ways + 8-entry stash |
| `lob_slot_table` | `rtl/lob/lob_slot_table.v` | 102 | 2048 × 47-bit records: valid, side, price index, shares |
| `lob_free_list` | `rtl/lob/lob_free_list.v` | 149 | stack of free slot numbers |
| `lob_price_ram` | `rtl/lob/lob_price_ram.v` | 135 | 16,384 × 32-bit total shares per price level |
| `lob_occupancy` | `rtl/lob/lob_occupancy.v` | 359 | 3-level bitmap tree + priority-encoder search |
| `lob_bbo` | `rtl/lob/lob_bbo.v` | 245 | best bid / ask registers and the price calculation pipeline |

Shared with owner 3 (you must know it, they own it): the order *sequencer* `lob_core` that issues commands to you.

## Tests you can run live

```bash
tb_lob_free_list                 # push/pop, full/empty, reclaim order
tb_lob_golden                    # 31 events from the Python-checked golden vectors compared to the RTL after every commit
tb_lob_random                    # 512 random operations x 3 seeds, 12 ids deliberately colliding in hash set 0
```

`tb_lob_random` is the strongest evidence for your part: it forces the hash collision and stash paths, and compares the book against an independent
dictionary model after **every** commit.

## Reading order

1. [00-system-in-10-minutes](../00-system-in-10-minutes.md)
2. [01-the-system-from-my-seat](01-the-system-from-my-seat.md)
3. [02-design-and-capacity](02-design-and-capacity.md): why these structures and these sizes
4. [03-hash-slot-freelist](03-hash-slot-freelist.md)
5. [04-price-ram-and-occupancy](04-price-ram-and-occupancy.md)
6. [05-bbo-and-latency-table](05-bbo-and-latency-table.md)
7. [06-viva-qa](06-viva-qa.md)

## The seven facts you must be able to state without looking

1. Capacities: **2048 order slots**, **1024 hash sets × 8 ways + 8 stash**, **8192 price levels per side** (16,384 total).
2. The price index is `(price − base)/tick`, 13 bits; price RAM address is `{side, pidx}`, 14 bits.
3. Hash function: **XOR-fold** of the 64-bit id into 10 bits (7 chunks).
4. A slot entry is **47 bits**: `{valid, side, pidx[12:0], shares[31:0]}`; a hash entry is **76 bits**: `{valid, slot[10:0], key[63:0]}`.
5. The free list is a **stack**; pop is split into *read top* and *commit* so the sequencer can check before it takes.
6. The occupancy tree is **8192 leaf bits → 256 level-1 bits → 8 level-0 bits**; a search takes **5 cycles** whatever the book size.
7. Read latencies: hash 2, slot 1, free list 1, occupancy search 5, **price RAM 3**.
