# RTL reference

One section per area. Read [architecture.md](architecture.md) first for the
big picture. All RTL is Verilog-2001 (`.v` / `.vh`); no SystemVerilog.

## Directory map

| Path | Contents |
| --- | --- |
| `rtl/top/top_system.v` | Wires everything together; owns the clock-domain crossings |
| `rtl/clocking/clk_rst_mgr.v` | MMCM (100 MHz → 50/50/25 MHz + 45° PHY clock), reset synchronizers, PHY reset |
| `rtl/ethernet/rmii_rx.v` | RMII receiver, CRC-32, runt/error/overflow rejection |
| `rtl/network/` | `net_parser` (Ethernet/IPv4/UDP), `moldudp64_decoder` (sequence check, fail-stop) |
| `rtl/itch/itch_decoder.v` | ITCH message → canonical 256-bit event |
| `rtl/common/` | `async_event_fifo` (event crossing), `config_cdc` (bundled-value crossing) |
| `rtl/lob/` | Order book engine and its memories |
| `rtl/ui/` | PS/2 keyboard, form logic, network/local order arbiter |
| `rtl/display/` | 720p video, presentation CPU, journal and per-level order count |
| `rtl/telemetry/` | UART status line and RAM readback |
| `rtl/bus/` | MMIO slaves for the LOB and network counters |
| `rtl/cpu/core/` | RV32IM CPU, bus interconnect, memories, seven-segment driver |

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
| `lob_core` | Sequencer: for each opcode it steps through prefetch → check → commit states (add ≈ 6 states, execute/cancel/delete ≈ 10, replace ≈ 12), then the BBO search if needed |

`lob_core` also exposes the last event's RAM write controls (the *storage
trace* sent over UART) and read-only ports used by the display.

## Order sources and keyboard (`rtl/ui`)

* `ps2_keyboard` – oversamples PS/2 clock, accepts 11-bit frames with odd
  parity, rejects bad frames, decodes set-2 make/break/`E0`, tracks Shift,
  and clears pressed keys after a timeout with no clock (unplug).
* `keyboard_controls` – form state machine: focus order, digit entry with a
  cursor, Escape restore, validation, page selection, order browsing, and
  the Enter-once-per-press rule. Output is a canonical event plus a valid bit.
* `order_source_arbiter` – round-robins network and local FIFOs into the LOB
  without losing an accepted event under backpressure.

## Display (`rtl/display`)

* `kitty_ui_cpu` – small RV32 core running `software/baremetal/kitty_ui`
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
| 04 | STATUS | init done, book valid, busy, fail-stop, bid valid, ask valid, event ready |
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

## Python ↔ RTL contract

`software_lob/` is a pure-Python reference book. `sim/golden/` converts its
scenarios to RTL vectors; the testbenches `tb_lob_golden` and `tb_lob_random`
compare RTL results against it. If you change event layout, hash function or
capacity, change `lob_defines.vh` and the Python packer together.
