# The system from the Ethernet owner's seat

You own the front door. This page explains what happens before and after your
modules, so you can answer "and then what?" questions confidently.

## What comes **into** your part

| Input | From | Meaning |
| --- | --- | --- |
| `eth_crsdv`, `eth_rxerr`, `eth_rxd[1:0]` | the Ethernet PHY chip (LAN8720A) | carrier/data-valid, error flag, 2 data bits per 50 MHz clock |
| `clk_100mhz_in`, `rst_btn_n` | board oscillator and the red CPU_RESETN button | your `clk_rst_mgr` turns these into every clock and reset in the chip |
| `cfg_core = {locate, price_base, tick}` | **owner 4's CPU** (through the LOB MMIO registers) | the price conversion constants and the stock filter; copied into your `eth` clock |
| `evt_ready` | **owner 3's** `order_merge` | "I can take another event" (backpressure) |

Note the last two: your part is not a one-way street. The CPU configures how you convert prices,
and the order book can push back on you.

## What goes **out of** your part

| Output | To | Meaning |
| --- | --- | --- |
| `evt_valid`, `evt_data[255:0]` | owner 3's `order_merge` → `lob_core` | one canonical order event per accepted ITCH order message |
| `feed_loss` | `lob_core` | sticky "a message may have been lost"; fail-stops the book |
| `diag[351:0]` | owner 4's `net_mmio_slave` (CPU register reads), LED logic, owner 5's VGA/UART | counters and flags |
| `ip_csum_errors`, `pipe_stats[159:0]` | owner 5's UART status line and VGA Status page | pipeline counters |
| clocks and resets: `clk_core`, `clk_eth`, `clk_vga` (25 MHz UI), `rst_*_n`, `mmcm_locked` | **everyone** | every flip-flop in the chip |
| `eth_refclk`, `eth_rstn` | the PHY chip | its reference clock and reset |
| `async_event_fifo`, `config_cdc` | **everyone** | the only approved ways to cross clock domains |

## What happens after an event leaves you

```
 your evt_valid/data/ready
     │
     ▼
 order_merge (owner 3): alternates with keyboard orders; one event at a time
     │
     ▼
 lob_core (owner 3) + memories (owner 2): add / execute / cancel / delete / replace,
     update best bid / ask, bump order count, pulse event_done
     │
     ├─► owner 4: CPU snapshot, LED row, seven-segment display
     ├─► owner 5: UART line "[BBO] B:... A:... N:... CRC:... UDP:... T:..."  (about 28 ms to print)
     └─► owner 5: VGA Market page redraws from the real RAM (next frame, 1/60 s)
```

**So the order you decode appears on the monitor.** The Market page shows the best bid and ask
that `lob_bbo` computed from your event; the Orders page lists the order from the real slot table;
the Status page shows **your counters** (frames received, CRC errors, Mold messages, sequence gaps)
and the Events page shows your event's write trace.

## Rough end-to-end timing (good for "how fast?" questions)

| Step | Approx. time |
| --- | --- |
| A 142-byte frame on the wire | 142 × 4 clocks × 20 ns ≈ **11.4 µs** |
| Parsing + replay + Mold + ITCH divide + FIFO | tens of µs (the ITCH divide is 32 cycles ≈ 0.64 µs) |
| `lob_core` ADD sequence | about 6 states ≈ **0.12 µs** (20 ns per state at 50 MHz) |
| UART status line | about 28 ms (320 characters at 115200 baud) |
| VGA update | within one frame, **16.7 ms** |

The order book itself is not the bottleneck: the human-visible outputs are.

## What is **not** yours

- The order book memories and sequencer (owners 2 and 3).
- The keyboard: keyboard orders are a **second input** to the same `order_merge`. They do not touch your modules, which is why the network counters stay accurate when you type orders.
- The CPU, the LEDs, and the screen (owners 4 and 5). You only supply some of the numbers they show.

## The one thing others will ask you about

Because you own the clock-crossing modules, expect cross-over questions such as
"how does the keyboard order get into the core clock?" (answer: the same
`async_event_fifo` module, instantiated again as `u_local_fifo` in `order_merge`, 4 entries deep)
and "how does the display see the book's status?" (answer: seven `config_cdc` instances in `status_to_ui`).
