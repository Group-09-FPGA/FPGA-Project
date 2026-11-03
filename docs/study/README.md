# RTL study guide

A guided tour of everything in `rtl/`, written to be read in order. Each
chapter explains one area in plain language, then goes module by module:

- **Job**: what the module does, in one sentence.
- **Why it is here**: why the design needs it and where it is instantiated.
- **Analogy**: a real-world picture to hold in your head.
- **Key signals**: the wires and registers worth remembering.
- **Always blocks**: what each `always` block does.
- **Example**: a small worked trace.

| # | Chapter | You will learn |
| --- | --- | --- |
| 0 | [Verilog refresher](00-verilog-refresher.md) | The 10 language ideas this code uses |
| 1 | [Big picture](01-big-picture.md) | The whole system, and one order followed end to end |
| 2 | [Clocks, resets and crossings](02-clocks-and-crossings.md) | Why there are four clocks and how data moves between them |
| 3 | [Network front end](03-network-front-end.md) | Ethernet bytes to a 256-bit order event |
| 4 | [The order book](04-order-book.md) | Hash table, slots, price levels, best bid/ask, and the sequencer |
| 5 | [Order sources and keyboard](05-order-sources-and-keyboard.md) | PS/2 keys, the order form, merging two sources |
| 6 | [CPU, bus and board](06-cpu-and-board.md) | The RISC-V supervisor, MMIO registers, LEDs, 7-segment |
| 7 | [UART](07-uart.md) | The status line and the RAM readback protocol |
| 8 | [Display](08-display.md) | How the VGA picture is produced from real FPGA memory |
| 9 | [Top level and cheat sheets](09-top-level-and-cheatsheets.md) | How everything is wired, important signals, quiz |

Suggested route: read 0 and 1 first, then 4 (the heart), then 2, 3, 5, 6, 7, 8.
Keep `rtl/top/top_system.v` open beside you; it is only 265 lines.

A convention used everywhere: signals ending in `_n` are active-low,
`clk_*` are clocks, `rst_*_n` are resets, and `*_valid` / `*_ready` pairs are
handshakes (explained in chapter 0).
