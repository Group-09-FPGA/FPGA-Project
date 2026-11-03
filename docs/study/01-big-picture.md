# Chapter 1: The big picture

## The one-paragraph version

A stock exchange sends a stream of tiny messages ("order 7 buys 100 shares at
$90.50", "order 7 cancelled"). This FPGA listens on Ethernet, decodes each
message in hardware, and keeps a live **order book**: every open order, plus the
best buy and best sell price. You can also type orders on a USB keyboard. A
small RISC-V CPU supervises, and everything is shown on a VGA monitor, on UART,
and on the board's LEDs.

## Analogy: a post office with a ledger

| Real thing | In this design |
| --- | --- |
| Mail arrives in a van | Ethernet frames (`rmii_rx`) |
| Sorting room opens envelopes layer by layer | `net_parser` (Ethernet, IP, UDP) and `moldudp64_decoder` |
| A clerk reads the letter and writes a standard form | `itch_decoder` builds the 256-bit **canonical event** |
| A mailbox between two departments that use different clocks | `async_event_fifo` |
| A second person hands in forms over the counter (the keyboard) | `keyboard_controls` + `order_merge` |
| The ledger and its index cards | `lob_core` and its memories |
| A supervisor who checks the ledger and flips the "open" sign | the RISC-V CPU (`cpu_system`) |
| Noticeboards showing the ledger | VGA (`display_system`), UART, LEDs |

## Block diagram

```
Ethernet RMII ──► net_ingest ──────────────┐   (eth clock → core clock inside)
                                           ▼
USB keyboard ─► display_system ──► order_merge ──► lob_core ──┬─► book_views (history, per-level counts)
                (keyboard form,                    (order book)│
                 display CPU, video)                          ├─► uart_system ──► USB-UART
                    ▲                                         ├─► cpu_system  (RISC-V supervisor)
                    └──── status_to_ui, ram_ports ◄───────────┘
                                                              └─► board_status ──► LEDs, 7-segment
VGA monitor ◄── display_system (kitty_video)
```

`rtl/top/top_system.v` contains only this wiring.

## Four clock domains

| Name | Frequency | Who lives there |
| --- | --- | --- |
| `eth` | 50 MHz (from the PHY clock) | `rmii_rx`, `net_parser`, `moldudp64_decoder`, `itch_decoder` |
| `core` | 50 MHz | `lob_core`, CPU, UART, arbiter |
| `ui` (named `clk_vga` in `clk_rst_mgr`) | 25 MHz | keyboard, display CPU, display memories |
| `pixel` | 74.25 MHz | `kitty_video` scan-out (1280x720 @ 60 Hz) |

`eth` and `core` are the same speed but different clocks; that is enough to
require careful crossings (chapter 2).

## One order, start to finish

Suppose a laptop sends: **Add order 0x2001, Buy, 300 shares at $90.5000**.

1. **`rmii_rx`** collects 2-bit RMII pieces into bytes, finds the start-of-frame,
   checks the Ethernet CRC, and stores the frame in a small buffer.
2. **`net_parser`** reads the Ethernet, IPv4 and UDP headers, checks the IP
   checksum and port, and streams out only the UDP payload.
3. **`moldudp64_decoder`** reads the session/sequence header. Sequence matches
   expectation, so it passes each length-prefixed message along. (A skipped
   sequence number would raise a *feed loss* and stop the book.)
4. **`itch_decoder`** sees message type `A`. It turns the price into an index:
   `(90.5000 − base) / tick`. The result is the **256-bit canonical event**:
   opcode 1 (add), side buy, id 0x2001, 300 shares, price index 605.
5. **`async_event_fifo`** carries that event from the `eth` clock to the `core` clock.
6. **`order_merge`** (its `order_source_arbiter`) picks it, since the keyboard FIFO is empty.
7. **`lob_core`** runs its ADD sequence: look up id 0x2001 in the hash table (must be
   absent), take a free slot from the free list, add 300 to the price-level total
   for index 605, write the slot, write the hash entry, set the occupancy bit, update
   the best bid.
8. **Outputs update**: `uart_telemetry` prints a `[BBO]` line, `book_views` records a
   history sample, the display CPU redraws the market page, the 7-segment shows
   the new best bid.

A keyboard order follows the same path from step 5 onward: it skips steps 1-4
because it is already a canonical event built by `keyboard_controls`.

## Where does the CPU fit?

The CPU is **not** in the order data path. But it does one essential job: its
firmware (`firmware/lob_test/firmware_monitor.s`) waits for the book to finish
initializing and for the configuration to reach the `eth` domain, then writes
`1` to the LOB `CTRL` register. That sets `accel_enable`, which feeds `run_enable`
on `lob_core`. **Until the CPU does that, `lob_core.event_ready` stays low and no
order, network or keyboard, is accepted.** After that, the CPU just copies
status into memory and mirrors it to the LEDs/7-segment.

## The canonical event (the glue of the whole design)

Every block downstream of the decoder speaks this 256-bit format
(`rtl/lob/lob_defines.vh`):

| Bits | Field | Meaning |
| --- | --- | --- |
| 255:252 | version | must be 1 |
| 251:248 | opcode | 1 add, 2 execute, 3 cancel, 4 delete, 5 replace |
| 247 | side | 0 buy (bid), 1 sell (ask) |
| 239:176 | order id | 64-bit |
| 175:112 | new order id | used by replace |
| 111:80 | shares | |
| 79:67 | price index | `(price − base) / tick`, 13 bits (0..8191) |
| 66 | out-of-window | set when the price does not fit the 8192-level window |
| 63:32 | sequence | feed sequence number (or a local counter for keyboard orders) |

Reserved bits must be 0; `lob_event_decoder` rejects an event that breaks the rules.
