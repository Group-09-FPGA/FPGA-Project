# The system from the storage owner's seat

You own the memories. Almost everything in the chip ends up reading them.

## What comes **into** your modules

| Input | From | Meaning |
| --- | --- | --- |
| command registers: `hash_rd_en`, `hash_rd_set`, `hash_lookup_key`, `hash_wr_*`, `hash_inv_*`, `slot_rd_en/addr`, `slot_wr_*`, `free_rd_top_en`, `free_pop_commit`, `free_push_*`, `price_rd_en/addr`, `price_wr_*`, `occ_leaf_*`, `occ_search_*`, `bbo_direct_*`, `bbo_search_*`, `bbo_clear_en` | **owner 3's `lob_core`** | one-clock commands, set by the sequencer's state machine |
| `*_init_start` | `lob_core` (`ST_RESET`) | "zero yourselves" after every reset |
| `cfg_price_base`, `cfg_tick` | the CPU (owner 4) via `lob_core`'s `eff_*` registers | used only by `lob_bbo` to turn a price index back into a price |
| `dbg_clk`, `dbg_*` addresses | owner 5's display / UART (the 25 MHz UI clock) | read-only second port on each memory |

## What goes **out of** your modules

| Output | To | Meaning |
| --- | --- | --- |
| `hash_match_*`, `hash_free_*`, `hash_bucket_full` | `lob_core` | "id found? where? where can a new one go?" |
| `slot_rd_data` | `lob_core` | the order's side, price index, shares |
| `free_top_slot`, `free_top_valid`, `free_empty`, `free_full`, `free_active_count` | `lob_core` (and `active_order_count` outward) | next free slot and the live-order count |
| `price_rd_data`, `price_rd_valid` | `lob_core` | level quantity, 3 clocks after the request |
| `occ_search_*`, `occ_*_has_orders` | `lob_core` | "highest bid / lowest ask index" |
| `bbo_triggers_search` | `lob_core` | "the level you are emptying is the current best" |
| `best_bid/ask_valid/price/qty` | **everyone downstream** | the book's headline numbers |
| `display_*` / `dbg_*` data | owner 5 | the real memory contents, read-only |

## Who ends up showing what you store

```
 your memories
   ├─ best bid/ask ──► owner 4: LOB MMIO registers (the CPU snapshot), LED row, seven-segment display
   │                ├► owner 5: UART "[BBO] B:...|A:..|QB..|QA.." line, VGA Market page header and chart
   │                └► owner 5: history journal (a sample after every event)
   ├─ active order count (free list) ──► LEDs 15:12, UART "N:", VGA
   ├─ hash ways/stash dbg port ──► VGA Hash page, UART "?H" and "?X" queries, keyboard order browser (owner 3)
   ├─ slot table dbg port ──► VGA Orders and Slots pages, UART "?S", keyboard order browser, stale-order check
   ├─ price RAM dbg port ──► VGA Levels page, UART "?P"
   └─ free list dbg port ──► UART "?F"
```

So **everything on the Orders, Hash, Slots and Levels pages is literally your memory contents**, shown with no copy or fake data. That is why every memory has a **second read port** on the display's clock.

## What you do *not* decide

You never decide **when** to read or write, or whether an event is legal. `lob_core` (owner 3) decides; you obey and answer after fixed delays.
This makes your blocks easy to test in isolation, and means any "what if the event is bad?" question about *legality* goes to owner 3.

## Initialization (everyone's concern)

After every reset, `lob_core` pulses all five `*_init_start`. Each block then runs a small internal counter that zeroes (or, for the free list, fills) its memory:

| Block | Init | Cycles |
| --- | --- | --- |
| hash table | writes 0 to all 1024 sets in every way, clears the stash | 1024 |
| slot table | writes 0 (valid = 0) to 2048 slots | 2048 |
| free list | writes `stack[i] = i` and sets `sp = 2048` | 2048 |
| occupancy | writes 0 to 256 leaf words per side; clears level 1 and level 0 | 256 |
| price RAM | writes 0 to 16,384 levels | **16,384** (the slowest; about 0.33 ms at 50 MHz) |

`lob_core` waits for all five (`ST_INIT_WAIT`), then sets `init_done` and `book_valid` and starts accepting events (if the CPU has enabled it).
