# `lob_core` part 1: structure, initialization, accepting an event, and ADD

File: `rtl/lob/lob_core.v` (about 870 lines). One instance, `u_lob_core`, in `top_system`. Core clock (50 MHz).

## 1. What it is, in one paragraph

`lob_core` is **a sequencer**: a finite state machine that, for each event, walks through a fixed list of **steps** (states). In each step it may issue **one-cycle commands** (read the hash table, write the slot, ...)
and then waits the right number of clocks for the answers. It contains the memories as sub-instances (owner 2's modules) and the decoder and trace modules, but the *logic that decides what happens when* is all here.

*Analogy:* a chef following a recipe card. Each card step says "put the pot on, wait 3 minutes, check the temperature". The recipe never changes; only the ingredients (the event) do.

## 2. The ports in groups

| Group | Ports | Meaning |
| --- | --- | --- |
| event in | `event_valid`, `event_data[255:0]`, `event_ready` | the canonical event handshake; `event_ready` is **output** |
| control | `cfg_clear` (tied 0), `cfg_fail_stop_en` (tied 1), `run_enable`, `feed_fault`, `cfg_price_base`, `cfg_tick` | `run_enable` from the CPU, `feed_fault` from the network |
| status out | `book_valid`, `init_done`, `busy`, `error_valid`, `error_code`, `active_order_count`, `event_done`, `storage_trace` | the book's public health |
| BBO out | `best_bid_valid/price/qty`, `best_ask_valid/price/qty` | from `lob_bbo` |
| display ports | `display_clk` and `display_*_addr` / `display_*_data` | pass-through to the memories' second ports |
| level counts | `level_count_delta_valid/inc/addr` | tells `lob_level_order_count` (display memory) that a price level gained or lost an order |

## 3. What lives inside `lob_core`

```
 u_decoder (lob_event_decoder)       u_hash_table   u_slot_table   u_free_list   u_price_ram   u_occupancy   u_bbo   u_trace
        ▲                                   ▲              ▲             ▲             ▲            ▲           ▲
        └────────── the state machine issues commands to all of them with registered one-cycle pulses ───────────┘
```

Each sub-block's signals are named with a prefix: `hash_*`, `slot_*`, `free_*`, `price_*`, `occ_*`, `bbo_*`. **Naming tells you whose it is.**

## 4. The registers you must recognise

| Register(s) | Meaning |
| --- | --- |
| `state` (6 bits) | current step; constants `ST_*` |
| `cur_evt` | the event being processed (256-bit copy taken at accept time) |
| `reg_is_add/exec/cancel/delete/replace` | which operation (one-hot, from the decoder) |
| `lat_*` | working values for execute / cancel / delete: `lat_slot`, `lat_way`, `lat_is_stash`, `lat_stash_idx`, `lat_ord_side/pidx/shares`, `lat_deduct_shares`, `lat_rem_shares`, `lat_is_kill`, `lat_new_level_qty`, `lat_level_zero`, `lat_triggers_search` |
| `rep_*` | working values for replace (old and new slot/way/stash, old/new price index and shares, old/new level quantities, ...) |
| `search_target_side`, `found_search_pidx`, `found_search_valid` | best-price search working values |
| `hash_rd_en`, `hash_wr_*`, `hash_inv_*`, `slot_rd_en`, `slot_wr_*`, `free_*`, `price_rd_*`, `price_wr_*`, `occ_*`, `bbo_*` | **command registers**: one-clock pulses to owner 2's memories |
| `eff_price_base`, `eff_tick` | registered copies of the configuration (`eff_tick` falls back to a default if the CPU wrote 0) |

## 5. The structure of the main `always` block

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ... every register to its starting value; state <= ST_RESET ...
    end else begin
        // (1) DEFAULTS: every one-cycle command is cleared every clock
        event_done <= 0; level_count_delta_valid <= 0; hash_rd_en <= 0; slot_wr_en <= 0; price_wr_en <= 0; ...

        // (2) OVERRIDES
        if (cfg_clear && state != ST_INIT_WAIT) begin ... state <= ST_RESET ...
        end else if (feed_fault) begin state <= ST_FAIL_STOP; book_valid <= 0; error_valid <= 1; error_code <= FAIL_FEED_LOSS; end
        else begin
            // (3) THE SCRIPT
            case (state) ... endcase
        end
    end
end
```

**The key idea (3 parts):**

1. **Reset branch:** all registers have a defined start value.
2. **Defaults first, then the case:** because later non-blocking assignments to the same register *win*, setting every command to 0 at the top and then setting some to 1 in a state means each command is **automatically a one-clock pulse**.
3. **Overrides before the case:** `feed_fault` (a network loss) forces `ST_FAIL_STOP` at any moment, regardless of what the state machine was doing.

## 6. The helper tasks (what each state's lines mean)

These are written once and used throughout (they replaced about 14 copies of 8 lines). A task call is "paste these assignments here".

| Task | What it assigns |
| --- | --- |
| `fail(code)` | `error_valid <= 1; error_code <= code;` then, in fail-stop mode, `book_valid <= 0; state <= ST_FAIL_STOP`, otherwise `state <= ST_IDLE` |
| `finish` | `event_done <= 1; state <= ST_IDLE` |
| `hash_lookup(id)` | `hash_rd_en <= 1; hash_rd_set <= hash_oid(id); hash_lookup_key <= id` |
| `hash_insert(use_stash, stash_idx, way_idx, slot, key)` | writes `{slot, key}` into a stash entry or a way of `hash_oid(key)` |
| `hash_remove(use_stash, stash_idx, way_idx)` | clears that stash entry or that way of `hash_oid(cur_evt_oid)` |
| `slot_read(slot)`, `slot_write(slot, valid, side, pidx, shares)` | access the slot table |
| `price_read(side, pidx)`, `price_write(side, pidx, qty)` | access the price RAM (`{side, pidx}` address) |
| `level_count(inc, side, pidx)` | `level_count_delta_*` pulse for the display's per-level count |
| `occupancy_set(side, pidx, val)` | set/clear one occupancy bit |
| `bbo_direct(side, pidx, qty)`, `bbo_search_result(valid, pidx, qty)` | the two BBO update paths |

`hash_oid(id)` is a *function* (an XOR fold of the id, owner 2 explains why).

## 7. Initialization and getting ready

| State | What happens |
| --- | --- |
| `ST_RESET` | pulse all five `*_init_start`; clear the BBO; `init_done <= 0; book_valid <= 0` |
| `ST_INIT_START` | wait one clock (memories latch the start) |
| `ST_INIT_WAIT` | wait until all five report `init_done` **and** none is `busy` (price RAM, 16,384 clocks, is slowest, about 0.33 ms) → `init_done <= 1; book_valid <= 1; state <= ST_IDLE` |

## 8. `ST_IDLE`: accepting an event

```verilog
assign event_ready = (state == ST_IDLE) && init_done && book_valid && run_enable && !feed_fault;

ST_IDLE: begin
    error_valid <= 0;
    if (event_valid && event_ready) begin
        cur_evt <= dec_evt;  reg_is_add <= dec_is_add; ...          // capture the event and its operation
        if (dec_error)          fail(dec_err_code);                  // illegal format
        else if (dec_price_oow) fail(FAIL_PRICE_OOW);                // price outside the window
        else case (dec_evt[`EVT_OP_SLICE])
            OP_ADD:                           state <= ST_ADD_C1;
            OP_EXECUTE, OP_CANCEL, OP_DELETE: state <= ST_ECD_C1;
            OP_REPLACE:                       state <= ST_REP_C1;
            default:                          fail(FAIL_INVALID_OP);
        endcase
    end
end
```

`event_ready` has **five** conditions: idle, initialised, book still valid, **CPU has enabled** (`run_enable`), no network loss. Any one false → the event waits (the producer sees backpressure).

Also: `busy = (state != ST_IDLE) && (state != ST_FAIL_STOP)`. Note that all `fail(...)` here happen **before** any command to the memories, so a rejected event leaves the book untouched.

## 9. ADD (6 states)

```
 IDLE ─accept─► C1 ─► C2 ─► C3 ─► C4 ───(wait for price data)──► C5 (COMMIT) ─► C6 ─► IDLE
                │            │      │                              │              └ finish: event_done
                │            │      └ price overflow check          └ writes
                │            └ duplicate / no slot / bucket full → fail()
                └ prefetch: hash lookup + free-list top + price level + occupancy word, all at once
```

| State | Code (simplified) | Meaning |
| --- | --- | --- |
| `ADD_C1` | `hash_lookup(oid); free_rd_top_en<=1; price_read(side,pidx); occ_leaf_rd_en<=1; ...` | start **four reads in parallel**: does the id exist? which slot is free? what is the level's current total? the occupancy word |
| `ADD_C2` | wait | the memories need time |
| `ADD_C3` | `if (hash_match_hit) fail(DUP_OID); else if (free_empty) fail(NO_SLOT); else if (hash_bucket_full) fail(HASH_FULL); else latch lat_slot/lat_way/lat_is_stash/lat_stash_idx` | **all legality checks**; the three failures are in priority order. Success remembers *where* things will be stored |
| `ADD_C4` | `if (price_rd_valid) begin if ((price_rd_data + shares) < price_rd_data) fail(QTY_OVF); else lat_new_level_qty <= price_rd_data + shares; end` | waits **in place** until the price RAM data is valid (3 clocks after C1), then checks for 32-bit overflow (wrap-around detection) |
| `ADD_C5` | **commit** (see below) | all the writes at once |
| `ADD_C6` | `finish` | `event_done` pulse; back to idle |

**`ADD_C5` commit (all in one clock):**

```verilog
hash_insert(lat_is_stash, lat_stash_idx, lat_way, lat_slot, cur_evt_oid);      // 1. id → slot
slot_write(lat_slot, 1'b1, cur_evt_side, cur_evt_pidx, cur_evt_shares);        // 2. order details
free_pop_commit <= 1;                                                          // 3. the slot is now taken
price_write(cur_evt_side, cur_evt_pidx, lat_new_level_qty);                    // 4. level total up
level_count(1'b1, cur_evt_side, cur_evt_pidx);                                 // 5. +1 order at this level (display)
occupancy_set(cur_evt_side, cur_evt_pidx, 1'b1);                               // 6. level now occupied
bbo_direct(cur_evt_side, cur_evt_pidx, lat_new_level_qty);                     // 7. maybe the new best
```

Seven writes in one clock: that is the **atomic commit point**. Everything before it only reads; if any check failed, no write ever happened.

### Timeline of an ADD (clock numbers; each state is 1 clock except the wait)

| Clock | State | Notes |
| --- | --- | --- |
| 0 | `ST_IDLE` | event accepted |
| 1 | `ADD_C1` | commands issued |
| 2 | `ADD_C2` | memories working |
| 3 | `ADD_C3` | hash match and free-list top valid |
| 4-5 | `ADD_C4` | waits for the price RAM (valid at clock 5) |
| 6 | `ADD_C5` | **commit** |
| 7 | `ADD_C6` | `event_done` |

About 8 clocks, 160 ns at 50 MHz. The time is the same every time, whatever is in the book.

## 10. Worked example

Fresh book. Event: Add, id 0x2001, buy, 300 shares, pidx 5.

- `ADD_C3`: hash miss, free list not empty (top = slot 2047), bucket not full → `lat_slot = 2047`, `lat_way = 0`, `lat_is_stash = 0`.
- `ADD_C4`: price level `{0,5}` currently 0 → new quantity 300.
- `ADD_C5`: hash set 9 way 0 ← `{1, 2047, 0x2001}`; slot 2047 ← `{1, buy, 5, 300}`; `sp` 2048 → 2047; price[5] ← 300; order count at level 5 +1; occupancy bit set; BBO best bid = index 5, qty 300.

## 11. "What if"

- **The id already exists?** `ADD_C3` → `fail(FAIL_DUP_OID)` → `book_valid = 0`, fail-stop. Nothing has been written.
- **The price level would overflow?** `ADD_C4` → `fail(FAIL_QTY_OVF)`.
- **`feed_fault` goes high in the middle?** The override above the `case` forces `ST_FAIL_STOP` immediately.
