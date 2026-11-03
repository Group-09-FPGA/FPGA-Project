# Chapter 2: Clocks, resets and clock crossings

Files: `rtl/clocking/clk_rst_mgr.v`, `rtl/clocking/phy_refclk_out.v`,
`rtl/common/config_cdc.v`, `rtl/common/async_event_fifo.v`,
`rtl/common/event_counter.v`.

## Why several clocks?

- The Ethernet PHY chip needs a 50 MHz reference and we sample its data on a
  matching 50 MHz clock (`eth`).
- The order book and CPU run at 50 MHz on their own clock (`core`) so they can be
  timed independently.
- The keyboard and display CPU run at a relaxed 25 MHz (`ui`).
- 1280x720 video needs an exact 74.25 MHz pixel clock (`pixel`).

*Analogy:* four departments each with their own wall clock. They can only pass
paperwork through special doors that are designed so a half-written page is never
read.

## `clk_rst_mgr`: make the clocks and the resets

**Job:** turn the board's 100 MHz oscillator into the project clocks, and turn the
reset button into clean resets.

**Why here:** instantiated once in `top_system` as `u_clk_mgr`. Everything else
takes its clocks and resets from it.

**How it works (hardware build):**

- One **MMCM** (the FPGA's clock synthesizer) multiplies 100 MHz by 10 to a
  1000 MHz internal clock, then divides it: ÷20 = 50 MHz for `core`, ÷20 = 50 MHz
  for `eth`, ÷40 = 25 MHz for `ui`, and another ÷20 with a **45° phase shift** for
  the PHY clock (`CLKOUT3_PHASE(45.0)`, the Digilent manual's recommendation).
- Each clock goes through a `BUFG` (a global clock buffer).
- In **simulation** (`ifdef SIMULATION`), plain toggling registers stand in for the MMCM.

**Resets:** `global_rst_condition = rst_btn_n && mmcm_locked`. For each clock there
is a 4-bit shift register (`rst_core_sync`, `rst_eth_sync`, `rst_vga_sync`):
- reset *asserts* immediately (asynchronous), so the design stops at once;
- reset *releases* only after four clock edges have shifted a `1` through, so
  release is aligned with that clock (this is the standard "async assert,
  sync de-assert" trick).

**PHY reset counter:** `phy_rst_cnt` counts 65,535 `eth` cycles (about 1.3 ms) before
raising `phy_rst_n`, giving the Ethernet chip time to wake up.

**Key signals**

| Signal | Meaning |
| --- | --- |
| `clk_core`, `clk_eth`, `clk_eth_phy`, `clk_vga` | the clocks (`clk_vga` is the 25 MHz UI clock despite its name) |
| `rst_core_n`, `rst_eth_n`, `rst_vga_n` | per-domain active-low resets |
| `phy_rst_n` | goes to the Ethernet PHY chip's reset pin |
| `mmcm_locked` | clock synthesizer is stable; also shown on LED0 |

## `phy_refclk_out`: put a clock on a pin

The PHY wants its reference clock on a normal output pin. Driving a pin from a clock
net needs an `ODDR` primitive; `phy_refclk_out` wraps it (in simulation it is just a wire).

## `config_cdc`: carry a bundle of bits safely to another clock

**Job:** copy a multi-bit value from the source clock to the destination clock
with no chance of reading it half-updated.

**Why here:** about a dozen instances (`u_cfg_cdc`, `u_diag_cdc`, `u_pipe_cdc`,
`u_book_cdc`, ...) move counters, configuration and snapshots between domains.

**Analogy:** a **safe-deposit window**. You put the new value in the box (`held_data`)
and ring a bell (`req_toggle` flips). The other side notices the bell, copies the
box (`dst_data`), and rings back (`ack_toggle`). You may not change the box until
the reply arrives.

**Always blocks**

- *Source side:* if not busy and `src_data != held_data`, latch `held_data <= src_data`
  and flip `req_toggle`. `src_busy` is "request not yet acknowledged".
- *Destination side:* a two-flop synchronizer brings `req_toggle` over
  (`req_sync1`, `req_sync2`). When it differs from `ack_toggle`, copy
  `held_data` to `dst_data`, pulse `dst_update`, and flip `ack_toggle` back.

**Key signals:** `src_data` in, `dst_data` out, `dst_update` (one-clock pulse when new
data lands), `src_ready` (all sent and acknowledged).

**Important property:** only a *snapshot* arrives, not every intermediate value.
Fine for counters and status; **not** for a stream of events (that is what the FIFO is for).

**Naming rule:** the timing constraints (`fpga/nexys_a7_system.xdc`) match
instances named `u_*_cdc`, so keep that suffix.

## `async_event_fifo`: a mailbox between two clocks

**Job:** a queue that is written on one clock and read on another, for the 256-bit
events.

**Why here:** two instances. `u_event_fifo` (inside `net_ingest`) takes events from
`eth` to `core`. `u_local_fifo` (inside `order_merge`) takes keyboard events from
`ui` to `core`.

**Analogy:** a circular conveyor belt with a write finger on one side and a read
finger on the other. Each side knows the other's position only through a delayed,
safely copied note.

**Key ideas**

- `mem` is the storage array (64 entries for the network FIFO, 4 for the local one).
- `wptr_bin`/`rptr_bin` are binary pointers (one extra bit to tell full from empty);
  `wptr_gray`/`rptr_gray` are the same pointers in **Gray code**, where only one bit
  changes per step, so a half-caught value is off by at most one position.
- The Gray pointers pass through two-flop synchronizers (`*_sync1`, `*_sync2`)
  into the other clock domain.
- **Full:** write-side compares its next Gray pointer with the synchronized read
  pointer (top two bits inverted). **Empty:** read-side compares its pointer
  with the synchronized write pointer.
- **First-word fall-through:** `rd_data = mem[rptr]` directly, so the oldest
  entry is already on the wires whenever `rd_valid` is 1; no extra read cycle.

**Always blocks**

| Block | What it does |
| --- | --- |
| `always @(posedge wr_clk)` (no reset) | Writes `wr_data` into `mem` when `wr_valid && wr_ready`. Kept separate and reset-free so Vivado can use distributed RAM. |
| `always @(posedge wr_clk or negedge wr_rst_n)` | Advances the write pointers, updates `full_reg`, raises `wr_overflow` if a write is attempted while full. |
| `always @(posedge rd_clk or negedge rd_rst_n)` | Advances the read pointers, updates `empty_reg`, raises `rd_underflow` if a read is asked while empty. |
| two small sync blocks | Pass each Gray pointer through two flops into the opposite domain. |

**Key signals:** `wr_valid/wr_ready/wr_data`, `rd_valid/rd_ready/rd_data`,
`wr_overflow` (a lost event; feeds the feed-loss flag in `net_ingest`).

## `event_counter`: the simplest module

Counts clock cycles where `inc` is 1. Used in `top_system` (`u_core_events` counts
completed order-book events), in `net_ingest` (`u_fifo_events` counts events accepted
into the FIFO) and in `display_system` (`u_frame_errors` counts PS/2 frame errors).

```verilog
always @(posedge clk or negedge rst_n)
    if (!rst_n) count <= 0; else if (inc) count <= count + 1;
```

## Example: why not just wire a 32-bit counter across?

`cnt_rx_frames` counts in the `eth` domain. If the `core` domain sampled all 32 bits
exactly while the counter went from `0x0000FFFF` to `0x00010000`, it could see
`0x0001FFFF`, a value that never existed. `config_cdc` freezes the value in
`held_data` before the other side looks, so this cannot happen.
