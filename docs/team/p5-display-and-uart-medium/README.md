# Owner 5: Outputs: the VGA display and the UART  (difficulty: medium)

## Your 30-second pitch

> "I own everything the outside world sees of the order book. A UART status line prints the best bid and ask, the order count, the network counters and exactly what the last event wrote to memory.
> A UART query protocol lets a laptop read any entry of the real RAMs. For the screen, a second small RISC-V CPU runs a C program that reads the book's real memories and registers,
> draws characters and charts into video memory, and a video block streams that memory out as a 1280x720 VGA picture, sixty times a second, with double buffering so it never tears.
> No number on the screen is hard-coded: every value comes from FPGA registers or RAM."

## Your modules

| Module | File | Lines | One-line job |
| --- | --- | --- | --- |
| `uart_tx` | `rtl/telemetry/uart_tx.v` | ~90 | serial transmitter + 64-byte FIFO |
| `uart_telemetry` | `rtl/telemetry/uart_telemetry.v` | ~470 | builds the 320-character status line; the CPU's UART window |
| `uart_readback` | `rtl/telemetry/uart_readback.v` | 166 | the laptop's memory-query port (`?S07FF`) |
| `readback_engine` | `rtl/telemetry/readback_engine.v` | ~50 | fetches the requested RAM word in the UI clock |
| `uart_system` | `rtl/telemetry/uart_system.v` | ~100 | wires the four UART blocks and their clock crossings |
| `ram_ports` | `rtl/display/ram_ports.v` | ~100 | who owns the book's read ports; data routing |
| `ui_registers` | `rtl/display/ui_registers.v` | ~85 | packs 52 words for the display CPU |
| `status_to_ui` | `rtl/display/status_to_ui.v` | ~80 | copies core status to the 25 MHz UI clock |
| `book_views` | `rtl/display/book_views.v` | ~60 | wraps the two display-only memories |
| `lob_display_journal` | `rtl/display/lob_display_journal.v` | 84 | 128 quote samples + 256 event records |
| `lob_level_order_count` | `rtl/display/lob_level_order_count.v` | 87 | orders per price level |
| `display_system` | `rtl/display/display_system.v` | ~190 | wrapper: keyboard front end + display CPU + video |
| `kitty_ui_cpu` | `rtl/display/kitty_ui_cpu.v` | 95 | the second RISC-V CPU and its I/O |
| `kitty_video` (+ `kitty_pixel_clock`) | `rtl/display/kitty_video.v` | 187 | the 720p video generator |
| UI firmware | `firmware/kitty_ui/main.c` (+ `start.s`, `link.ld`, `build.py`) | ~400 | the C program that draws each page |

## Tests you can run live

```bash
tb_uart_tx                 # serial frames bit-by-bit; FIFO full flag
tb_uart_storage_trace      # the 320-byte status line: trace, base, tick
tb_uart_readback           # query ?S0001 → @S0001=... response
tb_lob_display_journal     # quote and event rings
tb_lob_level_order_count   # orders-per-level counters with forwarding
tb_kitty_preview           # renders every page from the real renderer to PPM images (build/kitty_preview/)
```

## Reading order

1. [00-system-in-10-minutes](../00-system-in-10-minutes.md)
2. [01-the-system-from-my-seat](01-the-system-from-my-seat.md)
3. [02-uart-transmit-and-status-line](02-uart-transmit-and-status-line.md)
4. [03-uart-readback](03-uart-readback.md)
5. [04-data-delivery-to-the-display](04-data-delivery-to-the-display.md)
6. [05-display-cpu-and-firmware](05-display-cpu-and-firmware.md)
7. [06-video-generator](06-video-generator.md)
8. [07-viva-qa](07-viva-qa.md)

## The facts you must be able to state without looking

1. UART: **115200 baud, 8N1**; the status line is **320 characters** printed after every event (plus a 1 s heartbeat); prices and counts are printed in **hexadecimal**.
2. Readback query format: `?` + kind letter + **4 hex digits** + newline; the reply is `@` kind address `=` hex digits.
3. The readback runs in the **UI clock** because the RAMs' second read ports are there; `ram_ports` gives readback **priority** over the display.
4. The display is a **second RV32IM CPU** (same `cpu_core`) running a C program; it can only **read** the book and **write** video memory.
5. The screen is a **160 × 45 character grid** of 8×16 pixels = 1280×720, plus a chart memory; **double-buffered**, swapped at vertical blank.
6. Pixel clock **74.25 MHz** = 100 MHz × 37.125 / 5 / 10; frame 1650 × 750 pixels at 60 Hz.
7. Nothing on screen is hard-coded: static text is labels only; every value is read from registers/RAM.
