# `uart_tx` and `uart_telemetry`: the serial output

Files: `rtl/telemetry/uart_tx.v` (~90 lines), `rtl/telemetry/uart_telemetry.v` (~470 lines). Core clock (50 MHz).

## 1. Serial basics (what is UART?)

A **UART** sends bytes one bit at a time on a single wire, with no shared clock: both ends agree on the speed (**baud rate**, here **115200 bits/s**). One bit lasts `50,000,000 / 115,200 ≈ 434` clocks (`CLKS_PER_BIT`).

An **8N1** frame is: idle line at 1 → **start bit** 0 → **8 data bits, least significant first** → **stop bit** 1 (no parity). So one byte = 10 bit-times ≈ 86.8 µs, about **11,520 bytes per second**.

The USB-UART chip on the board turns this into a virtual serial port on the laptop (`/dev/ttyUSB1` on Linux).

# Part A: `uart_tx`

## A1. Job

Accept bytes at any time, queue up to 64, and shift them out as 8N1 frames.

*Analogy:* a printer with a paper tray. The computer can add pages quickly; the print head works at its own fixed pace.

## A2. Two independent mechanisms

### The FIFO (a circular buffer)

```verilog
reg [7:0] mem [0:63];  reg [5:0] wptr, rptr;  reg [6:0] count;
assign empty = (count == 0);   assign full = (count >= 64);   assign head_byte = mem[rptr];
always @(posedge clk or negedge rst_n) begin
    if (wr_en) begin mem[wptr] <= wr_data; wptr <= wptr + 1; end
    if (rd_en) rptr <= rptr + 1;
    if (wr_en && !rd_en)      count <= count + 1;
    else if (!wr_en && rd_en) count <= count - 1;       // read and write together: unchanged
end
```

`wptr`/`rptr` are 6 bits so they wrap at 64 automatically. `rd_en = (state == IDLE) && !empty`: the serializer takes a byte only when idle. **The caller must check `full` before `wr_en`.**

### The serializer (4 states)

| State | Action | Leaves when |
| --- | --- | --- |
| `IDLE` | `txd = 1`; if not empty: `shift <= head_byte`, `baud_cnt <= 0` | immediately → `START` |
| `START` | `txd = 0` for one bit time | `baud_cnt == CLKS_PER_BIT − 1` |
| `DATA` | `txd = shift[bit_idx]` for 8 bit times (`bit_idx` 0..7) | after bit 7 |
| `STOP` | `txd = 1` for one bit time | → `IDLE` |

`baud_cnt` counts the clocks within each bit. `busy = (state != IDLE)`. The CPU can read `head_byte` (the oldest queued byte).

## A3. Test

`tb_uart_tx` pushes four bytes (`A5`, `0A`, `00`, `FF`) with `CLKS_PER_BIT = 40`, samples the serial line at the middle of each bit and checks the byte and the stop bit, then pushes 65 bytes while the line is busy and checks `full` is raised with 64 queued (the first byte leaves immediately).

---

# Part B: `uart_telemetry`

## B1. Job

Two jobs share the TX FIFO:

1. **Automatic status line**: after each order-book event, print one 320-character line summarising the book, counters and the last event's storage writes.
2. **CPU window** at `0x6000_0000`: the supervisor can write bytes to the UART (and read its status).

It also lets the **readback responses** (part 3) in, with priority.

## B2. The status line, field by field

Total **320 characters** (steps 0..319), ending in `\r\n`. All numbers are **uppercase hexadecimal**; the host decodes them. Layout:

```
[BBO] B:<8> | A:<8> | V:<1> | E:<2> | QB:<8> | QA:<8> | N:<3> | CRC:<8> | UDP:<8> | IP:<8> | R:<8> | U:<8> | M:<8> | I:<8> | F:<8> | D:<8> | T:<79> | BASE:<8> | TICK:<8>
```

| Field | Digits | Meaning (source) |
| --- | --- | --- |
| `B:` | 8 | best **bid price** (`best_bid_price`, in 1/10000 dollars; 0 if none) |
| `A:` | 8 | best **ask price** |
| `V:` | 1 | `book_valid` |
| `E:` | 2 | `error_code` |
| `QB:` / `QA:` | 8 / 8 | best bid / ask **quantity** |
| `N:` | 3 | active orders (12 bits) |
| `CRC:` | 8 | Ethernet CRC errors (`net_diag[319:288]`) |
| `UDP:` | 8 | UDP checksum errors (`net_diag[63:32]`) |
| `IP:` | 8 | IP checksum errors |
| `R: U: M: I: F: D:` | 8 each | pipeline counters: **R**x frames, **U**DP packets, **M**old messages, **I**TCH events, **F**IFO events, **D**one (completed book events) |
| `T:` | 79 | the 316-bit **storage trace** (79 hex digits) |
| `BASE:` / `TICK:` | 8 / 8 | the price base and tick, so a host never has to assume them |

**Decoding example:** `B:000DCF28` is `0xDCF28 = 905000` → $90.5000 (price units are 1/10000 of a dollar).

## B3. How the line is generated

### The step counter and the character function

`telem_step` (0..319) selects which character to send. A big combinational `case (telem_step)` in an `always @(*)` block returns `hw_char`:

```verilog
case (telem_step)
    9'd0: hw_char = "[";  9'd1: hw_char = "B"; ...
    9'd8: hw_char = hex2ascii(lat_bid_p[31:28]);   // 8 steps → 8 hex digits of the bid price
    ...
endcase
if (telem_step >= 85 && telem_step <= 92) hw_char = hex_digit(lat_crc_errors, telem_step - 85);   // ranges for the wide fields
```

Fixed text (`[BBO] B:`, ` | A:`...) is literal characters; each number field is a range of steps where each step outputs the next hex nibble of a latched register.
`hw_wr_en = telem_busy && !fifo_full` pushes that character into the TX FIFO this clock.

### The state registers

| Register | Meaning |
| --- | --- |
| `telem_busy` | a line is being generated |
| `telem_step` | current character index |
| `lat_*` | a **latched copy** of every input, taken at the start of a line |
| `pend_*`, `pending_update` | one extra copy taken if a new event arrives while a line is printing |
| `auto_telem_en` | enable (default 1), writable by the CPU |
| `heartbeat_cnt` | counts 50 M clocks = 1 s |
| `event_settle[5:0]` | shift register of `hw_telem_trigger` (the settle delay) |

### Why latch (`lat_*`)?

A line takes about 28 ms to print. Prices and counters can change during that time. By copying all inputs once at the start, the whole line is **internally consistent** (one instant in time).

### When a line is triggered

```verilog
wire settled_event = event_settle[5];                         // event_done, six clocks ago
wire bbo_settling  = hw_telem_trigger || (|event_settle[4:0]);
wire status_changed = book_valid != prev_book_valid || error_code != prev_error_code;
wire telem_trigger = (settled_event && !bbo_settling) ||
                     ((heartbeat_pulse || status_changed) && !bbo_settling);
```

- **After an event:** wait **6 clocks** after `event_done`. `lob_core` pulses `event_done` before `lob_bbo`'s two price-pipeline stages (and the order count) have all settled; sampling too early would print an inconsistent line.
- **Heartbeat:** every 1 s, so a quiet system still reports.
- **Status change:** `book_valid` or `error_code` changed (e.g. a fail-stop) → print immediately.
- A new line only starts when **not busy and no readback line is in progress** and `auto_telem_en`.
- If another event arrives while printing, its data goes to `pend_*`; after the current line ends (`telem_step == 319`), the pending data is copied to `lat_*` and a new line starts immediately (**no events are skipped; two back-to-back events print two lines**, the second possibly delayed).

## B4. Sharing the FIFO: byte priority

```verilog
wire rb_wr   = readback_valid && readback_ready;
wire mmio_wr = mmio_wr_tx && !fifo_full;
assign tx_wr_en   = rb_wr || mmio_wr || (hw_wr_en && !fifo_full);
assign tx_wr_data = rb_wr ? readback_byte : mmio_wr ? req_wdata_d[7:0] : hw_char;
```

Priority: **readback bytes, then CPU bytes, then the automatic line.**

`readback_line_active` stays high from the first byte of a readback reply until its `\n` (`0x0A`), so a readback reply is **never interleaved** with the status line: `readback_ready = !fifo_full && (!telem_busy || readback_line_active)`. While a readback reply is printing, the auto line cannot start; while an auto line is printing, a readback reply must wait (its `readback_ready` is low).

## B5. The CPU window (`0x6000_0000`)

| Offset | Access | Meaning |
| --- | --- | --- |
| `00` | write | push a byte into the TX FIFO |
| `00` | read | the oldest byte (`head_byte`) |
| `04` | read | `{empty, full, busy}` |
| `08` | read/write | bit 0 = `auto_telem_en` |

The request is **registered first** (`req_pending`, `req_addr_d`, `req_wdata_d`) so the CPU's long bus-decode path does not directly drive the FIFO's enable. `bus_rsp_valid` is `req_pending` delayed.

## B6. Worked example: a status line after one Add

Add buy 300 @ index 5 (price 905000), id 0x2001. About 7 clocks after the add finishes: `event_done`, 6 more clocks of settling, then the line begins:

```
[BBO] B:000DCF28 | A:00000000 | V:1 | E:00 | QB:0000012C | QA:00000000 | N:001 | CRC:00000000 | UDP:00000000 | IP:00000000 | R:00000001 | U:00000001 | M:00000001 | I:00000001 | F:00000001 | D:00000001 | T:... | BASE:000DBBA0 | TICK:000003E8
```

(`0x12C = 300`; `0xDBBA0 = 900000`; `0x3E8 = 1000`.) The 79-hex-digit `T:` field encodes the slot write at address 2047, the hash insertion, and the price-level write. It takes about 28 ms to finish printing.

## B7. "What if"

- **Events arrive faster than 28 ms apart?** The extra data waits in `pend_*`; the printed lines may lag, but the latest state is never lost. The VGA, which reads hardware directly, is unaffected.
- **The UART cable is unplugged?** Nothing changes in the FPGA; the FIFO fills, `fifo_full` blocks further writes, and printing simply waits (no deadlock in the book).
- **The laptop sends a query while a status line is printing?** The query is parsed immediately, but the reply waits until the status line ends (`readback_ready` low).
- **Why hex and not decimal?** Hex needs no divider: each nibble is one character. The host decodes. (The seven-segment display is different; it has the double-dabble.)
