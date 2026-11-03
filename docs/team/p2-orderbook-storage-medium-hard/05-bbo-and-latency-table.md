# `lob_bbo` and the latency table

---

# Part A: `lob_bbo` (`rtl/lob/lob_bbo.v`, 245 lines)

## A1. Job

Hold the **best bid** and **best ask** (price index, quantity, valid flag) and publish them as real **prices and quantities** that everyone else uses.
It also answers one question for the sequencer: "is the level I am about to empty the current best?"

*Analogy:* the price board in a shop window. Staff update it when something changes; customers (CPU, UART, VGA) just read it.

## A2. Internal registers (index domain)

```verilog
reg        bid_valid_r;  reg [12:0] bid_pidx_r;  reg [31:0] bid_qty_r;
reg        ask_valid_r;  reg [12:0] ask_pidx_r;  reg [31:0] ask_qty_r;
```

These hold the current best level **as an index**, not as a price. Better means: for bids a **higher** index, for asks a **lower** index.

## A3. Two update paths from the sequencer

### Fast path: `bbo_direct_*` (no search needed)

Used after an add, or after a partial execute/cancel at a level. For a **bid**:

| Situation | Action |
| --- | --- |
| no best bid yet, **or** the updated level is better (`pidx > bid_pidx_r`) | and `qty > 0` → this level becomes the best (valid, pidx, qty) |
| the updated level **is** the best (`pidx == bid_pidx_r`) | and `qty > 0` → just update the quantity |
| the updated level is worse | **nothing changes** |

For **asks** the comparison is reversed (`pidx < ask_pidx_r` is better).

A quantity of 0 on the best level is **not** handled here (it would leave a stale best). That case is exactly when `triggers_search` is true and the sequencer uses the search path instead.

### Slow path: `bbo_search_*` (after the best level emptied)

```verilog
bid_valid_r <= bbo_search_valid;
bid_pidx_r  <= bbo_search_pidx;
bid_qty_r   <= bbo_search_valid ? bbo_search_qty : 0;
```

The sequencer ran an occupancy search, read the new best level's quantity from the price RAM, and writes the result here (or `valid = 0` if that side is now empty).

### `clear_en`

Clears everything (during `ST_RESET` or `cfg_clear`).

## A4. `triggers_search`: the question

```verilog
always @* begin
    if (check_side == 0) triggers_search = bid_valid_r && (check_pidx == bid_pidx_r);
    else                 triggers_search = ask_valid_r && (check_pidx == ask_pidx_r);
end
```

The sequencer puts the side and price index of the level it is working on on `check_side` / `check_pidx` (in states `ECD_C8` / `REP_C8`). If that level **is** the current best, and the level's total is about to reach zero,
then after the commit the BBO would be stale; the sequencer must search for the next best. Otherwise it can use the fast path.

## A5. Turning an index back into a price (the output pipeline)

The book stores indexes, but the outside world wants prices: `price = base + pidx × tick`.

```
 bid_pidx_r ──► stage 1: s1_bid_prod = pidx × tick_pipe ──► stage 2: best_bid_price = base + s1_bid_prod
 (index regs)   (multiplier)                                   (adder)
```

- `tick_pipe` and `base_pipe` register `cfg_tick` and `cfg_price_base` one clock earlier, to help timing.
- Stage 1 also copies `valid`, `pidx` and `qty`; stage 2 produces `best_bid_valid`, `best_bid_pidx`, **`best_bid_price`**, **`best_bid_qty`**. Price is `0` when not valid.
- The multiplier is a 32-bit multiply (the tool maps it to the chip's DSP blocks).

**Consequence (this appears in other owners' docs too):** the published BBO lags the internal registers by **2 clocks**. The UART telemetry waits 6 clocks after `event_done` before sampling the BBO so everything is consistent.

## A6. Worked example

`base = 900000` (=$90.0000), `tick = 1000` (=$0.1000). The book is empty. Add buy 300 at index 5:

- `bbo_direct`: no best bid → `bid_valid_r = 1`, `bid_pidx_r = 5`, `bid_qty_r = 300`.
- 1 clock later `s1_bid_prod = 5 × 1000 = 5000`; 2 clocks later `best_bid_price = 900000 + 5000 = 905000` ($90.5000), `best_bid_qty = 300`.

Add buy 100 at index 9 (a better bid): `pidx 9 > 5` → best becomes index 9, qty 100, price `909000`.
Cancel 100 at index 9 (level to zero, it was the best): `triggers_search` = 1 → occupancy search finds index 5 → `bbo_search` writes pidx 5 and its quantity 300.

## A7. "What if"

- **An order is added at a worse price than the best?** The fast path ignores it; the best does not change (the order is still stored in the price RAM and slot table).
- **The best level is partially executed?** `pidx == best`, `qty > 0` → quantity updated.
- **The tick changes at run time?** Prices recompute from the new `tick_pipe`, which is why the CPU may only change configuration before any order exists (the LOB MMIO registers refuse writes once events have been counted).
- **Both sides empty?** Both valid flags 0; prices read 0.

---

# Part B: The latency table (the contract with owner 3)

Everything the sequencer waits on, in one place. "Cycle 0" is the cycle the sequencer's command register is **set**, so the memory sees it during the next cycle.

| Operation | Command | Answer valid | Sequencer state that uses it |
| --- | --- | --- | --- |
| Hash lookup | `hash_rd_en` (+ set, key) | `match_*` after 2 cycles | `ADD_C3`, `ECD_C3`, `REP_C3` / `REP_C5` |
| Slot read | `slot_rd_en` (+ addr) | next cycle (`rd_data`) | `ECD_C5`, `REP_C5` |
| Free list top | `free_rd_top_en` | next cycle (`top_slot`, `top_valid`) | `ADD_C3` |
| Price RAM read | `price_rd_en` (+ addr) | **3 cycles** (`rd_valid`) | `ADD_C4`, `ECD_C8`, `REP_C8`/`C9`, `SEARCH_PRICE2` |
| Occupancy search | `occ_search_start` (+ side) | `search_done` after 5 states | `SEARCH_WAIT` |
| BBO check | combinational (`check_*`) | same cycle | `ECD_C8`, `REP_C8` |
| BBO update | `bbo_direct_upd_en` / `bbo_search_upd_en` | internal regs next cycle; **price/qty outputs 2 cycles later** | read by UART after 6 cycles |
| Commit writes | `*_wr_en`, `hash_wr_*`, `hash_inv_*`, `free_push_en`, `free_pop_commit`, `occ_leaf_upd_en` | take effect next clock edge | |

The reason `ST_ECD_C6` and `C7` exist as empty "wait" states: the price RAM read issued in `ECD_C5` is only valid three clocks later, in `ECD_C8`.

## C. How to explain the whole picture in one breath

> "When an order comes in, the sequencer asks me three things at the same time (hash lookup, free slot, price level). Two cycles later I answer. If everything checks out, it tells me
> to write: put the key in the hash table, the details in the slot table, take the slot from the free list, add the shares to the price level, set the occupancy bit, and update
> the best price. Because every block has a fixed delay, the whole add takes the same number of cycles every time."
