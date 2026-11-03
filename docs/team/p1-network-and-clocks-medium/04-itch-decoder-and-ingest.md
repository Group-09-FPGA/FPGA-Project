# `itch_decoder` and `net_ingest`

---

# Part A: `itch_decoder` (`rtl/itch/itch_decoder.v`, 184 lines)

## A1. Job

Take one **ITCH 5.0** message (a few dozen bytes), decide what it is, and produce the **256-bit canonical event** the
order book understands. It is the translator between the exchange's dialect and the project's internal language.

## A2. The ITCH messages we handle

All numbers are big-endian. Offsets are from the first byte of the message.

| Type | Meaning | Length | Fields we use |
| --- | --- | --- | --- |
| `A` | Add order | 36 | locate 1-2, order ref 11-18, side 19 (`B`/`S`), shares 20-23, price 32-35 |
| `F` | Add order with attribution | 40 | same as `A` (4 extra attribution bytes ignored) |
| `E` | Order executed | 31 | order ref 11-18, executed shares 19-22 |
| `C` | Order executed with price | 36 | same as `E` (the execution price does not change the book) |
| `X` | Order cancel (reduce) | 23 | order ref 11-18, cancelled shares 19-22 |
| `D` | Order delete | 19 | order ref 11-18 |
| `U` | Order replace | 35 | old ref 11-18, new ref 19-26, shares 27-30, price 31-34 |

Any other type is an **administrative** message (system events, stock directory...): counted and ignored.

## A3. The state machine: `COLLECT → DECODE → (DIVIDE →) SEND`

```
COLLECT ──last byte──► DECODE ──error / filtered / admin──► COLLECT
                          │
                          ├─ no price (E C X D) ──► SEND
                          └─ price (A F U) ──► DIVIDE (32 steps) ──► SEND ──ready──► COLLECT
```

### COLLECT

```verilog
if (itch_msg_start) begin
    msg_sequence <= itch_msg_seq; length <= itch_msg_len; count <= 1; msg_buffer[0] <= itch_msg_byte;
end else begin
    if (count < 48) msg_buffer[count[5:0]] <= itch_msg_byte;
    count <= count + 1;
end
if (itch_msg_last) begin cnt_itch_total_msgs <= cnt_itch_total_msgs + 1; state <= DECODE; end
```

Bytes go into `msg_buffer[0:47]` (48 bytes covers the longest message we accept, 40). `itch_msg_ready = (state == COLLECT)`:
**while the decoder is decoding, dividing, or sending, upstream is told to wait.** That is the backpressure path back to `rmii_rx`.

### DECODE (one clock)

It uses **blocking** assignments (`=`) for temporaries (`oid`, `noid`, `shares`, `price`, `side`, `known_type`,
`priced_type`, `expected_length`, `malformed`) because they are used later in the same clock; the registered outputs use `<=`.

1. Look at `msg_buffer[0]`; fill the temporaries by message type (table A2).
2. `malformed = (count != length) || (known && length != expected_length) || (A/F and side byte not B/S)`.
3. Decision, in this order:
   - `malformed` → `decode_error <= 1` (it feeds the sticky feed-loss flag) → `COLLECT`.
   - unknown type → `cnt_itch_admin_msgs++` → `COLLECT`.
   - stock locate `!= cfg_stock_locate` → `cnt_itch_filtered_msgs++` (the message is for another stock) → `COLLECT`.
   - otherwise build `pending` (the event, without the price index yet) and `cnt_itch_order_events++`.
4. If the type carries a price (`A`, `F`, `U`), prepare the divider and go to `DIVIDE`; otherwise go straight to `SEND`.

`pending` is assembled with the layout from the canonical event table:

```verilog
"A","F": pending <= {4'h1, `OP_ADD, side, 7'd0, oid, 64'd0, shares, 13'd0, 1'b0, 2'd0, msg_sequence[31:0], 32'd0};
```

Version 1, opcode, side, reserved zeros, order id, new id (0), shares, price index placeholder (13'd0), OOW (0), reserved, sequence, reserved.
Execute / cancel / delete / replace use their own opcodes and put `oid`, `noid`, `shares` in the right fields.

### DIVIDE: price → price index

The book stores prices as small **indexes**: `index = (price − base) / tick`, where `base` and `tick` come from the CPU (`cfg_price_base`,
`cfg_tick`; defaults 900000 and 1000).

```verilog
dividend <= price < base ? 0 : price - base;
divisor  <= price < base ? 0 : tick;
```

A **restoring divider**, one quotient bit per clock for 32 clocks:

```verilog
wire [32:0] trial = {remainder[31:0], dividend[31]};  // shift the next dividend bit into the remainder
wire take = trial >= {1'b0, divisor};                 // does the divisor fit?
wire [32:0] remainder_next = take ? trial - divisor : trial;
wire [31:0] quotient_next  = {quotient[30:0], take};  // append 1 or 0
...
dividend <= {dividend[30:0], 1'b0};                   // each step exposes the next bit
```

After `steps == 31` the result is final. The event gets:

```verilog
canon_event_data <= {pending[255:80], quotient_next[12:0],
                     (remainder_next != 0 || quotient_next >= 32'd8192), pending[65:0]};
```

So **price index = `quotient_next[12:0]`** and the **out-of-window (OOW) bit** (bit 66) is set when:
- `price < base` (divisor was forced to 0), or
- there is a **remainder** (the price is not a multiple of the tick), or
- the index is **≥ 8192** (outside the book's 8192-level window).

When OOW is set, `cnt_itch_oow_events++` and the book will reject the event (`FAIL_PRICE_OOW`).

**Why divide at all?** Because the book's price RAM is indexed by a small number. Storing `(price − base)/tick` makes
one slot per price tick and lets the occupancy tree find best prices with simple bit searches.

### SEND

```verilog
SEND: if (!canon_event_valid) begin canon_event_data <= pending; canon_event_valid <= 1; end
      else if (canon_event_ready) begin canon_event_valid <= 0; state <= COLLECT; end
```

The event is held with `canon_event_valid = 1` until the FIFO says ready; then back to `COLLECT`. (Priced events already set valid in `DIVIDE`.)

## A4. Timing

For a priced message: 1 clock `DECODE` + 32 clocks `DIVIDE` + about 2 clocks `SEND` ≈ 35 clocks ≈ 0.7 µs at 50 MHz after the last byte arrives. Unpriced messages take about 3 clocks.

## A5. Counters

| Counter | Meaning |
| --- | --- |
| `cnt_itch_total_msgs` | messages received (framed) |
| `cnt_itch_order_events` | order events produced (what the FIFO receives) |
| `cnt_itch_filtered_msgs` | wrong stock locate |
| `cnt_itch_admin_msgs` | unknown / administrative type |
| `cnt_itch_oow_events` | events marked out-of-window |

Only `cnt_itch_order_events` is wired up in `net_ingest` (it goes into `pipe_stats` for the UART and the VGA Status page).

## A6. Worked example

Message `A` (buy, id `0x2001`, 300 shares, price `905000` = $90.5000), locate matches, `base = 900000`, `tick = 1000`.

- `dividend = 5000`, `divisor = 1000`, 32 steps → `quotient = 5`, `remainder = 0` → index **5**, OOW **0**.
- Event: `{ver 1, op 1 (add), side 0 (buy), id 0x2001, new id 0, shares 300, index 5, OOW 0, seq}`.

Same message with price `905500`: remainder 500 → **OOW = 1** → the book rejects it: that is how off-tick prices are handled.

## A7. "What if"

- **Two Add messages arrive one after another?** The second waits in `payload_mem`/the decoder's `itch_msg_ready = 0` until the first is sent.
- **`cfg_stock_locate` changes at run time?** The configuration crosses with `config_cdc` (`u_cfg_cdc`). If it changes **after** messages have arrived, `net_ingest` sets the feed-loss flag (a replay is required).
- **A message type we don't know?** Counted as admin and ignored, never an error.
- **Why `msg_buffer` is only 48 bytes?** The longest handled message is 40; extra bytes are not stored (`if (count < 48)`), and the length check (`count != length`) does not depend on stored bytes.

---

# Part B: `net_ingest` (`rtl/network/net_ingest.v`)

## B1. Why it exists

Before the refactor, all of this was in `top_system.v`. `net_ingest` hides the whole `eth` clock domain: **its inputs are PHY pins and a configuration word;
its outputs are all in the core clock.** Everything else in the project sees the network as one block.

## B2. What is inside

```
 pins ► rmii_rx ► net_parser ► moldudp64_decoder ► itch_decoder ► async_event_fifo(64) ► evt_* (core clock)
                                  │                      │                 ▲
                                  └──── seq_gap ─────────┴─ decode_error   └─ wr_overflow
                                                         ▼
                              sticky feed_loss_eth ──► 2 flops ──► feed_loss (core clock)
 cfg_core ► config_cdc u_cfg_cdc ► eth_cfg ► itch_decoder
 counters ► u_diag_cdc, u_ip_csum_cdc, u_pipe_cdc ► diag, ip_csum_errors, pipe_stats (core clock)
```

## B3. The sticky feed-loss flag

```verilog
always @(posedge clk_eth or negedge rst_eth_n)
  if (!rst_eth_n) feed_loss_eth <= 0;
  else if (seq_gap_detected || itch_decode_error || fifo_wr_overflow ||
           (eth_cfg_update && cnt_mold_msgs != 0) ||
           cnt_crc_err != 0 || cnt_len_err != 0 || cnt_phy_err != 0 || cnt_overflow_err != 0 ||
           cnt_mold_trunc != 0 || cnt_udp_len_err != 0 || cnt_udp_csum_err != 0 || cnt_ip_csum_err != 0)
      feed_loss_eth <= 1;
```

It is **sticky**: once set, only reset clears it. Reasoning: *any* frame or message that was dropped means an order may be missing, and a book
that is missing an add or a delete gives wrong prices. A wrong book is worse than a stopped one, so the design stops. It crosses to the core with two flops
(`loss_sync1`, `loss_sync2`, marked `ASYNC_REG`), becomes `feed_loss`, and `lob_core` goes to `ST_FAIL_STOP` with error code `FAIL_FEED_LOSS (0x0A)`.

## B4. The FIFO

`u_event_fifo` is an `async_event_fifo` with `ADDR_WIDTH = 6` (64 entries of 256 bits). Written in `eth`, read in `core`. `wr_overflow` (a write while full) → feed loss.
**Backpressure** also flows: if `lob_core` is slow, the FIFO fills, `itch_decoder` waits in `SEND`, `moldudp64_decoder` stalls, `net_parser` stalls in replay, and `rmii_rx` queues up to one more frame before dropping.

## B5. The three statistics crossings

| Instance | Width | Carries | Consumers |
| --- | --- | --- | --- |
| `u_diag_cdc` | 352 | `{rx_frames, crc_err, mold_msgs, seq_gaps, len_err, phy_err, overflow, mold_trunc, udp_len_err, udp_csum_err, 29'd0, itch_decode_error, seq_gap_detected, feed_loss_eth}` | owner 4's `net_mmio_slave` (CPU), `board_status` LEDs 10-11 and the 7-segment frame count, owner 5's UART (`CRC`, `UDP`) and VGA Status page |
| `u_ip_csum_cdc` | 32 | `cnt_ip_csum_err` | UART status line (`IP:`) |
| `u_pipe_cdc` | 160 | `{rx_frames, udp_packets, mold_msgs, itch_events, fifo_events}` | UART status line (pipeline counters), VGA Status page |

`config_cdc` copies the **latest snapshot** only; counters are slow-changing so this is ideal. (A FIFO would be pointless and expensive for a counter.)

## B6. What is configured from outside

| Input | Source | Used for |
| --- | --- | --- |
| `cfg_core = {locate[15:0], price_base[31:0], tick[31:0]}` | owner 4's `lob_mmio_slave` registers | `itch_decoder` (`cfg_stock_locate`, `cfg_price_base`, `cfg_tick`) |
| parameters `DEST_MAC`, `DEST_IP` | top level (default 0 = accept any) | `net_parser` address filters |
| fixed in the module | | UDP port **10443**; Mold `cfg_expected_seq = 1`; no sequence override |

`cfg_ready` (output) tells the CPU firmware the configuration has reached the `eth` domain (LOB STATUS bit 7). The firmware waits for it before enabling the book.
