# The display CPU and its firmware

Files: `rtl/display/kitty_ui_cpu.v` (95 lines), `firmware/kitty_ui/main.c` (393 lines), `start.s`, `link.ld`, `build.py`.

## 1. The idea

Instead of designing a complicated hardware renderer for nine pages of text and charts, the project reuses the **same RV32IM CPU** (`cpu_core`) as a **display processor** running a short **C program**. The program reads the book's registers and RAM through a few MMIO addresses and writes characters and chart points into video memory.

*Analogy:* a news editor who reads the wire reports (registers, RAM), types the front page into a layout (video memory), and hands it to the printing press (`kitty_video`).

**Safety property:** the display CPU has **no path to the order stream**. Its only outputs are RAM read requests and video-memory writes.

## 2. `kitty_ui_cpu`: the CPU wrapper

| Part | Detail |
| --- | --- |
| CPU | an instance of `cpu_core` (the same module as the supervisor) |
| Memory | `memory[0:16383]` of 32-bit words = **64 KiB**, block RAM, loaded from `kitty_ui.hex`; accesses with `address[31:16] == 0` go here (byte strobes supported) |
| MMIO | everything else, decoded in one `always` block |

### MMIO map

| Address | Access | Meaning |
| --- | --- | --- |
| `0x1000_0000 + 4n` (n < 64) | read | `registers` word *n* (from `ui_registers`) |
| `0x1000_0100` | write | **RAM query**: `wdata[19:16]` = kind (1-8), `wdata[13:0]` = address |
| `0x1000_0104` | read | which video bank is currently on screen (`front_bank`) |
| `0x1000_0108` | write | **present a finished frame**: bit 0 = bank, bit 1 = this is the Market page (enable charts); increments `completed_frames` |
| `0x1000_010C` | read | `completed_frames` |
| `0x1000_0200 + 4k` | read | words of the last RAM query result |
| `0x3000_0000 + 4·cell` | write | one character cell (`cell_we`, `cell_addr[13:0]`, `cell_data[15:0]`) |
| `0x4000_0000 + 4·x` | write | one chart column (`plot_we`, `plot_addr[10:0]`, `plot_data[31:0]`) |

### The RAM query handshake
1. Firmware writes the query word. `ram_request <= 1; ram_kind; ram_address; ram_wait <= 0`.
2. `ram_ports` raises `ram_grant` when free. If not granted, `ram_wait` is held at 0.
3. Once granted, after `ram_wait == 3` (four clocks for the synchronous RAM) the data is latched into `result` (608 bits) and the CPU's store completes (`mmio_response`).
4. Firmware then reads `result` as 19 words at `0x1000_0200...`.

The CPU's bus is stalled until the response arrives, so `QUERY_CMD = ...;` followed by reads simply works in C without polling.

## 3. The firmware (`main.c`)

### Memory map as C macros
```c
#define UI         ((volatile uint32_t *)0x10000000u)   // registers
#define QUERY_CMD  (*(volatile uint32_t *)0x10000100u)
#define FRONT_BANK (*(volatile uint32_t *)0x10000104u)
#define PRESENT    (*(volatile uint32_t *)0x10000108u)
#define QUERY_DATA ((volatile uint32_t *)0x10000200u)
#define CELL       ((volatile uint32_t *)0x30000000u)
#define PLOT       ((volatile uint32_t *)0x40000000u)
```

### The main loop
```c
for(;;) {
    for(int i=0;i<64;i++) cached[i]=UI[i];       // 1. snapshot all status registers
    bank = FRONT_BANK ? 0 : 1;                   // 2. draw into the HIDDEN bank
    clear_screen();
    switch(cached[0]&15) {                       // 3. word 0 low bits = page number
        case 0: market(); break;  case 1: orders_page(); break;  case 2: hash_page(); break;
        case 3: events_page(); break;  case 4: status_page(); break;  case 5: levels_page(); break;
        case 6: slots_page(); break;  case 7: order_entry(); break;  default: history(); break;
    }
    PRESENT = bank | (page==0 ? 2 : 0);          // 4. ask to show that bank
    while((int)FRONT_BANK != bank) { }           // 5. wait until the video swapped (at vertical blank)
}
```

Every frame: read all registers into a local array (`cached`) so the page is internally consistent, draw into the bank that is **not** on screen, publish, and wait for the swap. **Double buffering** means the viewer never sees a half-drawn page.

### Helpers
| Function | Does |
| --- | --- |
| `cell(x,y,c,fg,bg)` | writes one 16-bit cell: `{bg, fg, character}` at `CELL[bank*8192 + y*160 + x]` |
| `text(x,y,s,color)` | writes a string |
| `stripe`, `highlight`, `clear_screen` | fill a row; reverse-video text; blank the page |
| `decimal`, `hex32`, `hex64`, `money` | number formatting (`money` prints `905000` as `90.5000`: whole = value/10000, four fraction digits) |
| `label_u`, `label_hex` | "name … value" rows |
| `query(kind, addr, count)` | issue a RAM query and copy `count` words into `words[]` |
| `bits(lo, count)` | extract a bit-field from the multi-word query result |
| `header(page, help)` | title bar, page-number legend, help line |
| `plot_point`, `draw_graph` | chart drawing |

### The pages
| Function | Shows | Data sources |
| --- | --- | --- |
| `market` | best bid/ask, spread, two history charts, live counters | registers 15-28; quote journal (kind 7) |
| `history` | event number, best bid/ask per event | quote journal |
| `status_page` | validity, error, counts, pipeline counters, base and tick | registers |
| `order_entry` | form, cursor, active order, status message, last local result | registers 0-14, 33-51 |
| `hash_page` | one set's 8 ways + stash | queries kind 2 and 3 |
| `events_page` | completed events with type, order id, trace | event journal (kind 8) |
| `levels_page` | per-index bid/ask quantity and order count | price RAM (kind 4) and level counts (kind 6) |
| `slots_page` | raw slot table | slot queries (kind 1) |
| `orders_page` | every live order | scans hash sets (kind 2), then each slot (kind 1), plus the stash (kind 3) |

**No fixed data:** the only static strings are labels and help text; a code comment states "All numerical state and rows are read from live FPGA registers and RAM."

### Charts (`draw_graph`)
Quote samples (up to 64) are scaled to a 512 × 256 area: find the min and max, add padding, map each value to `y = 255 − (value − low) × 255 / (high − low)`. For each sample a 32-bit **plot word** is written:

```
 bits 8:0   y of the point
 bits 17:9  vertical low  (for a step line to the previous value)
 bits 26:18 vertical high
 bits 28:27 colour: 0 grey (flat or first), 1 green (rise), 2 red (fall), 3 = no stroke
```
Missing columns between samples repeat the previous y (a step chart).

### The status message strings
`messages[12]` = `Ready, Queued, Sent to core, Invalid field, Queue busy, Invalid price or tick, Invalid quantity, Invalid order ID, Order changed: reselect, Disabled, Book invalid, Quantity exceeds stored order`, indexed by the 5-bit status in register word 0.

## 4. Building the firmware
`firmware/kitty_ui/build.py` compiles `start.s` (sets `sp = 65536`, calls `main`) and `main.c` with the RISC-V GCC (`-march=rv32im`), links with `link.ld` (code at address 0), and writes `kitty_ui.hex`. The run script and Vivado flow run it automatically. The font hex is generated by `firmware/kitty_ui/build_font.py` into `kitty_font.hex`.

## 5. "What if"
- **The page redraw is slower than a frame?** The video keeps showing the previous (front) bank; the update rate falls, but the picture stays whole.
- **The firmware tries to write to the book?** There is no such address; unmapped MMIO returns zero and nothing is wired to the order path.
- **A query is made while UART readback has the RAM?** `ram_grant` stays low; the CPU's bus stalls until granted.
- **Why not draw in hardware?** A programmable renderer made nine pages and charts cheap to change and test (`tb_kitty_preview` renders them to image files from the real RTL).
