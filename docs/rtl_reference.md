# RTL reference

One section per area. Read [architecture.md](architecture.md) first for the
big picture. All RTL is Verilog-2001 (`.v` / `.vh`); no SystemVerilog.

## Directory map

`rtl/top/top_system.v` only connects the subsystems below. Each subsystem is
a module with one job.

| Path | Contents |
| --- | --- |
| `top/` | `top_system` (wiring), `board_status` (LEDs, seven-segment display) |
| `clocking/` | `clk_rst_mgr` (MMCM and resets), `phy_refclk_out` (PHY clock pin) |
| `ethernet/`, `network/`, `itch/` | `rmii_rx`, `net_parser`, `moldudp64_decoder`, `itch_decoder`; `network/net_ingest` chains them into one block (frame to event, statistics, feed-loss flag) |
| `common/` | `async_event_fifo`, `config_cdc` (clock crossings), `event_counter` |
| `lob/` | Order book engine: `lob_core` and its memories (see below), `lob_storage_trace` |
| `ui/` | `ps2_keyboard`, `keyboard_controls` (page navigation only), `keyboard_diag`, `order_merge` (network events + journal metadata) |
| `display/` | `display_system` (keyboard, display CPU, video), `ui_registers`, `ram_ports`, `book_views`, `status_to_ui`, `kitty_ui_cpu`, `kitty_video`, history/level memories |
| `telemetry/` | `uart_system` (+ `readback_engine`), `uart_telemetry` (status line), `uart_tx`, `uart_readback` |
| `bus/` | MMIO slaves for the LOB and network counters |
| `cpu/` | `cpu_system` (CPU, memories, MMIO), `core/` the RV32IM pipeline and bus |

## Canonical event (256 bits)

Defined in `rtl/lob/lob_defines.vh`, most significant bit first:

| Bits | Field |
| --- | --- |
| 255:252 | version (must be 1) |
| 251:248 | opcode: 1 add, 2 execute, 3 cancel, 4 delete, 5 replace |
| 247 | side (0 bid, 1 ask) |
| 246:240 | reserved (must be 0) |
| 239:176 | order ID |
| 175:112 | new order ID (replace only) |
| 111:80 | shares |
| 79:67 | price index (13 bits) |
| 66 | price-out-of-window flag |
| 63:32 | feed sequence number |

Events with a wrong version, non-zero reserved bits, zero shares where shares
are required, or an invalid opcode fail with `FAIL_EVT_FORMAT` /
`FAIL_INVALID_OP`.

## LOB engine (`rtl/lob`)

| Module | Job |
| --- | --- |
| `lob_event_decoder` | Validates the event and splits it into fields |
| `lob_hash_table` | 1024 sets × 8 ways + stash; XOR-fold of the 64-bit ID (`HASH_OID`) picks the set |
| `lob_slot_table` | 47-bit entry per order: valid, side, price index, shares |
| `lob_free_list` | LIFO stack of free slot numbers |
| `lob_price_ram` | 16384 quantities (bid half and ask half); initialisation takes 16384 cycles after reset |
| `lob_occupancy` | 256-leaf / 256-bit / 8-bit bitmap tree with priority encoders |
| `lob_bbo` | Best bid/ask and quantities; searches the occupancy tree when a best level empties |
| `lob_core` | Sequencer: for each opcode it steps through prefetch → check → commit states (add ≈ 6 states, execute/cancel/delete ≈ 10, replace ≈ 12), then the BBO search if needed. Small tasks (`fail`, `hash_insert`, `price_write`, ...) name each one-cycle command |

`lob_core` also exposes the last event's RAM write controls (the *storage
trace* sent over UART) and read-only ports used by the display.

## Order sources and keyboard (`rtl/ui`)

* `ps2_keyboard` – oversamples PS/2 clock, accepts 11-bit frames with odd
  parity, rejects bad frames, decodes set-2 make/break/`E0`, tracks Shift,
  and clears pressed keys after a timeout with no clock (unplug).
* `keyboard_controls` – form state machine: focus order, digit entry with a
  cursor, Escape restore, validation, page selection, order browsing, and
  the Enter-once-per-press rule. Output is a canonical event plus a valid bit.
  without losing an accepted event under backpressure.

## Display (`rtl/display`)

* `kitty_ui_cpu` – small RV32 core running `firmware/kitty_ui`
  (`main.c`, built by `build.py` into `kitty_ui.hex`).
* `kitty_video` – pixel clock MMCM (74.25 MHz), double-buffered character and
  plot memories in block RAM, font ROM from `kitty_font.hex`, 1280×720 timing.
* `lob_display_journal` – ring of recent quotes for the History page and graph.
* `lob_level_order_count` – orders per price level for the Levels page.

## CPU memory map

Address decode is in `rtl/cpu/core/sys_bus_interconnect.v`. Unmapped accesses
return a bus error.

| Base | Size | Device |
| --- | --- | --- |
| `0x0000_0000` | 4 KiB | instruction memory (`imem_slave`) |
| `0x2000_0000` | 4 KiB | data memory (`dmem_slave`) |
| `0x4000_0000` | 256 B | LOB (`lob_mmio_slave`) |
| `0x5000_0000` | 256 B | network counters (`net_mmio_slave`) |
| `0x6000_0000` | 256 B | UART telemetry |
| `0x7000_0000` | 256 B | system: `0x00` = SW14/SW15 in bits 1:0, `0x04` = MMCM locked |

**LOB registers** (offset from `0x4000_0000`)

| Off | Name | Notes |
| --- | --- | --- |
| 00 | CTRL | bit 0 enable, bit 2 snapshot request |
| 04 | STATUS | bit 0 init done, 1 book valid, 2 busy, 3 error latched, 4 bid valid, 5 ask valid, 6 event ready, 7 config ready |
| 08 | ERROR_CODE | `[7:0]` code, bit 16 valid, write-1-to-clear |
| 0C | ACTIVE_ORDERS | `[11:0]` |
| 10–1C | SNAP_BID_P/Q, SNAP_ASK_P/Q | reading the first latches a consistent snapshot |
| 20 | SNAP_FLAGS | bid valid, ask valid, `[31:16]` snapshot generation |
| 24 / 28 / 2C | PRICE_BASE / TICK / LOCATE | read-write configuration |
| 30 | EVT_COUNT | events processed |
| 34–40 | LIVE_BID_P/Q, LIVE_ASK_P/Q | unsynchronised current values |
| 44 | SPREAD | ask − bid when both valid |

**Network counters** (offset from `0x5000_0000`): `00` RX frames, `04` CRC
errors, `08` Mold messages, `0C` sequence gaps, `10` length errors, `14` PHY
errors, `18` overflow errors, `1C` Mold truncations, `20` status flags, `24`
UDP length errors, `28` UDP checksum errors.

The same values appear in the source as `REG_*` localparams; if the two ever
disagree, the RTL is right.

## Python <-> RTL contract

`sim/golden/` holds the golden vectors (`golden_vectors.json`) and generators
that turn them, and random event sequences checked against an independent
dictionary model, into RTL input files. `tb_lob_golden` and `tb_lob_random`
compare RTL results against them. If you change the event layout, hash
function or capacity, update `lob_defines.vh` and these generators together.
