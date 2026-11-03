# Clocks, resets and clock crossings

Files: `rtl/clocking/clk_rst_mgr.v`, `rtl/clocking/phy_refclk_out.v`, `rtl/common/config_cdc.v`,
`rtl/common/async_event_fifo.v`, `rtl/common/event_counter.v`.

These are the "infrastructure" modules every other owner depends on. Expect cross-over questions.

---

# Part A: `clk_rst_mgr`

## A1. Why four clocks?

| Clock | Frequency | Why this frequency |
| --- | --- | --- |
| `clk_eth` | 50 MHz | the RMII PHY interface is defined at 50 MHz for 100 Mbit/s |
| `clk_eth_phy` | 50 MHz, **45° phase shifted** | the reference clock *sent to* the PHY; the shift (per the Digilent manual) sets the timing relationship of the PHY's data to our sampling clock |
| `clk_core` | 50 MHz | the order book, CPU, UART; relaxed so timing closes easily |
| `clk_vga` (the **UI clock**, despite the name) | 25 MHz | the keyboard, the display CPU and display memories; the 720p pixel clock is generated separately in `kitty_video.v` |

`eth` and `core` are the same frequency, but they are **different clocks** from different outputs of the clock generator. Without a guarantee of phase relationship,
every signal between them must be treated as asynchronous. That is why the CDC modules exist.

## A2. The hardware clock generator (an MMCM)

An **MMCM** is the FPGA's clock synthesizer. It multiplies its input to a high internal frequency (the VCO) and divides it to produce outputs.

```
 100 MHz ──► ×10 ──► VCO = 1000 MHz ──┬─ ÷20 ─► 50 MHz  clk_core
 (CLKIN1)  (CLKFBOUT_MULT_F=10)       ├─ ÷20 ─► 50 MHz  clk_eth
                                      ├─ ÷40 ─► 25 MHz  clk_vga (UI)
                                      └─ ÷20, 45° ─► 50 MHz clk_eth_phy
```

Each output goes through a **BUFG** (a global clock buffer) so it can drive thousands of flops with low skew. `LOCKED` (`mmcm_locked`) goes
high when the output clocks are stable; it also lights LED 0.

## A3. Simulation vs hardware

```verilog
`ifdef SIMULATION
    assign clk_core = clk_100mhz_in;     // NOTE: 100 MHz in simulation
    ... clk_50_reg toggles for clk_eth and clk_eth_phy; clk_25_cnt[1] gives clk_vga
    assign mmcm_locked = 1'b1;
`else
    MMCME2_BASE ... BUFG ...
`endif
```

The Icarus simulations use simple toggling registers instead of the MMCM (which does not exist in a simulator). **Detail worth knowing:** in simulation
`clk_core` is the raw 100 MHz while `clk_eth` is 50 MHz, so the clocks do not match the hardware ratio. The design is correct for any ratio because every crossing is handshake-based.

## A4. Resets: asynchronous assert, synchronous release

```verilog
wire global_rst_condition = rst_btn_n && mmcm_locked;

(* ASYNC_REG = "TRUE" *) reg [3:0] rst_core_sync;
always @(posedge clk_core or negedge global_rst_condition)
    if (!global_rst_condition) rst_core_sync <= 4'b0000;
    else                       rst_core_sync <= {rst_core_sync[2:0], 1'b1};
assign rst_core_n = rst_core_sync[3];
```

The same pattern is repeated for `eth` and `vga` (UI) domains.

**Why:** a reset that *asserts* asynchronously stops the design instantly. But if it were *released* asynchronously, different flops in a domain could leave reset one clock apart,
and the chip would start in an inconsistent state. The 4-stage shift register makes the release **synchronous**: the `1` has to travel through four clock edges. All flops in a domain are released together.

The button is **active low** (`rst_btn_n`). The reset condition also requires the clocks to be locked, so nothing runs on unstable clocks.

## A5. The PHY power-up reset

```verilog
reg [16:0] phy_rst_cnt;
always @(posedge clk_eth or negedge global_rst_condition)
  if (!global_rst_condition) begin phy_rst_cnt <= 0; phy_rst_n <= 0; end
  else if (phy_rst_cnt < 17'd65535) begin phy_rst_cnt <= phy_rst_cnt + 1; phy_rst_n <= 0; end
  else phy_rst_n <= 1;
```

The Ethernet PHY chip needs a clean reset pulse and time to start. This counter holds `phy_rst_n` low for 65,535 `eth` clocks (≈ **1.3 ms**), then releases it. `phy_rst_n` goes to the
board pin `eth_rstn` (and LED 1).

---

# Part B: `phy_refclk_out`

```verilog
ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), ...) u_oddr (.Q(refclk), .C(clk_phy), .CE(1'b1), .D1(1'b1), .D2(1'b0), ...);
```

A clock signal cannot go straight from a clock net to an output pin in a clean way. An **ODDR** (output double-data-rate flop) is the standard trick: with `D1 = 1` and `D2 = 0` it outputs `1` on one clock edge and `0` on the other,
so the pin toggles at exactly the clock frequency (50 MHz). It is driven by the 45° shifted clock. In simulation it is simply a wire (`refclk = clk_eth`).

---

# Part C: `config_cdc`: a bundle across clock domains

## C1. The problem it solves

You want to pass a **multi-bit** value (a counter, configuration, status) from clock A to clock B. If you sampled bit by bit, bits could be caught at different moments and the
destination would see a value that never existed (tearing).

## C2. How it works (hold and handshake)

Source side (clock `src_clk`):

```verilog
assign src_busy = req_toggle != ack_sync2;     // request not yet acknowledged
...
if (!src_busy && src_data != held_data) begin  // only when idle and the data changed
    held_data  <= src_data;                    // 1. freeze the value in a holding register
    req_toggle <= ~req_toggle;                 // 2. ring the bell (flip a flag)
end
```

Destination side (clock `dst_clk`):

```verilog
req_sync1 <= req_toggle;  req_sync2 <= req_sync1;   // the bell passes through a 2-flop synchronizer
if (req_sync2 != ack_toggle) begin
    dst_data   <= held_data;                        // 3. copy: held_data has been stable for 2+ destination clocks
    dst_update <= 1'b1;                             //    pulse "new data"
    ack_toggle <= req_sync2;                        // 4. answer: flip the ack flag
end
```

The ack toggle returns to the source through its own 2-flop synchronizer (`ack_sync1`, `ack_sync2`); only then is `src_busy` cleared and a new value can be sent.

### Timeline

```
 src clk:  data changes ──► held_data frozen, req_toggle flips ─────────────────────────────► ack arrives, busy=0
 dst clk:                       req_sync1 ─► req_sync2 ─► dst_data <= held_data, dst_update, ack_toggle flips
```

**Why a toggle and not a pulse?** A 1-clock pulse in a fast domain could be missed by a slow domain. A **level change** (toggle) stays until seen, so it cannot be missed.

## C3. Properties to quote

- Safe for any frequency ratio.
- It transfers the **latest snapshot**, not every intermediate value. Fine for counters, status, configuration. **Not** for event streams.
- `dst_update` is a 1-clock pulse in `dst_clk` when new data arrives. `src_ready` is high when the destination has the same value as the source.
- `RESET_VALUE` sets both `held_data` and `dst_data` at reset (e.g. default price base and tick).
- Latency is a few clocks of each domain, irrelevant for slow data.

## C4. Where it is used (project-wide)

`net_ingest` ×4 (`u_cfg_cdc`, `u_diag_cdc`, `u_ip_csum_cdc`, `u_pipe_cdc`), `uart_system` ×2 (`u_request_cdc`, `u_response_cdc`), `status_to_ui` ×7 (`u_book_cdc` ... `u_local_done_cdc`), `kitty_video` ×1 (`u_present_cdc`).
**Naming matters:** the timing constraints (`fpga/nexys_a7_system.xdc`) match instance names `u_*_cdc`. A differently named instance would be timed like ordinary logic and fail timing.

---

# Part D: `async_event_fifo`: a queue between clocks

## D1. When you need it

When **every item matters and order must be preserved**, like order events. `config_cdc` would lose items between snapshots.

## D2. Structure

```
 write side (wr_clk)                                                  read side (rd_clk)
 wr_valid/data ──► mem[ wptr ] ◄─────────── storage (2^ADDR_WIDTH entries) ─────────► rd_data = mem[ rptr ]
       wptr_bin ─► gray ─► 2 flops ─────────────────────────────────────────────────► compare with rptr → EMPTY
       full ◄─ compare ◄─ 2 flops ◄───────────────────────────────────────────────── rptr_bin ─► gray
```

Two pointers of `ADDR_WIDTH + 1` bits: the extra top bit tells "wrapped once more" so *full* and *empty* can be told apart.

## D3. Gray code: why

The pointers cross to the other clock domain. If a binary pointer goes from `0111` to `1000`, **four** bits change at once, and the other side could catch any mix (`1111`, `0000`...). In **Gray code**
consecutive values differ in **exactly one bit**:

| n | binary | Gray |
| --- | --- | --- |
| 0 | 000 | 000 |
| 1 | 001 | 001 |
| 2 | 010 | 011 |
| 3 | 011 | 010 |
| 4 | 100 | 110 |
| 5 | 101 | 111 |
| 6 | 110 | 101 |
| 7 | 111 | 100 |

(`gray = bin ^ (bin >> 1)`.) With one bit changing, a pointer caught mid-update is **either the old or the new value**, never garbage. An old value only makes the FIFO look slightly fuller or emptier than it is: a safe error.

## D4. Full and empty

```verilog
wire is_full  = (wptr_gray_next == {~rptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rptr_gray_sync2[ADDR_WIDTH-2:0]});
wire is_empty = (rptr_gray == wptr_gray_sync2);
```

- **Empty:** the read pointer equals the (synchronized) write pointer.
- **Full:** the write pointer is exactly one lap ahead. In Gray code that is "the top two bits inverted, the rest equal".

Each side uses only the *other* side's pointer after **two flip-flops** (`*_sync1`, `*_sync2`, `ASYNC_REG`). `full_reg` and `empty_reg` are registered for timing.

## D5. First-word fall-through (FWFT)

`assign rd_data = mem[rptr_bin[ADDR_WIDTH-1:0]];` and `rd_valid = ~empty_reg`. The oldest entry is **always on the output wires**; no "request a read, wait a cycle" step. The reader takes it by raising `rd_ready` while `rd_valid` is high (the usual valid/ready handshake).

## D6. The always blocks

| Block | What it does |
| --- | --- |
| `always @(posedge wr_clk)` (no reset) | `if (wr_rst_n && wr_valid && wr_ready) mem[wptr] <= wr_data;`: a clock-only block so Vivado infers **distributed RAM** with an asynchronous read |
| `always @(posedge wr_clk or negedge wr_rst_n)` | advances `wptr_bin/gray`, updates `full_reg`, drives `wr_overflow` (a write attempted while full) |
| `always @(posedge rd_clk or negedge rd_rst_n)` | advances `rptr_bin/gray`, updates `empty_reg`, drives `rd_underflow` |
| two synchronizer blocks | `rptr_gray → rptr_gray_sync1 → rptr_gray_sync2` in `wr_clk`, and `wptr_gray` similarly in `rd_clk` |

`wr_count` / `rd_count` give each side an estimate of how many items are stored (using the synchronized pointer converted back from Gray).

## D7. The two instances in the project

| Instance | Where | Depth | Direction |
| --- | --- | --- | --- |
| `u_event_fifo` | `net_ingest` | 64 | network events: `eth` → `core` |
| `u_local_fifo` | `order_merge` | 4 | keyboard events: `ui` → `core` |

(Only the `ADDR_WIDTH` parameter differs: 6 vs 2.)

## D8. Timing constraints you should know

In `fpga/nexys_a7_system.xdc`: `set_max_delay -datapath_only` (10 ns) on the Gray-pointer paths into the first synchronizer flop of **both** FIFOs (matched by
the instance names `u_event_fifo` and `u_local_fifo`), and false paths into the first flop of every synchronizer. These tell Vivado "this path is *meant* to be asynchronous; only check that it is not slower than 10 ns".

---

# Part E: `event_counter`

```verilog
always @(posedge clk or negedge rst_n)
    if (!rst_n) count <= 0; else if (inc) count <= count + 1;
```

A 32-bit counter. Used as `u_fifo_events` (events accepted into the FIFO), `u_core_events` in `top_system` (completed book events) and `u_frame_errors` (PS/2 frame errors).

## F. "What if" quick answers (infrastructure)

- **What if we used two plain flip-flops for a 32-bit counter?** Torn reads (explained in C1).
- **What if the FIFO were full and the decoder kept writing?** `wr_ready` is low, so the decoder holds its event (`SEND`) and the chain backpressures; if a write were attempted anyway, `wr_overflow` would set the feed-loss flag.
- **What if the MMCM never locks?** `mmcm_locked` stays 0, so `global_rst_condition` stays 0 and the whole chip stays in reset (LED 0 off).
- **What if you release reset asynchronously?** Different flops would leave reset on different clocks (the reason for the 4-stage release shift).
