# Chapter 8: The display (`rtl/display/`)

The VGA picture is built entirely from real FPGA memory. There is **no frame buffer fed by a laptop**: a small second
CPU reads the order book's own RAMs and draws text and charts into video memory.

## The pipeline

```
 book memories ─► ram_ports ─► kitty_ui_cpu (runs firmware/kitty_ui)
 ui_registers ───────────────────┘        │ writes characters / chart points
 (keyboard form, status, counters)         ▼
                                      kitty_video ─► VGA pins (1280x720 @ 60 Hz)
```

*Analogy:* a news editor (the UI CPU) reads wire reports (the registers and RAM), types the front page into a layout
(the cell and plot memories), and a printing press (`kitty_video`) streams the page onto the screen sixty times a second.

## `display_system`

The wrapper around the whole keyboard + display chain, instantiated once as `u_display`.

| Inside | Role |
| --- | --- |
| `u_ps2_receiver`, `u_ps2_decoder` | keyboard input (chapter 5) |
| `u_frame_errors` | counts PS/2 frame errors |
| `u_keyboard` | `keyboard_controls`, the order form |
| `u_registers` | `ui_registers`, packs state for the UI CPU |
| `u_ram_ports` | `ram_ports`, shares the book's read ports |
| `u_ui_cpu` | `kitty_ui_cpu` |
| `u_pixel_clock`, `u_video` | `kitty_pixel_clock`, `kitty_video` |

## `ui_registers`: the UI CPU's view of the world

A purely combinational block (`always @*`) that builds a 2048-bit vector: **52 words of 32 bits**. The UI firmware reads
word *n* at address `0x1000_0000 + 4n`. Examples: word 0 = `{status, scan_busy, selected_valid, focused_valid, editing, side,
action, focus, page}`; words 3-10 = price, quantity, ids; words 15-21 = book valid, bid/ask price/qty, orders, event count;
words 22-25 network counters; 33-48 the four text fields (16 chars each); 49 keyboard frame errors; 50-51 the last keyboard
submission result. The numbers are the **contract with `firmware/kitty_ui/main.c`**; change both together.

## `ram_ports`: who reads the book's memory?

Two requesters want the same read ports: the UART readback and the display CPU.

- If `readback_active`, the readback owns the ports (`rb_slot`, `rb_hash`, `rb_scan`, `rb_stash`, `rb_price`, `rb_free`).
- Otherwise the display CPU's request (`ui_kind`, `ui_address`) is granted: `ui_grant = ui_request && !readback_active && !ui_hold`.
- `ui_hold` is the keyboard order-browser or validation using the slot/hash ports itself; the UI CPU waits.
- Output addresses: `slot_addr`, `hash_set`, `stash_idx`, `price_addr`, `free_addr`, `quote_addr`, `event_addr`.
- Returned data is routed by *kind*: display kinds are numbers (1 slot, 2 hash, 3 stash, 4 price, 5 free, 6 level count, 7 quote
  history, 8 event history); readback kinds are letters (`S H X P F L Q E`). `hash_valid` (the valid bit of each way) feeds the `B` scan.

## `kitty_ui_cpu`: the UI processor

**Job:** run the presentation firmware.

- It is **another instance of `cpu_core`** (the same RV32IM pipeline as the supervisor).
- It has a 64 KiB memory (`memory[0:16383]`, 32-bit words) loaded from `kitty_ui.hex`. Reads/writes below `0x0001_0000`
  go there.
- **MMIO map:**

| Address | What |
| --- | --- |
| `0x1000_0000 + 4n` (n < 64) | read `registers` word *n* |
| `0x1000_0100` write | request a RAM read: `wdata[19:16]` = kind, `wdata[13:0]` = address |
| `0x1000_0104` read | which video bank is on screen |
| `0x1000_0108` write | publish a finished frame: bank, market-page flag; increments `completed_frames` |
| `0x1000_0200 + 4k` read | words of the last RAM read result |
| `0x3000_0000 + 4·cell` write | write one character cell |
| `0x4000_0000 + 4·x` write | write one chart column |

- **RAM read protocol:** write the request; `ram_request` stays high until `ram_ports` grants it; after four wait cycles the data
  (up to 608 bits) is captured into `result`, and the firmware reads it back in 32-bit words.
- It has **no way to inject orders**: it can only read book RAM and write video buffers. That is a deliberate safety property.

## `kitty_video`: the screen

**Resolution:** 1280x720 visible in a 1650x750 total frame (74.25 MHz pixel clock). `x`, `y` count pixels; `hs`/`vs` are
sync pulses; `active` marks the visible area.

**Structure**

- **Character grid:** 160 columns x 45 rows of 8x16-pixel cells. Each cell is 16 bits: character code + colour attribute.
  Stored in block RAM (`xpm_memory_sdpram` `u_cells`) written by the UI CPU on `ui_clk` and read by the pixel logic on `pixel_clk`
  (two clocks on one memory).
- **Font:** `font[0:4095]` loaded from `kitty_font.hex`; each glyph row gives 8 pixels of 4-bit coverage (anti-aliasing).
- **Chart memory:** `plots[0:2047]`: for every chart column a Y position and a vertical range, plus a colour code.
- **Double buffering:** two banks of cells. The UI CPU draws into the hidden bank, then asks to present it
  (`requested_bank`). At the start of vertical blank (`x==0 && y==720`) the video logic swaps `front_bank`.
  This prevents tearing. The request crosses clocks via `u_present_cdc`; `front_bank` returns through a 2-flop synchronizer.
- **Pipeline:** cell lookup → font lookup → blend foreground/background by coverage (`blend`) → `stroke` overrides with the chart colour
  → `red/green/blue` registers. The extra pipeline stages (`*1`, `*2` registers) line up all signals in time.
- **Palette:** `palette()` maps attribute numbers to 12-bit colours (a dark theme: background `#191724`, foreground `#e0def4`,
  rising green-blue, falling pink).

`kitty_pixel_clock` generates the 74.25 MHz clock: `100 MHz x 37.125 / 5 / 10`. It also builds a 4-flop reset synchronizer.

## `book_views`, `lob_level_order_count`, `lob_display_journal`

These add memories that the order book itself does not need but the display and readback do.

**`lob_level_order_count`** ("how many orders at this price?"): `counts[0:16383]` of 12 bits. Each completed add/remove sends
`level_count_delta_valid/inc/addr`; a 3-stage pipeline reads the old count, adds or subtracts 1 (with **forwarding** so back-to-back
updates to the same level are correct), and writes it back. A second read port on the UI clock feeds the Levels page.

**`lob_display_journal`** (history):

- `quote_mem[0:127]` stores a 175-bit snapshot of the book (valid flags, bid/ask price and qty, order count, event number);
  `event_mem[0:255]` stores each event's number, side/shares/price and its 316-bit write trace.
- Timing: the trace is stable one clock after `event_done` (`done_pipe[1]`), but the best-price pipeline needs more time, so quotes are
  captured eight clocks later (`done_pipe[7]`). `quote_next`/`event_next` are ring write pointers; `quote_count`/`event_count`
  saturate at 128/256.

**`book_views`** simply instantiates both and exposes `history_meta = {quote_count, event_count, quote_next, event_next}`.

## `status_to_ui`

Copies slow-changing core-domain status into the UI domain with seven `config_cdc` instances (all named `u_*_cdc`):
`book` (175 bits: valid flags, prices, quantities, order count, event count), `net` (128), `pipe` (96), `error` (8), `config`
(`{price base, tick}`), `history` (32), `local_done` (41). The UI CPU only ever sees clean, UI-clock copies.

## Example: a new order appears on the Market page

1. `lob_core` finishes, pulses `event_done`.
2. Eight clocks later `lob_display_journal` stores a quote sample.
3. `status_to_ui` carries the new best bid/ask into `ui_book`; `ui_registers` word 16-19 change.
4. The UI firmware, on its next frame, reads those registers and the quote history through `ram_ports`, rewrites the text cells
   and chart columns of the hidden bank, then publishes the frame.
5. At the next vertical blank `kitty_video` swaps banks; the screen shows the new prices and a longer chart.
