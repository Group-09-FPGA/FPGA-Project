# `lob_core` part 2: EXECUTE / CANCEL / DELETE, REPLACE, best-price search, fail-stop

Same file as part 1. These operations all start with an id that **already exists**, so the sequence begins with a hash lookup and a read of the stored order.

---

# Part A: EXECUTE / CANCEL / DELETE (10 states)

## A1. The three operations share one script

| Op | Meaning | Shares deducted | Order dies? |
| --- | --- | --- | --- |
| Execute (`E`/`C` in ITCH) | shares traded away | `cur_evt_shares` | only if shares reach 0 |
| Cancel (`X`) | reduce the order by N shares | `cur_evt_shares` | only if shares reach 0 |
| Delete (`D`) | remove the whole order | **all** the order's stored shares | always |

## A2. The state-by-state script

| State | Action | Why |
| --- | --- | --- |
| `ECD_C1` | `hash_lookup(oid)` | find the order |
| `ECD_C2` | wait | hash needs two cycles |
| `ECD_C3` | `if (!hash_match_hit) fail(FAIL_MISSING_OID); else { lat_slot, lat_way, lat_is_stash, lat_stash_idx <= match_*; slot_read(match_slot); }` | the id must exist; remember where; start reading its slot |
| `ECD_C4` | wait | slot read latency 1 |
| `ECD_C5` | `lat_ord_side/pidx/shares <= slot_rd_*`; delete: `lat_deduct <= all`, `lat_rem <= 0`, `lat_is_kill <= 1`; else if `cur_evt_shares > stored` → `fail(FAIL_QTY_UF)`; else `lat_deduct <= cur_evt_shares`, `lat_rem <= stored − requested`, `lat_is_kill <= (stored == requested)`; then `price_read(side, pidx)` | slot data is valid; decide how many shares leave; start the price-level read |
| `ECD_C6`, `ECD_C7` | wait | the price RAM takes 3 clocks |
| `ECD_C8` | `if (price_rd_valid)`: if `deduct > level total` → `fail(FAIL_QTY_UF)`; else `lat_new_level_qty <= total − deduct`, `lat_level_zero <= (total == deduct)`, `lat_triggers_search <= bbo_triggers_search && (total == deduct)` | the level total arrives; check; decide whether the best price is affected |
| `ECD_C9` | **COMMIT** | writes |
| `ECD_C10` | search needed? → `search_target_side <= lat_ord_side; state <= ST_SEARCH_START`; else `finish` | |

During `ECD_C8`, the side and price index of the level are driven onto `bbo_check_side` / `bbo_check_pidx` so `lob_bbo` can answer `bbo_triggers_search` combinationally in the same clock.

## A3. The commit (`ECD_C9`)

```verilog
slot_write(lat_slot, !lat_is_kill, lat_ord_side, lat_ord_pidx, lat_rem_shares);       // valid = 0 if the order died
price_write(lat_ord_side, lat_ord_pidx, lat_new_level_qty);                           // new level total
if (lat_level_zero) occupancy_set(lat_ord_side, lat_ord_pidx, 1'b0);                  // level now empty
if (lat_is_kill) begin
    level_count(1'b0, lat_ord_side, lat_ord_pidx);                                    // −1 order at this level (display)
    hash_remove(lat_is_stash, lat_stash_idx, lat_way);                                // the id leaves the hash table
    free_push_en <= 1; free_push_slot <= lat_slot;                                    // the slot returns to the free list
end
if (!lat_triggers_search) bbo_direct(lat_ord_side, lat_ord_pidx, lat_new_level_qty);  // BBO fast path
```

If the order **died**, three structures are cleaned (hash, slot, free list). If the **level emptied**, the occupancy bit clears. If the emptied level **was the best price**, the fast BBO update is skipped and the search path runs next.

## A4. Timing (approximate clock numbers)

Accept 0; `C1` 1; `C2` 2; `C3` 3; `C4` 4; `C5` 5 (price read issued); `C6` 6; `C7` 7; `C8` waits to clock 9 (3-clock price latency); `C9` 10; `C10` 11; then `finish`. About 12-13 clocks (about 250 ns). If a search is needed: +10 more.

## A5. Worked example: execute 100 of order 0x2001 (300 shares, buy, index 5)

1. `C3`: hash hit → slot 2047.
2. `C5`: stored shares 300, requested 100 → `lat_rem = 200`, `lat_is_kill = 0`.
3. `C8`: level total 300 (only this order) → `lat_new_level_qty = 200`, `lat_level_zero = 0`.
4. `C9`: slot 2047 ← `{1, buy, 5, 200}`; price[5] ← 200; BBO direct update (same level → quantity 200).
5. `C10`: no search → `finish`.

**Cancel the remaining 200:** stored = requested → `lat_is_kill = 1`, `lat_new_level_qty = 0`, `lat_level_zero = 1`. If this was the best bid, `lat_triggers_search = 1`.
`C9`: slot valid = 0, price[5] ← 0, occupancy bit cleared, hash entry removed, slot 2047 pushed back on the free list, order count −1; **no** direct BBO update. `C10`: starts the search.

---

# Part B: REPLACE (12 states)

## B1. What replace means

An ITCH `U` message replaces an order with a **new id**, **new price** and **new shares**. The side stays the same. The book handles it as "remove the old entry, insert the new one, **reuse the same slot**".

## B2. The script

| State | Action |
| --- | --- |
| `REP_C1` | `hash_lookup(oid)` (the **old** id) |
| `REP_C2` | wait |
| `REP_C3` | old id must exist (`FAIL_MISSING_OID`); save `rep_slot`, `rep_old_way`, `rep_old_is_stash`, `rep_old_stash_idx`; **start the lookup of the new id** (`hash_lookup(noid)`: it must not exist) and read the old slot |
| `REP_C4` | wait |
| `REP_C5` | new id already present → `fail(DUP_OID)`; bucket full → `fail(HASH_FULL)`; else save where the new id will go (`rep_new_way`, `rep_new_use_stash`, `rep_new_stash_idx`), the old order's side/pidx/shares, the new pidx/shares; read the **old** price level |
| `REP_C6` | read the **new** price level |
| `REP_C7` | wait |
| `REP_C8` | (old level data) `rep_old_shares > total` → `fail(QTY_UF)`; else `rep_new_old_level_qty = total − old_shares`, `rep_old_level_zero`, `rep_triggers_search` |
| `REP_C9` | (new level data) overflow checks; `rep_new_new_level_qty = total + new_shares`. If the **old and new price index are the same**, the arithmetic uses the already-reduced old level quantity |
| `REP_C10` | **commit 1**: remove the old hash entry; if the price changed: `level_count(−1, old level)`, write the old level's new total, clear its occupancy bit if it is now empty |
| `REP_C11` | **commit 2**: insert the new hash entry, write the slot (new price/shares, same slot number), write the new level total, `level_count(+1, new level)` (if the price changed), set the new level's occupancy bit; if the old level was the best and emptied → search; else BBO direct update |
| `REP_C12` | `finish` |

## B3. Why two commit beats?

Replace touches **two** price levels and the hash table twice, and the memories have one write port each. Splitting into *K1* (removal side) and *K2* (insertion side) keeps every memory to one write per clock. The result is still atomic from the outside: nothing reads the book mid-event.

## B4. Subtle case: same price level

If the replacement stays at the same price, the old level total (minus old shares) and the new level total (plus new shares) are the **same price-RAM entry**. A naive design would read the old total twice and lose one update. The code checks `rep_old_pidx == rep_new_pidx` and chains the arithmetic through `rep_new_old_level_qty`.

## B5. Worked example

Replace id 0x2001 (100 shares at index 5, the only order at that level, best bid) by id 0x2002 (50 shares at index 9).

- `C5`: new id 0x2002 not in the table; bucket fine.
- `C8`: old level total 100 → `new_old = 0`, `old_level_zero = 1`, `triggers_search = 1` (it was the best).
- `C9`: new level (index 9) total 0 → `rep_new_new_level_qty = 50`.
- `C10`: old hash entry removed; level 5: count −1, total 0, occupancy bit cleared.
- `C11`: new hash entry, slot rewritten (50 shares at index 9, same slot), level 9 total 50, count +1, occupancy bit set. `rep_triggers_search && pidx differ` → search (so the BBO ends with the best bid = index 9; the search sees the newly set bit).

---

# Part C: Best-price search

## C1. When

After a commit that emptied the **current best** level (execute/cancel/delete of its last shares, or a replace moving away from it).

## C2. States

| State | Action |
| --- | --- |
| `ST_SEARCH_START` | `occ_search_start <= 1; occ_search_side <= search_target_side` |
| `ST_SEARCH_WAIT` | when `occ_search_done`: save `found_search_pidx`, `found_search_valid`. If valid → `price_read(side, found pidx)` → `SEARCH_PRICER`; if not → `bbo_search_result(0, 0, 0)` (side empty) → `ST_DONE` |
| `ST_SEARCH_PRICER`, `ST_SEARCH_PRICE1` | two wait states |
| `ST_SEARCH_PRICE2` | when `price_rd_valid` → `bbo_search_result(1, found pidx, price_rd_data)` → `ST_DONE` |
| `ST_DONE` | `finish` |

(`ST_SEARCH_COMMIT` is declared but unused.) Total about 5 + 5 clocks regardless of how many orders exist.

---

# Part D: Fail-stop and errors

## D1. All the error codes and where they come from

| Code | Name | Raised in |
| --- | --- | --- |
| `01` | `FAIL_EVT_FORMAT` | `ST_IDLE` (decoder) |
| `02` | `FAIL_DUP_OID` | `ADD_C3`, `REP_C5` |
| `03` | `FAIL_MISSING_OID` | `ECD_C3`, `REP_C3` |
| `04` | `FAIL_NO_SLOT` | `ADD_C3` |
| `05` | `FAIL_HASH_FULL` | `ADD_C3`, `REP_C5` |
| `06` | `FAIL_QTY_OVF` | `ADD_C4`, `REP_C9` |
| `07` | `FAIL_QTY_UF` | `ECD_C5`, `ECD_C8`, `REP_C8` |
| `08` | `FAIL_PRICE_OOW` | `ST_IDLE` (the OOW bit) |
| `09` | `FAIL_INVALID_OP` | `ST_IDLE` |
| `0A` | `FAIL_FEED_LOSS` | the `feed_fault` override |

## D2. Behaviour

`fail(code)`: `error_valid <= 1; error_code <= code;` then (with `cfg_fail_stop_en = 1`, tied on in this design) `book_valid <= 0; state <= ST_FAIL_STOP`. `ST_FAIL_STOP` has **no exit**: only a reset (or the unused `cfg_clear`) restarts, by returning to `ST_RESET` and re-initialising every memory.

`event_ready` is now 0 forever, `book_valid = 0` is visible everywhere (LED 3 off, LED 7 on, UART `V:0`, VGA "book invalid").

## D3. Why stop instead of skip?

A rejected add or delete means the book now differs from the exchange's book. All later prices would be wrong with no way to tell. A visibly stopped book is honest; a silently wrong one is dangerous.

## D4. The Python-model difference (a favourite examiner topic)

The software reference model (used to make the golden vectors) *continues* after a rejected event; the RTL deliberately **stops**. `tb_lob_golden` therefore skips that one rejected event in the main comparison and tests it separately: it checks the RTL fail-stops (`book_valid = 0`, `ready = 0`, `error_code = 0x02`, active orders still 4).

---

# Part E: Reading the whole file quickly

1. Ports and sub-instances (about 400 lines of wiring: skim).
2. `ST_*` constants and working registers.
3. `busy`, `event_ready`, `bbo_check_*` assigns.
4. `u_trace` instance.
5. The tasks (about 150 lines).
6. The main `always`: reset, defaults, overrides, then `case (state)`: this is the file.

When asked "what happens if X", find the state that checks X and look at which `fail(...)` or commit it leads to.
