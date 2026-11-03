# The system from the control owner's seat

You sit in the middle: events come in from two directions and commands go out to the memories.

## What comes **into** your part

| Input | From | Meaning |
| --- | --- | --- |
| `net_valid`, `net_data[255:0]`, `net_ready` | **owner 1's** `net_ingest` (through its 64-entry async FIFO) | decoded network order events, already in the core clock |
| keyboard pins `ps2_clk`, `ps2_data` | the board's USB-HID chip (it makes the USB keyboard look like PS/2) | key bits |
| `run_enable` (`accel_enable`) | **owner 4's CPU**, via the LOB MMIO `CTRL` register | "you may start accepting events" |
| `feed_fault` | **owner 1** | sticky "a network message may have been lost" |
| memory answers (`hash_match_*`, `slot_rd_*`, `price_rd_*`, `free_top_*`, `occ_search_*`, `bbo_triggers_search`) | **owner 2** | fixed-latency replies to your commands |
| `cfg_price_base`, `cfg_tick` | the CPU, through MMIO | for BBO and for the keyboard's price → index division |
| live RAM reads for the order browser (`hash_data`, `stash_data`, `slot_data`) | owner 2's second read ports, through owner 5's `ram_ports` | so the keyboard can browse real orders |

## What goes **out of** your part

| Output | To | Meaning |
| --- | --- | --- |
| one-cycle command registers | owner 2's memories | the add / execute / cancel / delete / replace scripts |
| `book_valid`, `init_done`, `busy`, `error_valid`, `error_code`, `event_done`, `event_ready` | owner 4 (CPU registers, LEDs), owner 5 (UART, VGA) | the book's health and a pulse per completed event |
| `storage_trace[315:0]` | owner 5 (UART `T:` field, VGA Events page, history journal) | what the last event wrote |
| `event_meta`, `local_done_*` | owner 5 | metadata and results for keyboard orders (the "Last local order accepted/rejected" text) |
| keyboard form state (page, focus, text fields, status, selected order) | owner 5's display CPU | what to draw while the user types |

## Who ends up seeing what you do

```
 lob_core ─► book_valid / error_code / event_done ─► LED 3 (valid), LED 7 (error), LEDs 15:12 (error code), UART [BBO] "V:" "E:",
                                                      VGA header "BOOK VALID / ERROR xx"
 keyboard ─► form state ─► VGA Order Entry page: focus cursor, field text, shortcut help, status line ("Sent to core",
                           "Invalid price or tick", "Order changed: reselect", ...), "Last local order accepted/rejected by book"
 orders accepted ─► owner 2's memories ─► VGA Orders / Market pages, UART readback
```

So **the Order Entry page on the monitor is your keyboard logic made visible**, and every status message there (`Invalid field`, `Quantity exceeds stored order`, ...) is a code your `keyboard_controls` produced.

## The two input sources, side by side

| | Network source | Keyboard source |
| --- | --- | --- |
| Where built | `itch_decoder` (owner 1) | `keyboard_controls` (you) |
| Clock domain | `eth` → core via FIFO | `ui` (25 MHz) → core via FIFO |
| Sequence field | exchange sequence | local counter (`local_sequence`) |
| Counted by | network counters | `local_done_count` only |
| Parsing needed | Ethernet / IP / UDP / Mold / ITCH | none: it builds the canonical event directly |

A keyboard order **bypasses the whole network pipeline**. That is why the network counters stay exact when you type orders, and why `order_merge` tracks which source an event came from.

## The most important system rule you enforce

> **Nothing downstream ever sees an illegal event.**
> `lob_event_decoder` rejects malformed events; the sequencer rejects impossible ones (duplicate id, missing id, no slot, overflow...) before any commit state runs.

Rejected events never half-update the book, because **all writes happen in commit states that come after every check**.

## How the CPU ties in (a frequent cross-question)

At power-up `lob_core` initializes the memories, then sits in `ST_IDLE` with `event_ready = 0` because `run_enable = 0`. The CPU's firmware waits for `init_done` and for the configuration to reach the Ethernet clock, then writes `1` to `CTRL`. Only then does `event_ready` rise; the first event, from either source, is accepted.
