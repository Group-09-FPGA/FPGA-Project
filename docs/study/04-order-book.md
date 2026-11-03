# Chapter 4: The order book (`rtl/lob/`)

This is the heart of the project. It stores every open order, and always knows
the best buy and best sell price.

## Words you need

- **Order:** "I want to buy/sell N shares at price P", identified by a 64-bit **order id**.
- **Bid / Ask:** buy side / sell side. **Best bid** = highest buy price, **best ask** = lowest sell price.
- **Price level:** all orders at one price. The book keeps one **total quantity per level**.
- **Price index (pidx):** `(price − base) / tick`, a small number 0..8191. One side has 8192 levels.
- **Operations:** *Add* a new order; *Execute* (shares traded away); *Cancel* (reduce by N shares);
  *Delete* (remove completely); *Replace* (new id, price and shares).

## Analogy: a library

| Library | Order book |
| --- | --- |
| Card catalogue (look up a book's shelf by title) | **hash table**: order id → slot number |
| The shelf spaces | **slot table**: 2048 slots, each holding side/price/shares of one order |
| A list of empty shelf spaces | **free list**: stack of unused slot numbers |
| A tally sheet of how many copies sit at each price | **price RAM**: total shares per price level |
| A map of which price rows are non-empty | **occupancy bitmaps**: a tree of bits |
| A board showing the best prices | **BBO** registers |

## Module map

```
event ─► lob_event_decoder ─► lob_core (sequencer) ─┬─► lob_hash_table
                                                    ├─► lob_slot_table
                                                    ├─► lob_free_list
                                                    ├─► lob_price_ram
                                                    ├─► lob_occupancy
                                                    ├─► lob_bbo
                                                    └─► lob_storage_trace
```

`lob_core` is the only module that decides *when* things happen; the others are
storage blocks with simple ports.

## `lob_defines.vh`: the shared constants

Capacities (2048 slots, 1024 hash sets x 8 ways, 8 stash entries, 8192 price levels per side), opcodes
(`OP_ADD`..`OP_REPLACE`), error codes (`FAIL_*`), the event bit slices (`EVT_*_SLICE`), and the
layouts of a slot entry (47 bits: valid, side, 13-bit price index, 32-bit shares) and a hash
entry (76 bits: valid, 11-bit slot, 64-bit key).

## `lob_event_decoder`: is this event legal?

**Job:** purely combinational checker; tells `lob_core` whether the event is well formed and
which operation it is.

**Rules (examples):** version must be 1; reserved bits must be 0; Add needs a non-zero id and shares; Execute/Cancel need
shares and no new id; Delete needs shares = 0; Replace needs both ids. Failing events produce
`evt_error` with `FAIL_EVT_FORMAT` or `FAIL_INVALID_OP`.

**Why here:** keeps all format rules in one place, so the sequencer can assume sane input.

**Always block:** `always @*`, one combinational block that sets `evt_valid`, `evt_error`, `error_code`. Outputs
`is_add`, `is_exec`, ..., and `price_oow` (a copy of the out-of-window bit).

## `lob_hash_table`: find an order by id

**Job:** given a 64-bit id, say whether it exists and where its slot is; also say where a new id could be stored.

**Structure:** `HASH_SETS`=1024 rows; each row has 8 **ways** (one RAM each, made by a `generate` loop of
`lob_hash_way_ram`), plus a shared **stash** of 8 entries for overflow. The set number is
`hash_oid(id)`, an XOR-fold of the 64-bit id into 10 bits.

**Analogy:** a coat-check with 1024 hooks, each hook holding up to 8 coats, and 8 extra
hooks by the door for when a hook is full.

**Lookup:** `rd_en` with `rd_set` and `lookup_key` reads the set from all 8 RAMs at once. The compare
logic (`always @*`) checks each way and each stash entry against `key_q`; outputs are
`match_hit`, `match_slot`, `match_way`, `match_is_stash`, `match_stash_idx`. At the same time it reports the first
free way (`free_way_idx`) and free stash entry. `bucket_full` means neither is free.

**Writes:** `wr_way_en`/`wr_stash_en` insert `{1, slot, key}`; `inv_way_en`/`inv_stash_en` clear an entry.

**`dbg_*` ports:** each RAM has a second, read-only port on `dbg_clk` (the UI clock). The display and the UART
readback use it, so they can read the book's real memory without disturbing the order logic. In
`lob_hash_way_ram` this is implemented as a **duplicate memory** (`dbg_mem`) written with the same data.

**Initialization:** after `init_start`, `initializing` makes every row write zeros once (`init_cnt`).

## `lob_slot_table`: remember each order's details

2048 entries x 47 bits `{valid, side, pidx, shares}`. One write port, one read port with 1-cycle latency
(`rd_data_reg`), and a debug port. Initialization writes zeros. `eff_wr_*` is a small mux: during init the
initializer owns the write port, otherwise the sequencer does.

## `lob_free_list`: which slots are empty?

A **stack** of slot numbers in `stack_mem`, with `sp` (stack pointer).

- At init, slot *i* is written as value *i*, and `sp` = 2048 (all free).
- **Allocate (pop):** `rd_top_en` reads `stack_mem[sp-1]` into `top_slot`; `pop_commit` then decrements `sp`.
  The read and the commit are separate, so the sequencer can check capacity first.
- **Free (push):** `push_en` writes the slot at `stack_mem[sp]` and increments `sp`.
- `active_count` = 2048 − `sp`: the number of live orders (shown on LEDs and UART).

## `lob_price_ram`: total shares at each price

16,384 x 32 bits, addressed by `{side, pidx}` (14 bits). Reads go through a 3-stage pipeline
(`stage1_data/valid` .. `stage3`), so **the answer arrives 3 cycles after `rd_en`**; that is why
the sequencer has idle "wait" states. Writes are immediate.

## `lob_occupancy`: which price levels have orders?

**Job:** remember which levels are non-empty, and quickly find the new best level when the old one empties.

**Structure (a 3-level tree of bits):**

- Leaf: 256 words x 32 bits per side (`leaf_mem_bid`, `leaf_mem_ask`) → 8192 bits, one per price level.
- Level 1: `l1_bid[255:0]`, one bit per leaf word ("this word has any bit set").
- Level 0: `l0_bid[7:0]`, one bit per group of 32 level-1 bits.

**Search (`SRCH_*` state machine):** to find the highest bid, take the highest set bit of `l0_bid`
(`prio_enc_high_8`), then in that group the highest set bit of `l1_bid`, then read that leaf word and take its
highest bit. Result `search_pidx = {group, j, bit}`. Asks use the *lowest* set bit (`prio_enc_low_*`).
It takes a bounded 5-6 cycles regardless of how many orders exist.

**Update:** `leaf_upd_en` with side, `pidx` and a bit value sets/clears one bit, then recomputes the affected
level-1/level-0 bits.

**Analogy:** finding the first occupied apartment in a skyscraper: ask the lobby board which tower, then which
floor, then which door. Three quick lookups, not a walk down every corridor.

## `lob_bbo`: the best prices

**Job:** hold best bid/ask (price index, quantity, valid) and produce the real **price** and quantity outputs.

- **Direct update (`bbo_direct_*`):** after an add or partial reduce at a level, if the level is better than (or
  equal to) the current best, take it. Fast path, no search.
- **Search update (`bbo_search_*`):** when the best level empties, take the occupancy search result.
- `triggers_search` (combinational) tells the sequencer "the level I am about to empty *is* the current best", so it
  knows a search is needed. Inputs are `check_side`, `check_pidx`.
- **Price calculation:** a two-stage pipeline: `s1_*_prod = pidx * tick`, then `best_*_price = base + prod`.
  So the price outputs follow the index registers by two clock cycles. (That is why `uart_telemetry` waits
  six clocks after `event_done` before sampling.)

## `lob_storage_trace`: what did the last event write?

Watches the write-enable pulses (`slot_wr_en`, hash insert/invalidate, price writes) during one event and
packs them into a 316-bit record (`trace`) published when the event completes. The UART's `T:` field and the
display's event history come from this. The record contains: the operation, old/new ids, slot write
(address, data), hash invalidation, hash insertion, and up to two price-level writes.

## `lob_core`: the sequencer

**Job:** run the right step-by-step sequence for each operation.

**Why it is a state machine:** the memories are synchronous: you issue a read, wait a few cycles, then use the
data. Each operation is a fixed script, so it takes a bounded, predictable number of cycles.

### Important registers and wires

| Name | Meaning |
| --- | --- |
| `state` | current step (`ST_*` constants) |
| `cur_evt` | the event being processed (captured in `ST_IDLE`) |
| `event_ready` | high only in `ST_IDLE` and `init_done && book_valid && run_enable && !feed_fault` |
| `run_enable` | from the CPU: nothing is accepted until firmware enables it |
| `feed_fault` | from `net_ingest`: sticky loss flag; forces `ST_FAIL_STOP` |
| `book_valid` | 0 after any error in fail-stop mode |
| `error_valid`, `error_code` | what went wrong |
| `event_done` | one-clock pulse when an event finishes (drives UART, history, counters) |
| `lat_*` | working values for execute/cancel/delete |
| `rep_*` | working values for replace |
| `hash_*`, `slot_*`, `free_*`, `price_*`, `occ_*`, `bbo_*` | **command registers**: one-cycle commands to the memories |
| `level_count_delta_*` | tells `lob_level_order_count` that a level gained/lost an order |

### The main `always` block

One big block, three parts:
1. **Reset branch:** every register to its start value, `state <= ST_RESET`.
2. **Defaults:** each command pulse (`hash_rd_en`, `slot_wr_en`, `price_wr_en`, ...) is set to 0 every cycle.
   A state that wants a command sets it to 1 *for this cycle only*. Later assignments win, so the pulses are naturally one clock long.
3. **`case (state)`:** the scripts below, preceded by two overrides: `cfg_clear` (restart) and `feed_fault` (fail-stop).

### The tasks (small named commands)

| Task | Does |
| --- | --- |
| `fail(code)` | set `error_valid/code`; in fail-stop mode clear `book_valid` and go to `ST_FAIL_STOP`, otherwise return to idle |
| `finish` | pulse `event_done`, go to `ST_IDLE` |
| `hash_lookup(id)` | start a hash read for that id |
| `hash_insert(...)`, `hash_remove(...)` | write / invalidate a hash entry (way or stash) |
| `slot_read`, `slot_write` | access the slot table |
| `price_read`, `price_write` | access the price RAM |
| `level_count(inc, side, pidx)` | +1 / −1 order at a level |
| `occupancy_set(side, pidx, val)` | set or clear a level's occupied bit |
| `bbo_direct(...)`, `bbo_search_result(...)` | update best prices |

### Script: initialization

`ST_RESET` pulses every `*_init_start` and clears the BBO; `ST_INIT_START` waits a cycle; `ST_INIT_WAIT` waits until all
five memories report `init_done` and none is busy (price RAM takes 16,384 cycles, the slowest), then sets
`init_done` and `book_valid` and goes idle. About 0.33 ms.

### Script: ADD (6 steps)

| State | Action |
| --- | --- |
| `ADD_C1` | start reads: hash lookup of the id, free-list top, price level, occupancy leaf word |
| `ADD_C2` | wait |
| `ADD_C3` | `hash_match_hit` → `FAIL_DUP_OID`; `free_empty` → `FAIL_NO_SLOT`; `hash_bucket_full` → `FAIL_HASH_FULL`; else remember which slot and which way/stash to use |
| `ADD_C4` | when the price data arrives: overflow check, new level quantity = old + shares |
| `ADD_C5` | **commit:** insert hash entry, write slot, pop free list, write price level, +1 order count, set occupancy bit, update BBO |
| `ADD_C6` | `finish` |

### Script: EXECUTE / CANCEL / DELETE (10 steps)

`C1` start hash lookup → `C2` wait → `C3` id must exist (`FAIL_MISSING_OID`), remember slot, start slot read → `C4` wait →
`C5` read stored side/price/shares; work out how many shares to deduct (delete = all; otherwise `cur_evt_shares`, error `FAIL_QTY_UF` if more than the order has);
start price read → `C6`, `C7` wait → `C8` price data arrives; check level has enough; compute new level quantity, whether it is now zero,
and whether this level is the current best (`triggers_search`) → `C9` **commit** (rewrite slot, price level, clear occupancy if the level emptied; if the order is dead: −1 order count, invalidate hash entry,
push the slot back on the free list; direct BBO update unless a search is needed) → `C10` either start a search or `finish`.

### Script: REPLACE (12 steps)

Same ideas with two ids: look up the old id (must exist), look up the new id (must **not** exist) while reading the old slot, read both old and new price
levels, check, then two commit beats: *K1* removes the old hash entry and (if the price changed) the old level;
*K2* inserts the new hash entry, rewrites the slot with new price/shares, writes the new level, sets its occupancy bit, and updates the BBO (or starts a search).

### Script: best-price search

`SEARCH_START` asks the occupancy tree; `SEARCH_WAIT` gets `search_pidx`; the price read takes 3 more cycles
(`PRICER`, `PRICE1`, `PRICE2`); then `bbo_search_result` writes the new best (or marks the side empty) and `ST_DONE` finishes.

### Fail-stop

`ST_FAIL_STOP` does nothing until reset. This is deliberate: a half-correct book is worse than a stopped one. In the
display you will see the error code; in LED7 `error_valid` lights.

### Example: Execute 100 of order 0x2001 (300 shares at index 5)

1. Hash finds slot 2047 (the first slot popped from the free list is the highest number).
2. Slot read gives side=buy, pidx=5, shares=300. Deduct 100, remaining 200, not a kill.
3. Price level 5 had 300; new total 200, not zero, so no search.
4. Commit: slot ← {valid, buy, 5, 200}; price level 5 ← 200; BBO direct update to quantity 200.
5. `event_done` pulses; UART prints the new BBO.

## Why do these blocks exist at all? (summary)

| Block | Without it... |
| --- | --- |
| hash table | finding an order by id would need scanning 2048 slots |
| free list | every add would have to search for an empty slot |
| price RAM | the best-level quantity would need summing all orders at that price |
| occupancy tree | finding the next best price would need scanning up to 8192 levels |
| BBO registers | every consumer (CPU, UART, display) would need to search |
