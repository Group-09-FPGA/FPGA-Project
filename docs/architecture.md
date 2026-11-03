# How the design works

This page explains the whole system in plain language, then points to the
RTL files that implement each part. For signal-level detail see
[rtl_reference.md](rtl_reference.md).

## The idea

A stock exchange publishes a stream of small messages: "order 7 wants to buy
100 shares at $90.50", "order 7 was cancelled", and so on. A **limit order
book** (LOB) is the data structure that remembers every open order, so you can
ask "what is the best bid and best ask right now?".

This project does the whole job in hardware on a Nexys A7-100T (Artix-7)
board: network packets go in on the Ethernet port, a fixed pipeline of
circuits decodes them, and a hardware order book updates its memories. A
small RISC-V CPU supervises, and results appear on a VGA monitor and over
UART. Orders can also be typed on a USB keyboard.

```
 Ethernet ─► rmii_rx ─► net_parser ─► moldudp64_decoder ─► itch_decoder ─┐
 (RMII, 50 MHz clock domain "eth")                                       │ 256-bit event
                                                                         ▼
                                     async_event_fifo (eth → core clock crossing)
                                                                         │
 USB keyboard ─► ps2_keyboard ─► keyboard_controls ─► local FIFO ───────►│
                                                                         ▼
                                              order_source_arbiter (one event at a time)
                                                                         ▼
                                                              lob_core (order book)
                                                                │             │
                          RV32IM CPU ◄── MMIO ──────────────────┘             ├─► uart_telemetry / uart_readback
                          (supervisor)                                        └─► kitty_ui_cpu + kitty_video ─► VGA 720p
```

## Clock domains

| Domain | Frequency | Used by |
| --- | --- | --- |
| `eth` | 50 MHz (RMII reference) | `rmii_rx`, parsers, ITCH decoder |
| `core` | 50 MHz | LOB, CPU, arbiter, UART, keyboard |
| `vga` | 25 MHz | presentation CPU and display journal |
| pixel | 74.25 MHz | `kitty_video` (1280×720 @ 60 Hz) |

`eth` and `core` run at the same frequency but are separate clocks, so every
signal between them goes through `async_event_fifo` (events) or `config_cdc`
(counters and status). Use those two modules for any new crossing; do not add
hand-made synchronizers.

## 1. Getting an order from the wire

1. **`rmii_rx`** turns the PHY's 2-bit RMII signals into bytes, checks the
   Ethernet CRC-32, and drops runts, errors and overflows (each has a counter).
2. **`net_parser`** reads the Ethernet, IPv4 and UDP headers, verifies lengths
   and checksums, and passes only the UDP payload on.
3. **`moldudp64_decoder`** reads the MoldUDP64 header (session, sequence
   number, message count). If a sequence number is skipped it raises a
   *feed loss*, because the book can no longer be trusted.
4. **`itch_decoder`** reads one ITCH message (Add `A`, Add with attribution
   `F`, Execute `E`, Execute with price `C`, Cancel `X`, Delete `D`, Replace
   `U`) and builds a **canonical event**: a fixed 256-bit word with an
   opcode, side, order IDs, shares, a price *index* and a sequence number.
   The price index is `(price − base) / tick`; prices outside the 8192-level
   window are flagged. The layout lives in `rtl/lob/lob_defines.vh`.

## 2. The order book

`lob_core` is a state machine that takes one canonical event at a time and
updates five memories. It never searches linearly, so the time per event is
bounded.

| Memory | Size | Purpose |
| --- | --- | --- |
| Hash table (`lob_hash_table`) | 1024 sets × 8 ways + 8-entry stash | Order ID → slot number |
| Slot table (`lob_slot_table`) | 2048 slots | Side, price index and remaining shares of each order |
| Free list (`lob_free_list`) | 2048 entries | Stack of unused slot numbers |
| Price RAM (`lob_price_ram`) | 8192 levels per side | Total shares at each price |
| Occupancy bitmaps (`lob_occupancy`) | 3-level tree | Which price levels are non-empty, for fast best-price search |

`lob_bbo` keeps the best bid and ask. When the best level empties, the
occupancy tree finds the next one without scanning price RAM.

**Fail-stop.** If an event is impossible (duplicate order ID, unknown ID, no
free slot, quantity overflow or underflow, price outside the window, lost
feed), the book is marked invalid and stops accepting events until the board
is reset. It never guesses. Error codes are in `lob_defines.vh` (`FAIL_*`).

## 3. Local orders from the keyboard

`ps2_keyboard` receives the keyboard through the board's USB-HID-to-PS/2
bridge: it checks start/parity/stop bits, decodes scan-code set 2 (including
key release and the `E0` extended prefix) and clears held keys when the
keyboard is unplugged. `keyboard_controls` owns the order form (action, side,
price, quantity, IDs), the focus/cursor state and the page selection. When
Enter is pressed on a valid form it builds a canonical event and pushes it
into a small local FIFO.

`order_source_arbiter` chooses between the network FIFO and the local FIFO
and hands exactly one event to `lob_core`. `top_system` remembers which
source is active so the completion result goes back to the right place.
Keyboard events skip the Ethernet parser, so the network counters only ever
count real network traffic. Details and the full key list are in
[keyboard_vga_controls.md](keyboard_vga_controls.md).

## 4. The CPU

A 3-stage RV32IM CPU (`rtl/cpu/core`) runs `firmware/lob_test`
firmware. It is only a supervisor: it reads status and counters over the
memory-mapped bus and mirrors them to LEDs and the seven-segment display. The
order path never goes through it. The multiplier/divider (`rv32m_unit`) is
multi-cycle and stalls the pipeline; `hazard_unit` and `forwarding_unit`
handle data hazards. Register map: [rtl_reference.md](rtl_reference.md#cpu-memory-map).

## 5. Showing the result

* **VGA.** A second, tiny CPU (`kitty_ui_cpu`) runs `firmware/kitty_ui`.
  It reads the real hash, slot, price and history memories (through read-only
  ports on the LOB), draws characters and graph points into video memory, and
  `kitty_video` scans that memory out at 1280×720. Static text and the font
  are compiled in; every number and graph point comes from the FPGA.
* **UART** (115200 baud). `uart_telemetry` prints a `[BBO]` status line after
  each event. `uart_readback` answers single-address RAM reads so a PC can
  rebuild the book. Protocol: [storage_trace_uart.md](storage_trace_uart.md).

## Verification

* `sim/unit/*` – one testbench per block.
* `sim/golden/*` – committed event and expected-result vectors, plus Python
  generators for random sequences, compared against the RTL.
* `sim/integration/tb_system_top.v` – Ethernet frames and PS/2 keystrokes into
  the full `top_system`.
* Vivado produces routed timing and DRC reports; see [commands.md](commands.md).

What has and has not been checked on a real board is tracked only in
[HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md).
