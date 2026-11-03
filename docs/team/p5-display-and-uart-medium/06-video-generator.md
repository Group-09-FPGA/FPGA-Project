# `kitty_video` and `kitty_pixel_clock`: the video generator

File: `rtl/display/kitty_video.v` (187 lines). Instantiated as `u_pixel_clock` and `u_video` in `display_system`.

## 1. How VGA works (the 60-second version)

A monitor draws a picture line by line, left to right, top to bottom, 60 times per second. The FPGA supplies:

- the **colour** (`vga_r/g/b`, 4 bits each = 4096 colours),
- a **horizontal sync** pulse at the end of each line and a **vertical sync** pulse at the end of each frame.

Timing is fixed by the **pixel clock**. For 1280×720 at 60 Hz the standard is **74.25 MHz** with a *total* frame of **1650 × 750** pixels (the extra pixels are blanking and sync):

| | Visible | Front porch | Sync | Back porch | Total |
| --- | --- | --- | --- | --- | --- |
| Horizontal | 1280 | 110 | 40 | 220 | 1650 |
| Vertical | 720 | 5 | 5 | 20 | 750 |

74.25 MHz / (1650 × 750) = 60.0 Hz.

## 2. `kitty_pixel_clock`

```verilog
MMCME2_BASE #(.CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(37.125), .DIVCLK_DIVIDE(5), .CLKOUT0_DIVIDE_F(10.0)) ...
```
100 MHz × 37.125 / 5 = 742.5 MHz (VCO), ÷ 10 = **74.25 MHz**. A BUFG distributes it. A 4-flop reset pipe (`reset_pipe`) holds `pixel_reset_n` low until the clock is locked (asynchronous assert, synchronous release). In simulation the pixel clock is just the 100 MHz test clock.

## 3. What is stored

| Memory | Size | Contents |
| --- | --- | --- |
| `cells` (block RAM via `xpm_memory_sdpram`, `u_cells`) | 16,384 × 16 bits = 2 banks × 8192 | one cell = `{bg[3:0], fg[3:0], character[7:0]}`; the grid is **160 columns × 45 rows** (each cell 8×16 pixels → 1280×720) |
| `plots` | 2048 × 32 bits | chart columns (2 banks × 2 charts × 512 columns) |
| `font` | 4096 × 32 bits | 256 characters × 16 rows; each 32-bit word = 8 pixels of 4-bit **coverage** (anti-aliasing), loaded from `kitty_font.hex` |

Cells and plots are **written on the UI clock** (by the display CPU) and **read on the pixel clock**: a true dual-clock memory.

## 4. The counters

```verilog
if (x == 1649) begin x <= 0; y <= (y == 749) ? 0 : y + 1; end else x <= x + 1;
wire active = x < 1280 && y < 720;
wire hs_now = !(x >= 1390 && x < 1430);     // 40-pixel sync after the front porch
wire vs_now = !(y >= 725 && y < 730);
```

`x` counts 0..1649, `y` counts 0..749. Sync signals are active low.

## 5. Double buffering and the swap

The UI CPU draws into the **hidden** bank and asks to present it (`requested_bank`, `requested_market`). That request crosses to the pixel clock through `u_present_cdc`. At the **start of vertical blanking** (`x == 0 && y == 720`) the video logic adopts the requested bank (`front_bank <= present_pixel[0]`, `front_market <= present_pixel[1]`) and sets `front_valid` after the first swap (the screen stays black until then). `front_bank` returns to the UI clock through a 2-flop synchronizer (`front_meta_ui`, `front_sync_ui`) so the firmware knows the swap happened.

Because the bank changes only during blanking, **a frame is never torn**.

## 6. The pixel pipeline (why so many `*1`, `*2` registers)

Reading the character, then the font, then blending takes several clocks. Each timing signal is delayed by the same number of stages so everything lines up:

| Stage | Action |
| --- | --- |
| 0 (combinational) | `col = x[10:3]` (x/8), `row = y[9:4]` (y/16), `index = row·160 + col` |
| 1 | read `cells[{front_bank, index}]` → `char_q`; read `plots[...]` → `plot_q`; register `fx1 = x[2:0]`, `fy1 = y[3:0]`, `active1`, sync copies |
| 2 | `font_q <= font[{char_q[7:0], fy1}]`; register attributes and plot data |
| 3 (combinational) | `coverage = (font_q >> ((7−fx2)·4)) & 15` (4-bit alpha of this pixel); `foreground`/`background` from `palette(attribute nibbles)` |
| output register | blend each colour channel: `blend(fg, bg, alpha) = (fg·alpha + bg·(16 − alpha)) / 16`; or a chart stroke colour; or black outside the active area |

`blend` gives smooth anti-aliased text edges. `palette()` maps attribute numbers 0-9 to 12-bit colours (dark background `#191724`, light foreground `#e0def4`, green for rises, pink for falls, dim grey, gold highlight...).

## 7. Charts

The chart area is two rectangles (`y` 80-335 for bid history, 384-639 for ask) × 512 px wide starting at `x = 104`, drawn only when `front_market` is set (Market page). For each pixel column the plot word gives the line's `y` (`hy`) and a vertical span (`vlo..vhi`); a pixel is a **stroke** if its `y` equals `hy` or lies within the span; its colour comes from the colour field (green/red/grey). Strokes override text.

## 8. Resource use
The character memory is block RAM (the synthesis flow originally put it in LUT RAM and ran out of LUTs; the `xpm_memory_sdpram` fixes this). The whole design uses about 78% of the chip's LUTs and 88% of its block RAM, a large share being the display.

## 9. Viewing it without hardware
`tb_kitty_preview` runs the real `kitty_video` and `kitty_ui_cpu` with the real firmware in simulation, scans out a frame, and writes PPM image files (`build/ci_sim/kitty_*.ppm`) for each page (`+PAGE=n`). That is the "preview from the actual renderer".

## 10. "What if"
- **The firmware hasn't finished its first frame?** `front_valid = 0` → black screen (not garbage).
- **The monitor doesn't support 1280×720@60?** It would not lock; this timing is the CEA-861 720p standard, which most monitors accept.
- **Why 4 bits per colour?** The Nexys A7's VGA DAC is a resistor ladder with 4 bits per channel.
- **Why not simply 640×480?** The earlier design used 25 MHz; 720p gives a 160×45 grid for dense tables and charts.
