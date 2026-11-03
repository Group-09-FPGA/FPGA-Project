# Chapter 7: UART (`rtl/telemetry/`)

The board's USB cable also carries a serial port at **115200 baud, 8N1**. The FPGA uses it two ways:

1. it **prints a status line** after every order-book event (the `[BBO] ...` line);
2. it **answers memory queries** from a laptop (`?S07FF`), so tools can rebuild the book from real FPGA RAM.

Files: `uart_tx.v`, `uart_telemetry.v`, `uart_readback.v`, `readback_engine.v`, `uart_system.v`.

## `uart_tx`: the serial transmitter and its queue

**Job:** accept bytes, store up to 64 in a FIFO, and send them one at a time as serial frames.

**Analogy:** a printer with a paper tray (the FIFO) and a print head that is much slower than the computer feeding it.

**Serial frame (8N1):** line idles at 1; a **start bit** 0; eight data bits, LSB first; a **stop bit** 1. One bit lasts
`CLKS_PER_BIT` clock cycles (50 MHz / 115200 ≈ 434).

| Signal | Meaning |
| --- | --- |
| `wr_en`, `wr_data` | push a byte (the caller checks `full`) |
| `full`, `empty`, `busy` | FIFO full, FIFO empty, a byte is being shifted out |
| `head_byte` | oldest queued byte (the CPU can peek at it) |
| `txd` | the serial output pin |
| `mem`, `wptr`, `rptr`, `count` | the FIFO storage and pointers |
| `state` (`IDLE/START/DATA/STOP`), `baud_cnt`, `bit_idx`, `shift` | the serializer |

**Always blocks**

- *FIFO block:* a write stores `wr_data` and advances `wptr`; a read (when the serializer is idle and the FIFO is not
  empty) advances `rptr`; `count` goes up on write-only, down on read-only, and stays put when both happen.
- *Serializer block:* `IDLE` loads the byte into `shift`; `START` holds the line low for one bit time; `DATA` drives
  `shift[bit_idx]` for eight bit times; `STOP` drives high for one bit time. `bit_done` (`baud_cnt == CLKS_PER_BIT-1`)
  ends each bit.

**Test:** `sim/unit/tb_uart_tx.v` samples the serial line at mid-bit and checks every frame.

## `uart_telemetry`: the status-line printer (and CPU's serial port)

**Job:** build a text line from the latest book state and push it into `uart_tx`; also give the CPU a memory-mapped window
to write its own bytes.

**Why it is here:** this is how the laptop dashboard knows what the FPGA book looks like without any wires beyond USB.

**The line** (one per event, plus a heartbeat once per second):

```
[BBO] B:<bid price>.<..> | A:<ask..> | V:<valid> | E:<error> | QB:<bid qty> | QA:<ask qty> | N:<orders>
      | CRC:<..> | UDP:<..> | IP:<..> | <pipeline counters> | T:<316-bit write trace> | BASE:<..> | TICK:<..>
```

**How it works**

- **Trigger (`telem_trigger`):** an event completed (`hw_telem_trigger` = `event_done`), then wait **six clocks**
  (`event_settle` shift register) so the best-price pipeline and counters have settled; also fire on a 1-second
  heartbeat, or whenever `book_valid`/`error_code` changed.
- **Latch (`lat_*`):** copy all inputs at that moment so the line is internally consistent while it prints (about 320 characters, roughly 28 ms at 115200 baud).
  A second set (`pend_*`) holds one more update that arrives while printing.
- **Formatter (`always @(*)` → `hw_char`):** `telem_step` is a counter; a big `case` returns the character for
  that step: literals like `"["`, or hex digits of a latched value via `hex2ascii`/`hex_digit`. Each step is
  pushed into the TX FIFO.
- **Byte sources into the FIFO** (priority order): readback response bytes, then bytes the CPU writes at `0x6000_0000`,
  then the automatic line (`hw_wr_en`). `readback_line_active` keeps one readback line contiguous.
- **MMIO window:** `0x00` write a byte / read head, `0x04` status {empty, full, busy}, `0x08` auto-telemetry enable.
  The request is registered first (`req_pending`, `req_addr_d`) to keep the CPU bus path short.

After the refactor the TX FIFO and serializer are in `uart_tx`; this module owns only the text formatter and the bus window.

## `uart_readback`: the laptop's query port

**Job:** decode a query like `?S07FF\n` and print the answer `@S07FF=<hex>\r\n`.

**Query types**

| Type | Address range | Returns |
| --- | --- | --- |
| `S` | 0-2047 | slot record (12 hex digits) |
| `H` | 0-1023 | all 8 hash ways of one set (152 digits) |
| `X` | 0-7 | stash entry |
| `P` | 0-16383 | price-level quantity |
| `L` | 0-16383 | orders at that price level |
| `F` | 0-2047 | free-stack entry |
| `Q` | 0-127 | quote-journal record |
| `E` | 0-255 | event-journal record (99 digits) |
| `B` | 0-31 | bitmap of which hash sets are occupied (32 sets at a time) |

**Parts**

- *Receiver:* `rx_meta`/`rx_sync` (2-flop synchronizer on `uart_rxd`) and a 4-state serial receiver (`rx_state`):
  wait for start bit, wait half a bit to sample in the middle, shift in 8 bits, check the stop bit.
- *Command parser:* collects `?`, the kind letter, 4 hex digits, newline; `valid_kind` rejects other letters; on a valid
  command it flips `req_toggle` and sets `req_kind`/`req_addr`.
- *Responder:* when `rsp_update` arrives with `rsp_payload` (631 bits: kind, address, up to 608 bits of data), it prints `@`, kind,
  address, `=`, then the right number of hex digits (`tx_digits` by kind), then `\r\n`, into `tx_byte` with
  `tx_valid`/`tx_ready` handshaking.

## `readback_engine`: fetch the data (in the UI clock domain)

**Job:** the RAM read ports are on the UI clock, so the lookup has to happen there. The engine takes a request,
waits **four cycles** for the synchronous RAM to deliver, captures the data into `rsp`, and clears `busy`.

**Kind `B` is special:** it scans 32 hash sets one after another (`scan_set` increments, `scan_index` counts 0..31),
sets bit *i* of `scan_bits` when any of the eight ways at set *i* is valid, and returns the 32-bit bitmap. This lets a laptop
find the occupied sets with 32 queries instead of 1024.

| Signal | Meaning |
| --- | --- |
| `req_update` | one-clock pulse: a new request has arrived |
| `req = {toggle, kind[7:0], address[13:0]}` | the request word |
| `hash_valid[7:0]` | valid bit of each hash way at the current set |
| `data[607:0]` | RAM data selected by `ram_ports` for this kind |
| `active` | engine busy; also tells `ram_ports` to hand the read ports to the readback |
| `scan_set`, `rsp` | outputs |

## `uart_system`: the wiring of all of the above

One instance (`u_uart`) in `top_system`. Chain of a query:

```
?S07FF ─► uart_readback (core) ─ req ─► config_cdc ─► readback_engine (ui) ─ reads RAM via ram_ports
                                                          │
 @S07FF=... ◄─ uart_readback ◄─ rsp ─ config_cdc ◄────────┘
                  │ tx bytes
                  ▼
            uart_telemetry (merges with the status line) ─► uart_tx ─► pin
```

Why the round trip through the UI domain? The book's RAMs expose their read ports on the UI clock for the display.
The readback shares those ports instead of adding another set of memories.

## Example: reading slot 2047

Laptop sends `?S07FF\n`. `uart_readback` parses kind `S`, address `0x07FF`, flips `req_toggle`. `config_cdc` carries it
to the UI domain; `readback_engine` becomes active, `ram_ports` points `slot_addr` at 2047, four cycles later the slot
data is captured into `rsp`; another `config_cdc` carries `rsp` back; `uart_readback` prints
`@S07FF=` followed by 12 hex digits (a 47-bit slot record: valid, side, price index, shares). The laptop now sees the first order stored in slot 2047 exactly as the FPGA holds it.
