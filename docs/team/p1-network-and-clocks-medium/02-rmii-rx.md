# `rmii_rx`: from PHY bits to checked frames

File: `rtl/ethernet/rmii_rx.v` (322 lines). Instantiated once, as `u_rmii_rx`, inside `net_ingest`. Runs in the `eth` clock (`clk_50`).

## 1. The physics you must know

**RMII** ("Reduced Media-Independent Interface") is how the PHY chip hands received data to the FPGA:

| Wire | Meaning |
| --- | --- |
| `rmii_rxd[1:0]` | **two** data bits per clock |
| `rmii_crs_dv` | carrier sense / data valid: high while a frame is arriving |
| `rmii_rx_err` | the PHY saw a bad symbol |
| `clk_50` | a 50 MHz clock (the FPGA supplies it to the PHY, see chapter 5) |

2 bits × 50 MHz = **100 Mbit/s**. A group of two bits is a **dibit**. Four dibits make one byte,
so one byte takes 4 clocks (80 ns). Bits arrive **least-significant first**.

An Ethernet frame on the wire looks like this:

```
 7 bytes preamble  | 1 byte SFD | 6 dst MAC | 6 src MAC | 2 type | ... payload ... | 4 byte FCS (CRC)
   0x55 x 7        |   0xD5     |           |           |        |                 |
```

The preamble `0x55` is binary `01010101`. Sent LSB-first, every dibit is `01`. The SFD ("start of frame
delimiter") `0xD5` is `11010101`; LSB-first the dibits are `01, 01, 01, 11`. **The first dibit equal to `11`
marks the end of the preamble.** That is exactly what the RTL looks for (`cur_rxd == 2'b11`).

## 2. Block diagram of the module

```
 pins ─► IOB input flops ─► dibit assembler ─► byte ─┬─► CRC-32 update
                                                     └─► frame_mem[wr_ptr]   (2048-byte ring buffer)
 state machine: IDLE → PREAMBLE → DATA → CHECK_FCS → (commit | drop)         │
                                                                             ▼
 net_parser reads:  frame_valid, frame_len, frame_byte_out (= frame_mem[rd_ptr]), frame_byte_last
```

## 3. Input registers in the I/O block (IOB)

```verilog
(* IOB = "true" *) reg rmii_crs_dv_iob, rmii_rx_err_iob;
(* IOB = "true" *) reg [1:0] rmii_rxd_iob;
```

The first thing the design does with each pin is capture it in a flip-flop that is **inside the pin's own
I/O block**. This gives the shortest, most predictable route from pin to flop, which matters because the
timing relationship between the PHY clock and its data is tight (the constraints file gives these inputs a
15 ns / 2 ns input delay against the 45°-shifted PHY clock). After this stage, everything uses the `_iob` copies.

`crs_dv_d1` is `cur_crs_dv` delayed one clock.

### The `crs_dv_active` trick

```verilog
wire crs_dv_active = cur_crs_dv | crs_dv_d1;
```

At the end of a frame in 100 Mbit mode the PHY drains its internal buffer and `crs_dv` toggles `1,0,1,0` at
25 MHz instead of dropping cleanly. If the design treated the first `0` as "frame over" it would cut the
last bytes. So "active" means "high this cycle **or** last cycle"; the frame is over only when `crs_dv` has
been low for **two consecutive clocks**.

## 4. The state machine

| State | What it waits for | Next |
| --- | --- | --- |
| `RX_IDLE` | clears per-frame registers (`dibit_cnt`, `active_bytes_received`, `buffer_overflow`, `had_phy_error`, `crc32_reg ← 0xFFFFFFFF`). When `cur_crs_dv` goes high → | `RX_PREAMBLE` |
| `RX_PREAMBLE` | ignores `01` dibits. If `crs_dv_active` drops → back to `IDLE`. If `rx_err` → `RX_DISCARD`. If the dibit is `11` (SFD seen): reset CRC, `wr_ptr ← wr_start_ptr` → | `RX_DATA` |
| `RX_DATA` | assembles bytes, updates CRC, writes the buffer. When `crs_dv_active` has dropped → | `RX_CHECK_FCS` |
| `RX_CHECK_FCS` | decides: drop or commit (see section 6) | `RX_IDLE` |
| `RX_DISCARD` | (after a PHY error in the preamble) waits for the carrier to end, rolls back | `RX_IDLE` |

(`RX_SFD` is declared but not used as a separate state; the SFD is detected inside `RX_PREAMBLE`.)

## 5. Assembling a byte (the `RX_DATA` state)

```verilog
case (dibit_cnt)
    2'd0: shift_byte[1:0] <= cur_rxd;
    2'd1: shift_byte[3:2] <= cur_rxd;
    2'd2: shift_byte[5:4] <= cur_rxd;
    2'd3: shift_byte[7:6] <= cur_rxd;
endcase
```

`dibit_cnt` counts 0→3. When it reaches 3, the byte is complete: `{cur_rxd, shift_byte[5:0]}` (the last dibit
becomes bits 7:6). Then, in the same clock:

1. `crc32_reg <= calc_crc32_byte(crc32_reg, byte)`: update the running CRC,
2. write the byte into `frame_mem[wr_ptr]` and `wr_ptr <= wr_ptr + 1` **unless the buffer is full** (then `buffer_overflow <= 1`),
3. `active_bytes_received` counts bytes (including the 4-byte FCS).

`rx_err` seen at any time sets `had_phy_error`; the frame is dropped at the end.

### The CRC-32 function

```verilog
for (i = 0; i < 8; i = i + 1)
    if ((crc[0] ^ byte_in[i]) == 1'b1) crc = (crc >> 1) ^ 32'hEDB88320;
    else                               crc = (crc >> 1);
```

This is the standard Ethernet (IEEE 802.3) **reflected** CRC-32: polynomial `0xEDB88320`, register initialised to
all ones (`crc32_reg ← 0xFFFFFFFF` at the start of each frame), one data bit at a time, least-significant bit first.
Eight loop iterations = one byte, computed combinationally in one clock.

**Why check against `0xDEBB20E3`?** The sender appends the CRC (the FCS) to the frame. If you keep running the CRC
over **all** bytes *including* the FCS, a correct frame always leaves the register at a fixed number, the "magic
residue", `0xDEBB20E3` (when, as here, the register is not inverted at the end). Any corruption changes it.
So the receiver never needs to separate the FCS: it just checks one constant.

## 6. The frame buffer and the commit decision

### The ring buffer

```verilog
reg [7:0] frame_mem [0:BUFFER_DEPTH-1];   // 2048 bytes, distributed RAM
reg [10:0] wr_ptr, wr_start_ptr, rd_ptr, read_start_ptr;
```

| Pointer | Meaning |
| --- | --- |
| `wr_ptr` | next byte to write |
| `wr_start_ptr` | where the **current incoming** frame began; used to **roll back** a bad frame by `wr_ptr <= wr_start_ptr` |
| `rd_ptr` | next byte `net_parser` will read |
| `read_start_ptr` | where the frame being read started |
| `queued_start_ptr`, `queued_frame_len`, `queued_valid` | a **second** good frame waiting while the first is still being read |

All pointers are 11 bits, so they wrap at 2048 automatically (a ring).

**Store-and-forward:** a frame is shown to the parser (`frame_valid`) only after it is complete and verified.
The parser can therefore never see half a frame or a corrupt one. The cost is one frame of latency.

`frame_byte_out = frame_mem[rd_ptr]` is an **asynchronous read** (distributed RAM): the byte is on the wire in the
same cycle `rd_ptr` changes, so the parser sees zero-latency streaming. `frame_byte_last` is high when
`rd_ptr == read_start_ptr + frame_len - 1`.

### `RX_CHECK_FCS`: five checks in priority order

| # | Condition | Action |
| --- | --- | --- |
| 1 | `had_phy_error` | `cnt_phy_err++`, **roll back** the write pointer |
| 2 | `buffer_overflow` | `cnt_overflow_err++`, roll back |
| 3 | `active_bytes_received < 64` or `> 1518` | `cnt_len_err++`, roll back (runt or giant) |
| 4 | `crc32_reg != 32'hDEBB20E3` | `cnt_crc_err++`, roll back |
| 5 | otherwise: **good** | `cnt_rx_frames++`; if the reader is idle: `frame_valid <= 1`, `frame_len <= bytes − 4`, `rd_ptr <= wr_start_ptr`; else store it as the **queued** frame; then `wr_start_ptr <= wr_ptr` so the next frame starts after it |

`frame_len` is `active_bytes_received − 4`: the 4-byte FCS is excluded.

### The reader's side (the first part of the main always block)

When the parser reads (`frame_valid && frame_read_en`) it advances `rd_ptr`. At the last byte (`frame_byte_last`):
- `frame_done_ack` pulses one clock,
- if a queued frame exists, it becomes the current frame (`rd_ptr`, `read_start_ptr`, `frame_len` are loaded from the `queued_*` registers),
- otherwise `frame_valid` drops.

So the module can hold **one frame being read plus one queued**, which absorbs back-to-back frames.

## 7. Worked example

A 60-byte payload frame with its 4-byte CRC = 64 bytes on the wire (the Ethernet minimum).

1. `crs_dv` rises → `RX_IDLE → RX_PREAMBLE`.
2. 7 preamble bytes pass (dibits `01`), then the SFD's last dibit `11` → `RX_DATA`, CRC reset.
3. 64 × 4 = 256 clocks later `crs_dv` falls (and stays low 2 clocks) → `RX_CHECK_FCS`.
4. `active_bytes_received = 64` ≥ 64 ✓; `crc32_reg == 0xDEBB20E3` ✓; no PHY/overflow error.
5. `cnt_rx_frames` becomes 1; `frame_len = 60`; `frame_valid = 1`; `net_parser` starts reading.

A **runt** (say 50 bytes) fails check 3: `cnt_len_err++`. A frame with one flipped bit fails check 4: `cnt_crc_err++`. In both cases `wr_ptr` returns to `wr_start_ptr`, so the buffer looks as if the frame never arrived.

## 8. Output signals, summarised

| Signal | Meaning |
| --- | --- |
| `frame_valid` | a complete, verified frame is ready to read |
| `frame_len[11:0]` | its length without the FCS |
| `frame_read_en` (input) | parser requests the next byte |
| `frame_byte_out[7:0]`, `frame_byte_last` | current byte and last-byte flag |
| `frame_done_ack` | pulse when the last byte was consumed |
| `cnt_rx_frames`, `cnt_crc_err`, `cnt_len_err`, `cnt_phy_err`, `cnt_overflow_err` | 32-bit counters; any non-zero error sets the sticky feed-loss flag in `net_ingest` |

## 9. "What if" quick answers

- **Two frames arrive back to back?** The second is committed as `queued_valid` while the first is being read; if a third came before the first finished, the ring or the queue could overflow → `cnt_overflow_err`.
- **The PHY sets `rx_err` mid-frame?** `had_phy_error` is latched, the frame is dropped at the end, `cnt_phy_err++`.
- **A jumbo (9000-byte) frame?** Length > 1518 → `cnt_len_err++`; the buffer's overflow guard also protects it.
- **Reset in the middle of a frame?** Asynchronous reset returns `state` to `RX_IDLE` and clears pointers and counters.
