# The system from the CPU owner's seat

You own the "control plane": the small processor that keeps the system running, the register windows that
connect it to everything else, and the physical indicators.

## What the CPU actually does (honest answer)

| Job | Details |
| --- | --- |
| **Unlocks the order book** | waits for `init_done` and for the configuration to reach the Ethernet clock, then writes `1` to the LOB `CTRL` register. This sets `accel_enable`, which becomes `run_enable` at `lob_core`. **Until then no order, network or keyboard, is accepted.** |
| **Owns the configuration** | the registers `PRICE_BASE`, `TICK`, `LOCATE` live in your `lob_mmio_slave`. They reset to **900000, 1000, 1**; the firmware leaves them at the defaults, but they could be changed before the first event. They feed owner 1's ITCH decoder (via `u_cfg_cdc`), owner 2's BBO, and owner 3's keyboard price conversion |
| **Monitors** | repeatedly reads status, the latched error code, network counters and a consistent best-bid/ask snapshot, and stores them in its data RAM |
| **Provides the program counter** | the seven-segment display mode `SW=11` shows the CPU's PC on the right four digits (a handy "is the CPU alive?" indicator) |

Not on its job list: it does **not** process orders, and the UART and VGA read hardware directly, not through the CPU.
The CPU's stored snapshots are what the simulation checks (`dmem[0]`, `dmem[2]` hold bid price and ask price in `tb_system_top`), and what a host could read in other configurations.

## What comes **into** your part

| Input | From | Meaning |
| --- | --- | --- |
| LOB status: `book_valid`, `init_done`, `busy`, `error_valid/code`, `active_order_count`, `event_done`, `event_ready`, best bid/ask valid/price/qty | **owners 2 and 3** (`lob_core`, `lob_bbo`) | the book's headline state; read through `lob_mmio_slave` |
| `cfg_ready` | **owner 1** (`u_cfg_cdc.src_ready`) | the configuration has reached the `eth` clock (LOB STATUS bit 7) |
| `net_diag[351:0]` | **owner 1** | network counters and flags; read through `net_mmio_slave` |
| `sw[1:0]` | the physical switches SW14 and SW15 | which value the seven-segment display shows; also readable at `0x7000_0000` |
| clocks, resets, `mmcm_locked` | **owner 1** | |
| the UART bus window `uart_rsp_*` | **owner 5** (`uart_telemetry`) | the CPU can also write bytes into the UART FIFO |

## What goes **out of** your part

| Output | To | Meaning |
| --- | --- | --- |
| `accel_enable` | **owner 3** (`lob_core.run_enable`) and the LOB status | the start switch |
| `cfg_price_base`, `cfg_tick`, `cfg_stock_locate` | owners 1, 2, 3, 5 | conversion constants; also shown on the VGA Status page |
| UART bus requests | owner 5 | `uart_req_*` |
| `led[15:0]`, `an`, `seg`, `dp` | the board | LEDs and seven-segment display |
| `top_system` wiring | everyone | how all the blocks connect |

## The picture you should be able to draw

```
                 ┌─────────────────────────────── 0x4000_0000 LOB registers ◄── lob_core status, BBO, config
  RISC-V CPU ────┤ sys_bus_interconnect           0x5000_0000 network counters ◄── net_ingest diag
  (3-stage)      │  (one transaction at a time)   0x6000_0000 UART window ───────► uart_telemetry FIFO
                 │                                0x7000_0000 system: switches, clock lock
                 ├── 0x0000_0000 instruction RAM (firmware, 4 KiB)
                 └── 0x2000_0000 data RAM (4 KiB): the stack and stored snapshots
```

## How your part connects to the visible results

```
 LEDs 0..15 ───► board_status (your module): from owner 1/2/3 signals
 Seven-segment ─► board_status + seven_seg_driver: best bid, ask, orders+events, or frames+PC
 VGA Status page ► shows the configuration you hold (base, tick) and your CPU-visible counters (via owner 5)
```

## The key rule you enforce

> **The CPU may configure and observe, but never sits in the order path.**
> A slow or stalled CPU cannot delay an order, because orders go network/keyboard → FIFO → arbiter → `lob_core`, with no CPU involvement after enabling.
> The same is true in reverse: a CPU fault cannot corrupt the book. It has no write access to the memories, only to `CTRL` and the three configuration registers.
