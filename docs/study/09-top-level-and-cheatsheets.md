# Chapter 9: Top level, cheat sheets and self-test

## `top_system.v`: only wiring

It has no logic of its own except instantiating subsystems and a counter. Read it top to bottom:

| Section | Instance | What it connects |
| --- | --- | --- |
| clocks | `u_clk_mgr`, `u_phy_refclk` | 100 MHz in; four clocks and resets out; PHY clock pin |
| network input | `u_ingest` (`net_ingest`) | Ethernet pins → `net_*` event stream, `feed_loss`, `net_diag`, `pipe_stats` |
| sources | `u_order_merge` | network + keyboard → one event stream `evt_*` |
| order book | `u_lob_core` | the book; read ports `slot_addr/hash_set/...` come from `display_system` |
| counter | `u_core_events` | counts completed events |
| CPU | `u_cpu_system` | supervisor; returns `cfg_*` (price base, tick, locate) and `accel_enable` |
| history | `u_views` (`book_views`) | per-level counts and quote/event journals |
| status copy | `u_status_to_ui` | core state → UI clock |
| UART | `u_uart` | status line and readback |
| display | `u_display` | keyboard, display CPU, video |
| board | `u_board_status` | LEDs, seven-segment |

## The signals worth memorizing

### Handshake signals

| Signal | From → to | Meaning |
| --- | --- | --- |
| `evt_valid`, `evt_data[255:0]`, `evt_ready` | `order_merge` → `lob_core` | one canonical event (the book's input) |
| `net_valid/data/ready` | `net_ingest` → `order_merge` | network events |
| `ui_valid/data/ready` | `display_system` → `order_merge` | keyboard events |

### Control / health

| Signal | Meaning |
| --- | --- |
| `accel_enable` (`run_enable` inside `lob_core`) | CPU says "start accepting orders" |
| `feed_loss` | sticky network-loss flag; fail-stops the book |
| `lob_init_done` | all five memories initialized |
| `lob_book_valid` | book is trustworthy |
| `lob_error_valid`, `lob_error_code` | something was rejected |
| `lob_event_done` | one-clock pulse: an event completed |
| `lob_busy` | sequencer is mid-event |
| `mmcm_locked` | clocks stable |

### Order-book outputs

| Signal | Meaning |
| --- | --- |
| `lob_bid_valid/price/qty`, `lob_ask_valid/price/qty` | best bid and offer |
| `lob_active_orders[11:0]` | live orders |
| `lob_storage_trace[315:0]` | what the last event wrote |
| `core_event_count` | completed events |

### Configuration

| Signal | Meaning |
| --- | --- |
| `cfg_price_base`, `cfg_tick`, `cfg_locate` | written by the CPU; decide price index conversion and stock filtering |
| `cfg_ready` | the configuration has reached the Ethernet clock domain |

### Shared read ports (display and UART)

`slot_addr`, `hash_set`, `stash_idx`, `price_addr`, `free_addr`, `quote_addr`, `event_addr`
(addresses from `ram_ports`) and `slot_data`, `hash_ways`, `stash_data`, `price_data`, `free_data`, `level_count`,
`quote_data`, `event_history` (data back).

## Every `always` block, by file (what it is for)

| File | Block | Job |
| --- | --- | --- |
| `config_cdc` | source / destination | hold-and-handshake copy across clocks |
| `async_event_fifo` | write, read, sync x2, RAM write | FIFO pointers and full/empty; Gray synchronizers |
| `clk_rst_mgr` | reset syncs x3, PHY counter | clean resets; PHY power-up delay |
| `rmii_rx` | CRC, byte assemble, FSM | frame reception and checking |
| `net_parser` | RAM write, FSM | header parsing and checksum, payload store/replay |
| `moldudp64_decoder` | FSM | sequence tracking and message framing |
| `itch_decoder` | FSM | message → canonical event, price index divide |
| `lob_event_decoder` | `always @*` | legality check of an event |
| `lob_hash_table` | match logic, init/stash | find or allocate an id entry |
| `lob_slot_table`, `lob_price_ram`, `lob_free_list` | memory + init FSM | simple storage |
| `lob_occupancy` | search FSM, update, level-1/0 bits | find best price quickly |
| `lob_bbo` | direct/search update, price pipeline x2 | best prices |
| `lob_core` | main FSM | the per-operation scripts |
| `lob_storage_trace` | collector | 316-bit write record |
| `ps2_receiver`, `ps2_key_decoder` | frame decode; scan-code state | keys |
| `keyboard_controls` | main block | form, navigation, validation |
| `form_parser`, `price_divider`, `bin_to_decimal` | parse / divide / convert | helpers |
| `order_source_arbiter`, `order_merge` | choose source; record result | two sources, one stream |
| `cpu_core` | fetch, decode regs, execute, WB, bus arbiter | the pipeline |
| `lob_mmio_slave`, `net_mmio_slave`, `cpu_system` sys window | register interfaces | CPU ↔ hardware |
| `uart_tx`, `uart_telemetry`, `uart_readback`, `readback_engine` | serializer, formatter, parser, engine | UART |
| `lob_display_journal`, `lob_level_order_count` | rings and counters | display-only memories |
| `kitty_ui_cpu` | MMIO/RAM request block | UI CPU's I/O |
| `kitty_video` | timing, pipeline, colour | VGA scan-out |

## Why each module is instantiated where it is

| Module | Placed in | Reason |
| --- | --- | --- |
| `async_event_fifo` x2 | `net_ingest`, `order_merge` | events are the only thing that cannot be sampled; each source clock needs a queue to the core |
| `config_cdc` | everywhere a value changes clock | values only need their latest snapshot |
| `event_counter` | three places | the same 32-bit counter pattern |
| `lob_storage_trace` | `lob_core` | needs to watch the same write controls the RAMs see |
| `book_views` | `top_system` | needs core signals and UI-clock reads |
| `ram_ports` | `display_system` | decides display vs. readback ownership of the book's read ports |
| `uart_tx` | `uart_telemetry` | only the telemetry module writes bytes to the serial port |
| second `cpu_core` | `kitty_ui_cpu` | the UI needs a programmable renderer; reusing the verified CPU avoids a new design |

## Self-test: can you answer these?

1. Why does `async_event_fifo` use Gray-coded pointers?
2. What stops a corrupted UDP packet from reaching the order book?
3. In an ADD, why does `lob_core` wait between `ADD_C1` and `ADD_C4`?
4. What does `triggers_search` mean, and who uses it?
5. Why must the CPU firmware write `1` to the LOB `CTRL` register before any order is accepted?
6. How does the design make sure holding Enter submits only one order?
7. What is the difference between `config_cdc` and `async_event_fifo`, and when must you use each?
8. Why can the display CPU not inject orders?
9. If you rename `u_event_fifo`, what breaks, and where?
10. What does `readback_kind == "B"` do differently from the other readback kinds?

**Answers (check yourself):** (1) Only one bit changes per step, so a pointer caught mid-update is wrong by at most one entry,
which is safe for full/empty. (2) `net_parser` stores the payload and only replays it after the UDP checksum is verified; frames
also need a good Ethernet CRC. (3) The hash read takes two cycles and the price RAM three, so data is not valid until then.
(4) The level being emptied is the current best; `lob_core` reads it from `lob_bbo` and then asks `lob_occupancy` for the next best.
(5) `event_ready` requires `run_enable`, which comes from that register bit; the book would sit idle otherwise.
(6) `ps2_key_decoder`'s `held` bitmap fires `key_valid` only on the first make code; the key must be released first.
(7) `config_cdc` copies the latest value of a bundle (counters, status); the FIFO preserves every item in order (events).
(8) It has no connection to the event path; it only reads book RAM and writes video memory.
(9) The timing exceptions in `fpga/nexys_a7_system.xdc` match the name, so the FIFO's pointer crossings lose their constraint
and synthesis shows negative slack.
(10) It scans 32 hash sets in one request and returns an occupancy bitmap, instead of reading one address.
