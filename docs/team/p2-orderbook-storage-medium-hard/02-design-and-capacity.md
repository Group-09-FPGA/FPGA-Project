# Design and capacity: why these structures, why these sizes

## 1. The problem in plain words

The book must support five operations on **millions of events per second** with **bounded, predictable time** (no scanning loops):

| Question the sequencer asks | Naive answer (slow) | Our answer (fast) |
| --- | --- | --- |
| "Does order id X exist, and where is it?" | scan every stored order | **hash table** → slot number in 2 cycles |
| "Give me an empty storage cell" | scan for a free cell | **free list stack** → top is the answer |
| "What are the details of order X?" | | **slot table**, direct address |
| "How many shares in total at price P?" | add up every order at P | **price RAM**, one entry per price, kept up to date |
| "What is the best price now?" | scan all price levels | **BBO registers** + **occupancy tree** for the rare "best level emptied" case |

Every structure is a **fixed-size RAM with a fixed latency**. Nothing loops over data, so every operation takes the same number of clocks regardless of how full the book is.

## 2. The constants (`lob_defines.vh`)

| Constant | Value | Meaning |
| --- | --- | --- |
| `NUM_SLOTS` / `SLOT_ADDR_W` | 2048 / 11 | maximum live orders; slot number width |
| `HASH_SETS` / `HASH_SET_W` | 1024 / 10 | hash rows |
| `HASH_WAYS` / `HASH_WAY_W` | 8 / 3 | entries per row |
| `STASH_ENTRIES` / `STASH_ADDR_W` | 8 / 3 | overflow entries shared by all rows |
| `PRICE_LEVELS_PER_SIDE` / `PRICE_INDEX_W` | 8192 / 13 | levels per side; index width |
| `TOTAL_PRICE_LEVELS` / `PRICE_ADDR_W` | 16,384 / 14 | both sides together; `{side, pidx}` |
| `OCC_LEAF_WORDS` | 256 | 32-bit words per side in the occupancy leaves (256 × 32 = 8192) |
| `OP_ADD` ... `OP_REPLACE` | 1 ... 5 | opcodes |
| `FAIL_*` | `0x01`...`0x0A` | error codes |

`FAIL_*`: `EVT_FORMAT 01`, `DUP_OID 02`, `MISSING_OID 03`, `NO_SLOT 04`, `HASH_FULL 05`, `QTY_OVF 06`, `QTY_UF 07`, `PRICE_OOW 08`, `INVALID_OP 09`, `FEED_LOSS 0A`.

## 3. The two record formats (know the bit positions)

### Slot entry: 47 bits

```
 46   45   44 ........ 32   31 ............. 0
valid side   price index        shares
 1b   1b       13 bits          32 bits
```

`SLOT_VALID_BIT = 46`, `SLOT_SIDE_BIT = 45`, `SLOT_PIDX_SLICE = 44:32`, `SLOT_SHARES_SLICE = 31:0`.

### Hash entry: 76 bits

```
 75   74 ........ 64   63 ................................ 0
valid  slot number                 key (64-bit order id)
 1b      11 bits                        64 bits
```

`HASH_VALID_BIT = 75`, `HASH_SLOT_SLICE = 74:64`, `HASH_KEY_SLICE = 63:0`.

**Why store the whole 64-bit key?** Different ids can hash to the same row. The full key is what distinguishes them.

## 4. The hash function

```
 hash(oid) = oid[9:0] ^ oid[19:10] ^ oid[29:20] ^ oid[39:30] ^ oid[49:40] ^ oid[59:50] ^ {6'b0, oid[63:60]}
```

Seven chunks of 10 bits (the last has only 4 real bits) XOR-ed into one 10-bit number: the **set** (row) number, 0..1023.

- **Why XOR-fold?** It is a few XOR gates, one clock, and mixes all 64 bits.
- **Weakness:** ids that differ only in a pattern that cancels (e.g. same bits in two chunks) collide. The random test **deliberately** creates 12 ids that all hash to set 0 to prove the design copes.

## 5. Why 8 ways and a stash?

A row (set) has 8 entries (ways). If a 9th id hashes to the same row there is **no room** in the row. A tiny **stash** of 8 entries, **shared by all rows**, catches the overflow. So a row can hold 8 ids in its ways plus as many extra as there are free stash entries (at most 8 across the whole table). `bucket_full` means "this row has no free way **and** the stash has no free entry"; adding then fails with `FAIL_HASH_FULL`.

*Analogy:* a coat-check with 1024 hooks of 8 pegs each, and 8 extra pegs by the door that anyone can use. Coats go on their own hook's pegs first; when that hook is full the coat goes by the door.

Capacity check: 2048 orders over 1024 sets × 8 ways = 8192 pegs, a load of 25 %, so overflow of a single row is rare but possible, hence the stash.

## 6. Why price index instead of raw price?

Prices are 32-bit numbers (e.g. 905000). A direct RAM indexed by price would be 4 billion entries. A real market trades in a narrow band around the current price in fixed steps (ticks), so:

```
 index = (price − base) / tick       // base = lowest price tracked, tick = price step
```

8192 levels per side × tick $0.1000 = a $819.20 window above `base`. Outside the window the event is flagged out-of-window and rejected. Both sides share the same index space, with the side bit in front: `price address = {side, pidx}`.

## 7. Memory technologies used

| Block | RAM type | Why |
| --- | --- | --- |
| hash ways (8) | block RAM, one per way, plus a **duplicate** for the display port | read all 8 ways of a row in one cycle |
| stash | registers (flops) | only 8 entries; compared in parallel with the ways |
| slot table | block RAM | 2048 × 47 |
| free list | block RAM | 2048 × 11 |
| price RAM | block RAM | 16,384 × 32 |
| occupancy leaves | **distributed (LUT) RAM** | needs an asynchronous read for the read-modify-write bit update in one cycle |
| occupancy levels 1 and 0 | flops | 256 + 8 bits each side, searched combinationally |

`(* ram_style = "block" *)` and `(* ram_style = "distributed" *)` are hints to Vivado. A RAM described with a reset in the same `always` block would not map to a block RAM, so the RAM writes live in their own clock-only blocks.

## 8. The "second port" pattern

Each memory has a read-only **debug / display port** on a different clock (`dbg_clk`, the 25 MHz UI clock):

```verilog
always @(posedge dbg_clk) dbg_data <= mem[dbg_addr];
```

This lets the VGA display, the UART readback and the keyboard order browser read the real contents **without** touching the sequencer's ports. In `lob_hash_way_ram` a second copy of the array (`dbg_mem`) is written with the same data so each clock domain has its own read port. The cost is extra block RAM; the benefit is that display traffic can never slow or corrupt the order logic.

Caveat (documented in the code): reading the same address in the same cycle a write happens is **not** a coherent snapshot; the display tolerates this, and the keyboard's order browser re-checks the data before submitting.

## 9. Fixed latencies (the contract with owner 3)

| Block | Request cycle | Data valid |
| --- | --- | --- |
| hash lookup | `rd_en` with `rd_set`, `lookup_key` | match outputs valid in the cycle `match_valid` (1 cycle later, as `rd_en_q`), so the sequencer uses them 2 cycles after issuing |
| slot read | `rd_en` | `rd_data` next cycle |
| free list top | `rd_top_en` | `top_slot` / `top_valid` next cycle |
| price RAM read | `rd_en` | **3 cycles** (pipeline stages 1-3), with `rd_valid` |
| occupancy search | `search_start` | `search_done` after 5 states |
| BBO | any update | registers update next cycle; **price** output two more cycles later (multiply pipeline) |

Section 5 of this folder collects all of these in one table with the sequencer's wait states.
