# UART readback: `uart_readback`, `readback_engine`, `uart_system`

Files: `rtl/telemetry/uart_readback.v` (166 lines), `readback_engine.v` (~50), `uart_system.v` (~100).

## 1. Job

Let a laptop **read any entry of the book's real RAMs** over the same serial cable. A dashboard can then rebuild the whole book from FPGA memory, so it never has to trust its own prediction.

## 2. The protocol

Laptop sends ASCII: `?` + kind letter + **four hex digits** + newline, e.g. `?S07FF\n`.
The board replies: `@S07FF=<hex digits>\r\n`.

| Kind | Address range | Returns | Hex digits |
| --- | --- | --- | --- |
| `S` | 0-2047 | slot record (47 bits) | 12 |
| `H` | 0-1023 | all 8 hash ways of one set, way 0 first | 152 |
| `X` | 0-7 | stash entry (76 bits) | 19 |
| `P` | 0-16383 | price-level quantity | 8 |
| `L` | 0-16383 | orders at that price level | 3 |
| `F` | 0-2047 | free-stack entry | 3 |
| `Q` | 0-127 | quote-journal record (175 bits) | 44 |
| `E` | 0-255 | event-journal record (394 bits) | 99 |
| `B` | 0-31 | bitmap: which of 32 hash sets are occupied | 8 |

One query is outstanding at a time. Replies are **fixed width**, so the host can parse by position.

## 3. `uart_readback`: the parser and the responder (core clock)

### Receiver
`rx_meta`/`rx_sync` form a 2-flop synchronizer on `uart_rxd`. A 4-state receiver (`rx_state`): 0 wait for the start bit; 1 wait **half a bit** and re-check it is still low (mid-bit sampling, rejects glitches); 2 shift 8 data bits one bit-time apart; 3 check the stop bit and raise `rx_byte_valid`.

### Command parser (`parse_step`)
| Step | Accepts |
| --- | --- |
| any | a `?` restarts (`parse_step <= 1`) |
| 1 | a valid kind letter (`valid_kind`: S H X P F L Q E B) else abort |
| 2-5 | four hex digits shifted into `parse_addr` (non-hex aborts) |
| 6 | newline `0x0A`: if idle (`!waiting_rsp && !tx_busy`) issue the request: `req_kind`, `req_addr`, **flip `req_toggle`**, `waiting_rsp <= 1` |

### Responder
When `rsp_update` arrives with `rsp_payload` (631 bits = 8-bit kind + 14-bit address + 608 bits data) and a request is pending, it latches `tx_kind`, `tx_addr`, `tx_data`, picks `tx_digits` from the kind (table above) and starts printing. `tx_byte` is combinational on `tx_step`:

| `tx_step` | Character |
| --- | --- |
| 0 | `@` |
| 1 | the kind letter |
| 2-5 | the four address digits |
| 6 | `=` |
| 7 … 6+digits | the data, most significant nibble first |
| next | `\r` then `\n` |

`tx_valid = tx_busy`; each byte is accepted on `tx_valid && tx_ready` (handshake with the TX FIFO).

## 4. The request crosses clocks: why?

The book's second read ports are on the **25 MHz UI clock** (they are shared with the display). So the request must travel core → UI, be served there, and the reply must travel back. `uart_system` wires this with two `config_cdc` instances:

```
 uart_readback (core) ─{toggle,kind,addr}─► u_request_cdc ─► readback_engine (UI) ─ drives RAM read addresses via ram_ports
 uart_readback (core) ◄─{request,data}──── u_response_cdc ◄── readback_engine
```

The request carries a **toggle bit** so even two identical queries in a row look like a *change* to `config_cdc` (which only transfers when the value changes) and are both served.

## 5. `readback_engine` (UI clock)

| Signal | Meaning |
| --- | --- |
| `req_update` | a new request arrived |
| `req = {toggle, kind[7:0], address[13:0]}` | the request |
| `hash_valid[7:0]` | valid bit of each hash way at the current set |
| `data[607:0]` | what `ram_ports` selected for this kind |
| `active` | engine busy (tells `ram_ports` the readback owns the read ports) |
| `scan_set` | hash set to read in `B` mode |
| `rsp[630:0]` | `{req, data}` |

### Normal kinds
On `req_update`: `busy <= 1; wait_cnt <= 0`. It waits **four cycles** (`wait_cnt` 0..3) for the synchronous RAM to deliver, then captures `rsp <= {req, data}` and clears `busy`.

### Kind `B`: the occupied-set bitmap
```verilog
wire [31:0] scan_next = scan_bits | ((|hash_valid) ? (32'd1 << scan_index) : 32'd0);
```
Starting at `scan_set = {address[4:0], 5'b0}` (a group of 32 sets), for each of the 32 sets it waits 4 cycles, then sets bit `scan_index` if **any** of the 8 ways is valid; then `scan_set++`, `scan_index++`. After 32 sets it returns the 32-bit bitmap.

Why: a laptop wanting the whole book would otherwise read all 1024 sets one by one. With `B` it asks 32 questions to learn which sets are non-empty, then reads only those (`H`), then the slots they point to (`S`).

## 6. `uart_system`
Instance `u_uart` in `top_system`. It contains `uart_readback`, the two CDCs, `readback_engine`, and `uart_telemetry` (with `uart_tx` inside). It exposes the UART bus window to the CPU and the RAM-access interface (`readback_active/kind/addr/scan_set/hash_valid/data`) to `display_system`'s `ram_ports`.

## 7. Worked example: `?S07FF\n`

1. Parser: kind `S`, address `0x07FF`; newline → toggle flips.
2. `u_request_cdc` delivers `{toggle, 'S', 0x07FF}` to the UI clock; `req_update` pulses.
3. `readback_engine` busy; `ram_ports` sees `readback_active && kind == "S"` → `slot_addr = 2047`.
4. 4 cycles later `rsp = {req, slot_data}`; `u_response_cdc` carries it back.
5. `uart_readback` prints `@S07FF=` then 12 hex digits, `\r\n`. For the first order added: valid 1, side buy, index 5, shares 300 → a 47-bit value shown as 12 hex digits.

## 8. "What if"
- **A malformed query (`?Z0000`)?** `valid_kind` fails; the parser returns to idle; no reply.
- **A second query before the first reply?** Ignored (`!waiting_rsp && !tx_busy` is required).
- **A query during a status line?** Accepted, but its reply waits until the line ends.
- **The display and a query want the same RAM?** `ram_ports` gives **readback priority**; the display CPU's request waits (`ui_grant` low) and the keyboard order browser pauses (`ram_paused`).
- **How is it tested?** `tb_uart_readback` sends `?S0001` and checks the fixed-width reply; the full-system test forces requests for `S` and `B` and checks the returned slot data and bitmap.
