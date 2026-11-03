# The whole system in 10 minutes

Read this once, whichever part you own. It is the context for every viva question
that crosses a boundary ("where does your output go?", "what feeds your input?").

## What the project is

A hardware **limit order book** on a Nexys A7 FPGA board. A stock exchange sends
tiny messages ("order 7: buy 100 shares at $90.50", "order 7 cancelled"). The FPGA
decodes them in dedicated hardware and keeps the live book: every open order plus
the best buy price (best **bid**) and best sell price (best **ask**).
Orders can also be typed on a USB keyboard. Results appear on a VGA monitor,
over a USB serial port (UART), on 16 LEDs and on an 8-digit seven-segment display.
A small RISC-V CPU supervises.

## One order, end to end (read this slowly)

```
 (1) Ethernet cable
      │  bits from the PHY chip
      ▼
 (2) NETWORK FRONT END ................................ owner 1
      rmii_rx → net_parser → moldudp64_decoder → itch_decoder
      "Ethernet frame" → "UDP payload" → "numbered messages" → "256-bit canonical event"
      │  async FIFO carries the event to the core clock
      ▼
 (3) ORDER SOURCES + SEQUENCER ........................ owner 3
      order_merge picks network or keyboard events (one at a time)
      lob_core checks legality and runs the add/execute/cancel/delete/replace script
      │  commands to memories
      ▼
 (4) ORDER-BOOK MEMORIES .............................. owner 2
      hash table (find by id), slot table (order details), free list,
      price RAM (total shares per price), occupancy tree, best bid/ask registers
      │  results: best bid/ask, order count, "event done", error code
      ├────────────────► (5) CPU + BOARD ............. owner 4
      │                      reads status over a bus, enables the book, drives LEDs/7-seg
      └────────────────► (6) DISPLAY + UART .......... owner 5
                             VGA pictures drawn from the book's real RAM, serial status line
```

A keyboard order is the second input: the display system (owner 5's hardware)
hosts the keyboard pins, but the keyboard logic (typing, validation, building the
event) is **owner 3**'s. It joins the stream at step 3.

## The five parts in one sentence each

| Owner | One sentence |
| --- | --- |
| 1 | "I turn bytes on the wire into clean, checked order events in the core's clock, and I own all the clocks, resets and safe clock crossings." |
| 2 | "I own the memories that remember every order and let the book find any order or the best price quickly." |
| 3 | "I decide whether an event is legal and run the step-by-step script that updates the memories; I also build keyboard orders and merge the two sources." |
| 4 | "I own the RISC-V supervisor that unlocks the book and reads its status, plus the register map, LEDs, seven-segment display and the top-level wiring." |
| 5 | "I turn the book's real memory contents into a VGA picture and a serial text stream, and I answer memory queries from the laptop." |

## The interface contracts (where the five parts meet)

These are the boundaries examiners love. Everyone should know all of them.

| # | Boundary | Signals | What it means |
| --- | --- | --- | --- |
| A | Owner 1 → owner 3 | `evt_valid`, `evt_data[255:0]`, `evt_ready` | one canonical order event, valid/ready handshake, already in the **core** clock |
| A' | Owner 1 → everyone | `feed_loss`, `diag[351:0]`, `pipe_stats[159:0]`, `ip_csum_errors` | network health and counters |
| B | Owner 5 (keyboard hardware) / owner 3 → merge | `ui_valid`, `ui_data[255:0]`, `ui_ready` | one keyboard event in the **ui** clock, crossing into core through a FIFO |
| C | Owner 3 → owner 2 | command registers: `hash_rd_en/set/key`, `slot_wr_en/addr/data`, `price_rd/wr_*`, `occ_*`, `bbo_*`, `free_*` | one-cycle commands to the memories |
| D | Owner 2 → owner 3 | `hash_match_*`, `slot_rd_data`, `price_rd_data/valid`, `free_top_*`, `occ_search_*`, `bbo_triggers_search` | answers after fixed delays |
| E | Owner 3/2 → owner 4 and owner 5 | `lob_book_valid`, `lob_init_done`, `lob_busy`, `lob_error_*`, `lob_event_done`, `lob_active_orders`, best bid/ask price and quantity, `lob_storage_trace` | the book's public status |
| F | Owner 4 → owner 3 | `accel_enable` (becomes `run_enable`) | until the CPU enables, **no order is accepted** |
| G | Owner 4 → owner 1 | `cfg_price_base`, `cfg_tick`, `cfg_locate` | configuration the decoder needs, crossing into the `eth` clock |
| H | Owner 2 memories ↔ owner 5 | the `display_*` read-only ports | second read port on every memory so VGA and UART can read the real data |
| I | Owner 3 → owner 5 | keyboard form state (page, focus, text) | what the screen shows while you type |

## The canonical event (the language every part speaks)

256 bits, defined in `rtl/lob/lob_defines.vh`:

| Bits | Field | Meaning |
| --- | --- | --- |
| 255:252 | version | must be 1 |
| 251:248 | opcode | 1 add, 2 execute, 3 cancel, 4 delete, 5 replace |
| 247 | side | 0 buy (bid), 1 sell (ask) |
| 246:240 | reserved | must be 0 |
| 239:176 | order id | 64-bit |
| 175:112 | new order id | for replace |
| 111:80 | shares | |
| 79:67 | price index | `(price − base) / tick`, 13 bits |
| 66 | out-of-window | price did not fit the 8192-level window |
| 65:64, 31:0 | reserved | must be 0 |
| 63:32 | sequence | feed sequence number (or a local counter for keyboard orders) |

## The four clock domains

| Domain | Frequency | Who lives there |
| --- | --- | --- |
| `eth` | 50 MHz | owner 1's network blocks |
| `core` | 50 MHz | owner 2, 3, 4 and the UART |
| `ui` | 25 MHz | keyboard, display CPU, display memories (owners 3 and 5) |
| `pixel` | 74.25 MHz | the video scan-out (owner 5) |

Signals cross between them only through `config_cdc` (a hold-and-handshake copy)
or `async_event_fifo` (a Gray-code queue). Owner 1 owns those two modules; everyone uses them.

## Five facts every viva answer should be consistent with

1. **No order is accepted until the CPU writes `1` to the LOB `CTRL` register.** The book's `event_ready` includes `run_enable`.
2. **The book fails safe.** Any impossible event, or any lost network message, makes it stop (`ST_FAIL_STOP`, `book_valid = 0`) until reset.
3. **Nothing hard-coded is displayed.** Every number on VGA and UART comes from real FPGA registers and RAM.
4. **The display CPU cannot inject orders.** It only reads book memory and writes video memory.
5. **Keyboard orders skip the network pipeline,** so the network counters count only real network traffic.

## Vocabulary

| Word | Meaning |
| --- | --- |
| bid / ask | buy side / sell side; best bid is the highest buy price, best ask is the lowest sell price |
| price level | all orders at one price; the book keeps one total quantity per level |
| price index | `(price − base) / tick` |
| tick | smallest price step (default 1000 = $0.1000) |
| base | price of index 0 (default 900000 = $90.0000) |
| slot | one storage cell holding one live order |
| way / set / stash | hash-table terms: 1024 sets x 8 ways, plus an 8-entry stash |
| MMIO | the CPU reads and writes hardware registers as if they were memory |
| CDC | clock-domain crossing |
| fail-stop | stop accepting events after any error until reset |
