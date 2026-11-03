# Viva questions and model answers (owner 5)

## A. UART

**1. What is the UART format?** 115200 baud, 8 data bits, no parity, 1 stop bit (8N1); LSB first.

**2. How many clocks per bit?** 50 MHz / 115200 ≈ 434.

**3. How does `uart_tx` work?** A 64-byte FIFO plus a 4-state serializer (idle, start, data, stop). The FIFO count goes up on write-only, down on read-only.

**4. What is in the status line?** 320 characters: best bid/ask price, valid flag, error code, bid/ask quantity, order count, CRC/UDP/IP error counts, six pipeline counters, the 79-digit storage trace, base and tick, all in hex.

**5. When is a line printed?** Six clocks after each `event_done`, once per second as a heartbeat, and when `book_valid` or `error_code` changes.

**6. Why wait six clocks?** The best-price pipeline and counters need to settle after `event_done`, or the line would show a mix of old and new values.

**7. Why latch the inputs?** The line takes about 28 ms to print; latching makes it one consistent snapshot.

**8. What if an event happens while a line is printing?** Its data goes to the `pend_*` registers and a new line starts right after; the latest state is never lost.

**9. How is the readback protocol framed?** Query `?` + kind + four hex digits + newline; reply `@` kind address `=` fixed-width hex `\r\n`.

**10. Why does readback run in the UI clock?** The RAMs' second read ports are in the UI clock domain; requests and replies cross with `config_cdc`.

**11. What if the UART and VGA read at the same time?** `ram_ports` gives the readback priority; the display CPU waits.

**12. What does kind `B` do?** Scans 32 hash sets and returns a bitmap of which are occupied, so a laptop can read only occupied sets.

**13. What if the cable is unplugged?** The FIFO fills and printing waits; nothing in the book changes.

## B. Display

**14. How is the picture generated?** A second RISC-V CPU runs a C program that reads registers and RAM and writes characters and chart points into video memory; `kitty_video` scans that memory out as VGA.

**15. Why a CPU for the display?** Flexible and easy to change for nine pages and charts; the same verified core is reused.

**16. Can the display change the book?** No. Its only outputs are RAM read requests and video-memory writes; there is no path to the order stream.

**17. Is anything hard-coded on the screen?** Only labels and help text. All numbers and rows come from registers or RAM.

**18. What is the resolution and pixel clock?** 1280×720 at 60 Hz, 74.25 MHz (100 × 37.125 / 5 / 10); total frame 1650 × 750.

**19. How is the text stored?** A 160×45 grid of 16-bit cells `{bg, fg, char}`, each cell 8×16 pixels, with an anti-aliased font ROM.

**20. How is tearing avoided?** Double buffering: the CPU draws into the hidden bank; the video swaps banks only at vertical blank.

**21. Why does the video pipeline have so many registers?** Each lookup (character, font, colour) takes a clock; delaying the sync and position signals by the same amount keeps everything aligned.

**22. How are the charts drawn?** The firmware scales up to 64 quote samples into a 512×256 area and writes one plot word per column (y, vertical span, colour); the video marks a pixel as a stroke if its y falls on the line or span.

**23. What does colour green/red mean on the chart?** Price rose / fell compared with the previous sample.

**24. What if the firmware is slow?** The previous frame stays on screen; the update rate drops but the picture is never half drawn.

**25. How does a monitor know where lines start?** Horizontal and vertical sync pulses, active low, at the standard 720p positions.

## C. Data paths

**26. How does the display get book status?** `status_to_ui` crosses it into the 25 MHz clock with `config_cdc`; `ui_registers` packs it into 52 words the firmware reads.

**27. How does it read bulk data (the hash table, slots)?** A RAM query: the firmware writes a kind and address; `ram_ports` points the book's second read port at that address; after four clocks the data is latched and read back in words.

**28. What is the history journal?** Rings of 128 quote snapshots and 256 event records written after every event; the quote is captured 7 clocks after the trace so the best-price pipeline has settled.

**29. What is `lob_level_order_count` for?** Orders per price level, which the book itself does not need; the Levels page shows it. It uses a read-modify-write pipeline with forwarding.

## D. Cross-over

**30. Where do the network counters on your screen come from?** Owner 1's `net_ingest`; crossed by `status_to_ui` and shown on the Status and Market pages and in the UART line.

**31. Where do the Orders page rows come from?** Owner 2's hash and slot tables, read through their second ports.

**32. Where do the Order Entry status messages come from?** Owner 3's `keyboard_controls` status code in register word 0.

**33. Who sets the price base and tick you print?** The CPU (owner 4); they appear in the UART line (`BASE:`, `TICK:`) and on the Status page.

## E. Tests

**34. How do you test the UART?** `tb_uart_tx` (frames, FIFO), `tb_uart_storage_trace` (the 320-character line), `tb_uart_readback` (query and reply).

**35. How do you test the display?** `tb_kitty_preview` runs the real renderer and firmware in simulation and writes an image per page; `tb_lob_display_journal` and `tb_lob_level_order_count` test the two display memories.
