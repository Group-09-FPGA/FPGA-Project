# Firmware, board indicators, and the top level

---

# Part A: The firmware (`firmware/lob_test/firmware_monitor.s`)

## A1. What it is

About 60 lines of RISC-V assembly, built by `firmware/lob_test/build_firmware.py` into `imem.hex` (4 KiB, padded) and `dmem.hex`. It runs forever on the supervisor CPU.

## A2. Line-by-line

```asm
_start:
    li sp, 0x20000FF0       # stack pointer in data RAM
    li s0, 0x40000000       # s0 = LOB MMIO base
    li s1, 0x20000000       # s1 = data RAM base (where snapshots are stored)
    li s2, 0x50000000       # s2 = network counters base

wait_init:                  # 1. wait for the order book's memories to finish initialising
    lw t0, 0x04(s0)         #    read STATUS
    andi t1, t0, 1          #    bit 0 = init_done
    beqz t1, wait_init

wait_config:                # 2. wait for the price configuration to reach the Ethernet clock domain
    lw t0, 0x04(s0)
    andi t1, t0, 0x80       #    bit 7 = config_ready
    beqz t1, wait_config
    li t0, 1
    sw t0, 0x00(s0)         # 3. WRITE 1 TO CTRL  →  accel_enable = 1  →  lob_core.run_enable  →  orders accepted

monitor:                    # 4. loop forever
    lw t0, 0x04(s0)  ; sw t0, 0x18(s1)     # STATUS      → dmem[6]
    lw t0, 0x08(s0)  ; sw t0, 0x1C(s1)     # last error  → dmem[7]
    lw t0, 0x20(s2)  ; sw t0, 0x20(s1)     # network feed-loss flags
    lw t0, 0x00(s2)  ; sw t0, 0x24(s1)     # frames received
    lw t0, 0x0C(s2)  ; sw t0, 0x28(s1)     # sequence gaps
    lw t0, 0x18(s2)  ; sw t0, 0x2C(s1)     # overflow errors
    lw t0, 0x04(s0)
    andi t1, t0, 2                         # book_valid?
    beqz t1, monitor                       # no: do not publish an invalid book

    lw t2, 0x10(s0)         # reading SNAP_BID_P latches a coherent snapshot of bid/ask price and quantity
    lw t3, 0x14(s0) ; lw t4, 0x18(s0) ; lw t5, 0x1C(s0) ; lw t6, 0x20(s0)
    sw t2, 0x00(s1) ... sw t6, 0x10(s1)    # store them in data RAM
    lw t0, 0x0C(s0) ; sw t0, 0x14(s1)      # active orders
    j monitor
```

(The `;` above only shows two instructions per line for readability; in the file each is on its own line.)

## A3. Why wait for `config_ready` before enabling?

The ITCH decoder (owner 1) converts prices using `base` and `tick` copied into its own clock domain. If the book were enabled before the copy finished, the first event could be converted with stale defaults. Waiting for `config_ready` (STATUS bit 7) guarantees consistency.

## A4. What the stored data is for

| `dmem` word | Contents | Used by |
| --- | --- | --- |
| 0, 1 | snapshot best bid price, quantity | testbench checks (e.g. `dmem[0] == 1500000` in `tb_system_top`) |
| 2, 3 | best ask price, quantity | testbench checks |
| 4 | snapshot flags | |
| 5 | active orders | |
| 6, 7 | STATUS, error | |
| 8-11 | network flags, frames, gaps, overflows | |

On the board, the UART and VGA read the hardware directly, so these words serve mainly as a monitor and as simulation checks.

## A5. Building it

```bash
python3 firmware/lob_test/build_firmware.py
```

Uses `riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -Wl,-Ttext=0`, `objcopy` to a binary, then writes 1024 words of hex. The Vivado build script copies `imem.hex` and `dmem.hex` next to the synthesis sources so `$readmemh` finds them.

---

# Part B: The board indicators

## B1. `board_status` (`rtl/top/board_status.v`, 66 lines)

A pure output block (no state of its own except the display value selection). Inputs: status from owners 1-3 and the CPU's `pc`. Outputs: `led[15:0]`, `an`, `seg`, `dp`.

### LEDs (`led[15:0]`)

| LED | Source | Meaning |
| --- | --- | --- |
| 0 | `mmcm_locked` | clocks stable |
| 1 | `eth_rstn` | PHY out of reset |
| 2 | `lob_init_done` | memories initialised |
| 3 | `lob_book_valid` | book trustworthy |
| 4 / 5 | `lob_bid_valid` / `lob_ask_valid` | a best bid / ask exists |
| 6 | `lob_busy` | sequencer mid-event |
| 7 | `lob_error_valid` | error flagged |
| 8 | `eth_crsdv` | Ethernet carrier |
| 9 | `evt_valid` | an event is waiting for the book |
| 10 | `net_diag[1]` | a sequence gap has been seen |
| 11 | `net_diag[319:288] != 0` | any CRC errors |
| 15:12 | error code low nibble if there is an error, else active-order count low nibble | |

In the full-system simulation the LED word is **`0x203d`**: bits 0, 2, 3, 4, 5 (locked, init done, book valid, bid and ask valid) and bit 13 (an active-order count of 2 shown in the top nibble).

### The seven-segment value

```verilog
case (sw)                                  // sw = {SW15, SW14}
    2'b00: value = bid_price;
    2'b01: value = ask_price;
    2'b10: value = {4'h0, active_orders, event_count[15:0]};
    default: value = {net_diag[351:336], cpu_pc[15:0]};
endcase
wire price_mode = (sw == 2'b00 || sw == 2'b01);
```

In price modes the display uses format 1 (eight decimal digits) with a decimal point after the fourth digit (`point_mask = 8'b0001_0000`) so 905000 shows as `0090.5000`. In modes 10 and 11 it uses format 2 (two independent 4-digit decimal fields).

Why **SW14/SW15** and not SW0/SW1? On this board's switches SW0 and SW1 are not working; the constraints file maps `sw[0]` to pin U11 (SW14) and `sw[1]` to V10 (SW15).

## B2. `seven_seg_driver` (174 lines)

**The hardware:** eight 7-segment digits share the same seven segment lines; each digit has its own **anode** (digit-select) line. All lines are **active low** (0 = on).

**Multiplexing:** only one digit is lit at a time. A refresh counter holds each digit for **1 ms** (`REFRESH_RELOAD = CLK_FREQ_HZ/1000 − 1`), cycling `digit_sel` through 0..7: a full refresh every 8 ms (125 Hz), too fast to see flicker.

```verilog
always @(*) case (digit_sel) 3'd0: an = 8'b1111_1110; 3'd1: an = 8'b1111_1101; ...   // one anode low
always @(*) case (nibble) 4'h0: seg = 7'b100_0000; 4'h1: seg = 7'b111_1001; ...      // hex → segments
```

**Binary to decimal:** a **double-dabble** converter runs continuously in 32 steps (or 16 for the split format), so the large decimal conversion costs few gates. `decimal_digits` only updates when a full pass completes, so the display never shows a half-converted number.

| `format` | Shows |
| --- | --- |
| 0 | the 32-bit value in hexadecimal |
| 1 | the value as eight decimal digits |
| 2 | two 16-bit values as two 4-digit decimal fields (values above 9999 show their last four digits) |

---

# Part C: The top level (`rtl/top/top_system.v`, 265 lines)

## C1. Role

Only wiring: it instantiates subsystems and connects them. Reading it top to bottom is the best way to understand the whole project.

## C2. Parameters and ports

| Parameter | Default | Meaning |
| --- | --- | --- |
| `DEFAULT_PRICE_BASE` | 900000 ($90.0000) | price of index 0 |
| `DEFAULT_TICK` | 1000 ($0.1000) | price step |
| `DEFAULT_LOCATE` | 1 | the one stock this book tracks |
| `DEST_MAC`, `DEST_IP` | 0 | 0 = accept any destination |

| Ports | Pins |
| --- | --- |
| `clk`, `reset` | 100 MHz oscillator (E3), CPU_RESETN button (C12, active low) |
| `sw[1:0]` | SW14 (U11), SW15 (V10) |
| `ps2_clk`, `ps2_data` | the USB host helper chip: F4 and B2 |
| `led[15:0]`, `an`, `seg`, `dp` | LEDs and seven-segment |
| `eth_*` | RMII PHY: `eth_refclk`, `eth_rstn`, `eth_crsdv`, `eth_rxerr`, `eth_rxd[1:0]` |
| `uart_txd_out`, `uart_rxd_in` | the USB-UART |
| `vga_hs`, `vga_vs`, `vga_r/g/b[3:0]` | VGA (12-bit colour) |

All pin assignments and timing constraints are in `fpga/nexys_a7_system.xdc`.

## C3. The instances, in order

| Section | Instance | Subsystem | Owner |
| --- | --- | --- | --- |
| clocks | `u_clk_mgr`, `u_phy_refclk` | clocks and resets | 1 |
| network | `u_ingest` | `net_ingest` | 1 |
| sources | `u_order_merge` | `order_merge` | 3 |
| book | `u_lob_core` | `lob_core` (contains owner 2's memories) | 3 / 2 |
| counter | `u_core_events` | `event_counter` | 1 |
| CPU | `u_cpu_system` | `cpu_system` | **4** |
| views | `u_views` | `book_views` | 5 |
| status copy | `u_status_to_ui` | core → UI clock | 5 |
| UART | `u_uart` | `uart_system` | 5 |
| display | `u_display` | `display_system` (also hosts the keyboard front end) | 5 / 3 |
| board | `u_board_status` | LEDs and seven-segment | **4** |

## C4. Which clock and reset does each use?

| Subsystem | Clock | Reset |
| --- | --- | --- |
| `net_ingest` | `clk_eth` (inside) and `clk_core` (outputs) | `rst_eth_n`, `rst_core_n` |
| `order_merge` | `clk_core` and `clk_ui` (the FIFO crosses) | `rst_core_n`, `rst_ui_n` |
| `lob_core`, `cpu_system`, `board_status`, `book_views`, `u_core_events` | `clk_core` | `rst_core_n` |
| `uart_system` | `clk_core` and `clk_ui` | both |
| `display_system` | `clk_ui` (25 MHz) and its own 74.25 MHz pixel clock | `rst_ui_n` and a pixel reset |

## C5. The "interface contract" wires in `top_system`

`net_valid/data/ready` (network → merge), `ui_valid/data/ready` (keyboard → merge), `evt_valid/data/ready` (merge → book), `accel_enable` (CPU → book), `cfg_*` (CPU → everything), `lob_*` status (book → CPU, UART, display, LEDs), the `display_*` read-port buses between `lob_core`, `display_system` and `book_views`, and `net_diag`/`pipe_stats` (network → CPU, UART, display).

## C6. How to explain it in a viva

> "`top_system` contains no logic. It connects eight subsystems. Orders flow left to right: network or keyboard into the merge, then the book. Status flows right to left and outwards: the CPU, the UART, the display and the LEDs. The only feedback to the front is the CPU's `accel_enable` and its configuration, plus the book's `event_ready`, which backpressures the producers."
