# Data delivery to the display

Files: `ram_ports.v`, `ui_registers.v`, `status_to_ui.v`, `book_views.v`, `lob_display_journal.v`, `lob_level_order_count.v`, `display_system.v` (all in `rtl/display/`).

The display CPU is slow and lives in the 25 MHz UI clock. This chapter covers how everything it needs gets there safely.

## 1. Two kinds of data

| Kind | How it reaches the UI CPU |
| --- | --- |
| **Status** (a few dozen values: book valid, best prices, counters, config, form state) | packed into **52 registers** by `ui_registers`, read over MMIO |
| **Bulk** (hash rows, slots, price levels, journals) | **RAM queries**: the CPU asks `ram_ports` for one entry at a time |

## 2. `status_to_ui`: core state into the UI clock

Seven `config_cdc` instances (all named `u_*_cdc` so the timing constraints cover them): `u_book_cdc` (175 bits: valid flags, best prices/quantities, order count, event count), `u_net_cdc` (128: from `net_diag`), `u_pipe_cdc` (96), `u_error_cdc` (8), `u_config_cdc` (64: `{base, tick}`), `u_history_cdc` (32), `u_local_done_cdc` (41). Latest-snapshot semantics are fine: these change slowly or only need to be current.

## 3. `ui_registers`: the contract with the firmware

A combinational `always @*` packing a 2048-bit vector (52 used words). Firmware reads word *n* at `0x1000_0000 + 4n`.

| Word | Contents |
| --- | --- |
| 0 | `{status[4:0], scan_busy, selected_valid, focused_valid, editing, side, action[2:0], focus[2:0], page[3:0]}` |
| 1, 2 | form lengths, form cursors (4 × 5 bits) |
| 3, 4 | price, quantity |
| 5-8 | order id, new id (low, high each) |
| 9, 10 | selected order id |
| 11-14 | hash set/way/stash, slot + free offset, level, history offset |
| 15 | flags `{ask valid, bid valid, book valid}` |
| 16-21 | best bid price, bid qty, best ask price, ask qty, active orders, event count |
| 22-25 | rx frames, CRC errors, Mold messages, sequence gaps |
| 26-28 | UDP packets, ITCH events, FIFO events |
| 29 | error code |
| 30, 31 | price base, tick |
| 32 | history meta: `{event_next, event_count, quote_next, quote_count}` (reordered to suit the firmware) |
| 33-48 | the four 16-character form fields (4 words each) |
| 49 | keyboard frame errors |
| 50, 51 | last local order: count / `{.., valid, error}` |

**Change a word's position and you must change `main.c`.**

## 4. `ram_ports`: sharing the book's read ports

Requesters: **readback** (UART) and the **display CPU** (and the keyboard order browser, which "holds" slot/hash ports).

```verilog
assign ui_grant = ui_request && !readback_active && !ui_hold;
```

| Output | Chosen from |
| --- | --- |
| `slot_addr` | readback `S` address, else the keyboard's `ui_hold_slot`, else the display request (kind 1) |
| `hash_set` | readback `B` scan set, readback `H` address, keyboard hold, display request (kind 2) |
| `stash_idx` | readback `X`, keyboard hold, display (kind 3) |
| `price_addr` | readback `P`/`L` address, else the display address |
| `free_addr` | readback `F`, else the display address |
| `quote_addr`, `event_addr` | readback `Q`/`E`, else display (kinds 7, 8 when granted) |

Data return: `ui_data` (selected by the **numeric** kind 1-8: slot, hash, stash, price, free, level count, quote, event) and `readback_data` (selected by the **letter** `S H X P F L Q E`), each padded into 608 bits. `hash_valid[7:0]` extracts each way's valid bit for the `B` scan.

## 5. The two display-only memories

### `lob_level_order_count`
`counts[0:16383]` of 12 bits: **how many orders sit at each price level**. Fed by `level_count_delta_valid/inc/addr` from the sequencer.
A 3-stage read-modify-write: stage 0 reads the old count; stage 1 computes ±1; stage 2 writes back. **Forwarding** (`forwarded_count`) handles two updates to the same level back to back (the second must see the first's result before it reaches the RAM). It initialises all 16,384 entries to 0 after reset (`init_done`). A second read port on the UI clock feeds the Levels page.

### `lob_display_journal`
Two rings written in the core clock, read in the UI clock:

| Ring | Size | Contents |
| --- | --- | --- |
| `quote_mem` | 128 × 175 bits | a snapshot of the book after every event: valid flags, best bid/ask price and quantity, order count, event number |
| `event_mem` | 256 × 394 bits | event number, `{side, shares, price index}`, and the 316-bit storage trace |

Timing pipeline: `done_pipe` shifts `event_done`. **After 1 clock** the storage trace is stable → write the event record. **After 7 more clocks** (`done_pipe[7]`) the BBO price pipeline has settled → write the quote record. `quote_next`/`event_next` are ring write pointers; `quote_count`/`event_count` saturate at 128/256. Together `{quote_count, event_count, quote_next, event_next}` is the `history_meta` word.

### `book_views`
Just instantiates both and exposes `history_meta`.

## 6. `display_system`: the wrapper

| Instance | Role |
| --- | --- |
| `u_ps2_receiver`, `u_ps2_decoder`, `u_frame_errors`, `u_keyboard` | the keyboard front end (owner 3's logic) |
| `u_registers` | `ui_registers` |
| `u_ram_ports` | `ram_ports` |
| `u_ui_cpu` | `kitty_ui_cpu` |
| `u_pixel_clock`, `u_video` | `kitty_pixel_clock`, `kitty_video` |

Its ports: PS/2 pins, the keyboard event stream (`event_*`), live state in the UI clock (`book`, `net`, `pipe`, `error`, `settings`, `history`, `local_done`), the book read ports and their data, and the VGA pins. (The port that carries `{price base, tick}` is called `settings` because `config` is a reserved word in Verilog.)

## 7. "What if"
- **Both the UART and the display want the RAM?** UART wins; the display CPU just waits, its request stays asserted until granted.
- **The keyboard is scanning orders while UART readback starts?** `ram_paused` makes the scan pause and restart its wait.
- **Why are display values two clock domains away from the book?** The book runs at 50 MHz; the UI at 25 MHz with different timing needs. Crossing with `config_cdc` keeps each side simple.
