# The system from the output owner's seat

You sit at the end of the pipeline, but you also **hold the second read port of every memory** and **host the keyboard hardware**, so you touch almost everyone.

## What comes **into** your part

| Input | From | Meaning |
| --- | --- | --- |
| best bid/ask valid/price/qty, `book_valid`, `error_code`, `active_orders`, `event_done`, `core_event_count` | **owners 2 and 3** (`lob_core`, `lob_bbo`) | the headline numbers |
| `storage_trace[315:0]` | **owner 3** (`lob_storage_trace`) | what the last event wrote |
| `event_meta`, `local_done_*` | **owner 3** (`order_merge`) | metadata and results of keyboard orders |
| `diag[351:0]`, `ip_csum_errors`, `pipe_stats[159:0]` | **owner 1** (`net_ingest`) | network counters |
| `cfg_price_base`, `cfg_tick` | **owner 4** (CPU config registers) | needed to format prices; also printed by the UART and on the Status page |
| level-count deltas `level_count_delta_*` | **owner 3** (`lob_core`) | when an order is added to or removed from a price level |
| the second read ports `display_*` of the hash table, slot table, price RAM, free list | **owner 2** | the real memory contents |
| keyboard form state (page, focus, text fields, selected order, status) | **owner 3** (`keyboard_controls`, hosted in your `display_system`) | what to show while the user types |
| `uart_rxd`, `ps2_clk`, `ps2_data` | the USB-UART and the board's USB-HID chip | queries from the laptop; keys |
| CPU's UART bus window | **owner 4** | the supervisor can write bytes into the UART FIFO |

## What goes **out of** your part

| Output | To | Meaning |
| --- | --- | --- |
| `uart_txd_out` | the USB-UART, then the laptop | status lines and query replies |
| `vga_hs`, `vga_vs`, `vga_r/g/b[3:0]` | the VGA monitor | 1280×720 @ 60 Hz |
| `ui_valid/data/ready` | **owner 3's** `order_merge` | keyboard orders typed on the Order Entry page |
| `slot_addr`, `hash_set`, `stash_idx`, `price_addr`, `free_addr`, `quote_addr`, `event_addr` | **owner 2's** memories (second read ports) | read addresses |

## Where owners 1-4 see themselves on your screen

| Page | What it shows | Whose data |
| --- | --- | --- |
| **Market** | best bid, best ask, spread, bid/ask history charts, live book and pipeline counters | 2 (BBO), 1 (counters), 3 (history from events) |
| **Orders** | every live order: id, side, price index, shares, slot, hash set | 2 (hash + slot tables) |
| **Hash** | the hash table, set by set, 8 ways + stash | 2 |
| **Events** | the last events with their storage writes | 3 (`storage_trace`) |
| **Status** | book valid/invalid, error code, active orders, completed events, **network pipeline counters, CRC errors, sequence gaps, price base and tick** | 1, 3, 2, 4 |
| **Levels** | orders and quantity per price level | 2 (price RAM) + level counts |
| **Slots** | raw slot table | 2 |
| **Order Entry** | the keyboard form, focus, shortcut help, status message, last local order accepted/rejected | 3 |
| **Quote history** | one line per event: event number, best bid and ask | 2 / 3 journal |

So **an Ethernet packet that owner 1 decoded shows up in three places you own**: the UART line (`R:`/`U:`/`M:`/`I:`/`F:` counters and `B:`/`A:` prices), the Market page chart, and the Orders page row.

## The key rule you enforce

> **The display and UART never change the book.**
> The UI CPU has no path to the event stream; its only outputs are RAM read requests and video-memory writes. The UART readback only reads. The only way something typed on the screen becomes an order is through the keyboard FIFO and the same legality checks as a network order.

## Timing the user experiences

| Output | Update delay after an event |
| --- | --- |
| UART status line | about 6 clocks to settle + about 28 ms to print |
| VGA | within one frame (16.7 ms) of the firmware finishing its redraw loop |
| LEDs / 7-segment (owner 4) | immediate |
