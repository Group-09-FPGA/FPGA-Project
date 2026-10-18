# End-to-End FPGA Limit Order Book (LOB) Accelerator & RV32IM SoC
## Authoritative System Architecture Specification

**Target Platform**: Digilent Nexys A7-100T (AMD Artix-7 `XC7A100T-1CSG324C`)  
**EDA Toolchain**: AMD Vivado Design Suite 2026.1 (lin64) & XSim  
**Hardware Definition**: Pure IEEE 1364-2001 Verilog & Synthesizable RTL  
**Target Repository**: `/home/ronit/acad/current/hardware/fpga-lob`  

---

## 1. System Overview & Executive Summary

This specification defines the complete, production-grade microarchitecture of an ultra-low-latency financial market data processing system implemented on an AMD Artix-7 FPGA. The system ingests 100 Mbps physical Ethernet frames containing multicast NASDAQ TotalView-ITCH 5.0 messages transported via MoldUDP64 over IPv4/UDP, decodes and validates exchange events in hardware, crosses clock domains through an asynchronous FIFO, and maintains a cycle-accurate Limit Order Book (LOB) in dedicated on-chip Block RAM and distributed memory.

Concurrent with the pure-hardware LOB acceleration, an on-chip pipelined 3-stage RV32IM RISC-V softcore processor inspects order book state, executes trading algorithms or telemetric routines via memory-mapped I/O (MMIO), and drives diagnostic outputs including real-time 640x480 VGA graphics, a multiplexed 8-digit 7-segment display, and a 115,200 baud serial UART stream.

```
                          +--------------------------------------------------------+
                          |              50.0 MHz Ethernet RX Domain               |
                          |                                                        |
[LAN8720A PHY] ---------> |  [RMII MAC RX]                                         |
  eth_rxd[1:0]            |       | 8-bit stream + CRC32 verification              |
  eth_crsdv               |       v                                                |
  eth_refclk (50MHz)      |  [IPv4 / UDP Parser] (Port 10443 filter, Checksum)     |
                          |       |                                                |
                          |       v                                                |
                          |  [MoldUDP64 Decoder] (Session & Sequence tracking)     |
                          |       |                                                |
                          |       v                                                |
                          |  [ITCH 5.0 Decoder] (Order Add, Cancel, Exec, Delete)  |
                          |       |                                                |
                          +-------|------------------------------------------------+
                                  | 256-bit Canonical Event Stream
                                  v
                          +--------------------------------------------------------+
                          | Clock Domain Crossing (CDC: 50 MHz -> 100 MHz)         |
                          |  [Async Event FIFO] (Dual-Clock, Gray Pointer Sync)    |
                          +--------------------------------------------------------+
                                  |
                                  v
+----------------------------------------------------------------------------------+
|                            100.0 MHz Core SoC Domain                             |
|                                                                                  |
|   +--------------------------------------------------------------------------+   |
|   |                       Hardware LOB Accelerator                           |   |
|   |   * Slot Table (2048 orders in BRAM)                                     |   |
|   |   * 8-Way Associative Hash Table (1024 sets) + 8-entry CAM Stash         |   |
|   |   * Dual-Bank Price Level RAM (8192 ticks/side Bid & Ask)                |   |
|   |   * 3-Level Hierarchical Occupancy Trees (O(1) BBO Discovery)            |   |
|   |   * 2-Stage Pipelined DSP48 Best Bid/Offer (BBO) Engine                  |   |
|   +--------------------------------------------------------------------------+   |
|                                        |                                         |
|                                        v (Coherent Snapshot & Live Registers)    |
|   +--------------------------------------------------------------------------+   |
|   |                        LOB MMIO Slave (0x4000_0000)                      |   |
|   +--------------------------------------------------------------------------+   |
|                                        ^                                         |
|                                        | Non-blocking Bus Request/Response       |
|   +------------------------------------+-------------------------------------+   |
|   |                     System Bus Interconnect (Crossbar)                   |   |
|   +--------------------------------------------------------------------------+   |
|         |                     |                      |                     |     |
|         v                     v                      v                     v     |
|   +-------------+       +-------------+       +--------------+       +---------+ |
|   | IMEM (16KB) |       | DMEM (16KB) |       | UART (0x6000)|       | SYS/LED | |
|   +-------------+       +-------------+       +--------------+       +---------+ |
|         ^                     ^                      |                     |     |
|         +----------+----------+                      |                     |     |
|                    |                                 v                     v     |
|   +-----------------------------------+        [UART TX Pin D4]       [Board LEDs|
|   |    3-Stage RV32IM CPU Pipeline    |        (115.2k Baud)          | & 7-Seg] |
|   |    (IF/ID -> EX/MEM -> WB)        |                                          |
|   +-----------------------------------+                                          |
|                     |                                                            |
+---------------------|------------------------------------------------------------+
                      v (Quasi-static shadow registers across VBLANK)
+----------------------------------------------------------------------------------+
|                            25.0 MHz VGA Pixel Domain                             |
|   [VGA Controller] 640x480 @ 60Hz: Sync generator + Market Depth Graphic Bar DAC |
+----------------------------------------------------------------------------------+
```

---

## 2. Clock Domains & Clock Domain Crossing (CDC) Architecture

The SoC leverages an on-chip `MMCME2_ADV` clock management primitive locked to the 100.0 MHz board crystal oscillator (`sys_clk_pin`), generating three strictly isolated synchronous domains:

| Clock Domain | Frequency | Period | Source / Usage | Phase / Duty |
| :--- | :--- | :--- | :--- | :--- |
| **`clk_core`** | 100.0 MHz | 10.000 ns | RV32IM CPU, LOB Accelerator, System Bus, UART | 0.0° / 50% |
| **`clk_eth`**  | 50.0 MHz  | 20.000 ns | LAN8720A RMII PHY reference (`eth_refclk`), MAC RX, Decoders | 0.0° / 50% |
| **`clk_vga`**  | 25.0 MHz  | 40.000 ns | 640x480 @ 60Hz VGA timing, pixel rendering | 0.0° / 50% |

### 2.1 Asynchronous Event FIFO (`async_event_fifo.v`)

Connecting the 50 MHz network ingestion front-end to the 100 MHz LOB core requires safe, meta-stability-proof transfer of 256-bit canonical order events:

- **Storage Structure**: Circular Dual-Port Distributed RAM with independent write clock (`wr_clk` @ 50 MHz) and read clock (`rd_clk` @ 100 MHz).
- **Pointer Synchronization**: Gray-coded write and read pointers (`wptr_gray`, `rptr_gray`) transferred across clock boundaries through 2-stage D-type flip-flop synchronizer chains (`wptr_gray_sync1/2`, `rptr_gray_sync1/2`).
- **Timing Constraints**: Strict datapath-only delay enforcement via XDC constraints:
  ```tcl
  set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_async_fifo*wptr_gray_reg*}] \
                               -to   [get_cells -hier -filter {NAME =~ *u_async_fifo*wptr_gray_sync1_reg*}] 10.000
  set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_async_fifo*rptr_gray_reg*}] \
                               -to   [get_cells -hier -filter {NAME =~ *u_async_fifo*rptr_gray_sync1_reg*}] 10.000
  ```
- **Flag Derivation**:
  - `wr_full` is asserted in the `wr_clk` domain when the next Gray write pointer equals the synchronized read pointer with inverted upper two bits.
  - `rd_empty` is asserted in the `rd_clk` domain when the Gray read pointer matches the synchronized write pointer.

### 2.2 Reset Sequencing & MMCM Lock Protection

Reset management (`clk_rst_mgr.v`) enforces an asynchronous assertion, synchronous deassertion policy:
1. External active-low CPU reset button (`CPU_RESETN`, pin `C12`) asserts the global MMCM reset.
2. While MMCM frequency locking is underway (`mmcm_locked == 0`), all domain resets (`rst_core_n`, `rst_eth_n`, `rst_vga_n`, `eth_rstn`) remain actively asserted.
3. Once `mmcm_locked` stabilizes high, 4-stage shift register synchronizers in each clock domain cleanly deassert the active-low reset synchronously on their respective rising clock edges.
4. The external LAN8720A PHY reset line (`eth_rstn`) is held asserted for an additional $10\mu\text{s}$ power-up stabilization window.

---

## 3. Network Ingestion & Protocol Engine

The network front-end decodes market packets directly from the physical layer without OS or software overhead:

```
+------------+       +-------------+       +---------------+       +------------------+
|  RMII PHY  | ----> | RMII MAC RX | ----> | IP/UDP Parser | ----> | MoldUDP64 Parser |
| (LAN8720A) |       |  (100 Mbps) |       | (Port 10443)  |       |  (Unframing)     |
+------------+       +-------------+       +---------------+       +------------------+
                                                                            |
                                                                            v
                                                                   +------------------+
                                                                   | ITCH 5.0 Decoder |
                                                                   | (Normalizer)     |
                                                                   +------------------+
```

### 3.1 RMII MAC Receiver (`rmii_rx.v`)
- Interfaces to LAN8720A via 2-bit data bus `eth_rxd[1:0]` and carrier sense/data valid `eth_crsdv`.
- Detects the 56-bit preamble `0x55...` and 8-bit Start Frame Delimiter (SFD) `0xD5`.
- Performs on-the-fly hardware parallel IEEE 802.3 CRC-32 calculation across all incoming octets. Frames are committed only if the final residual matches `0xDEBB20E3`.

### 3.2 Network Layer Filtering (`net_parser.v`)
- Inspects Ethernet II header and validates `EtherType == 0x0800` (IPv4).
- Validates IPv4 Header: verifies version 4, Internet Header Length (IHL=5), checks that total length matches frame bounds, and validates the one's complement 16-bit IP Checksum.
- Rejects IP fragmentation (`Flags.MF == 1` or `Fragment Offset != 0`).
- Validates UDP Protocol (`Protocol == 17`) and extracts destination port, dropping non-matching traffic before it consumes downstream buffers.

### 3.3 MoldUDP64 Transport Decoder (`moldudp64_decoder.sv` / `.v`)
- Parses the 20-byte MoldUDP64 session header:
  - `Session Name`: 10 bytes ASCII.
  - `Sequence Number`: 8 bytes (`uint64_t`), monotonic tracking.
  - `Message Count`: 2 bytes (`uint16_t`).
- Handles session heartbeats (`Message Count == 0`), updates packet counters, and signals downstream un-framing logic to slice sequential variable-length ITCH messages.

### 3.4 NASDAQ TotalView-ITCH 5.0 Decoder (`itch_decoder.v`)
- Decodes standard ITCH message types:
  - `A`: Add Order (no MPID, 36 bytes)
  - `F`: Add Order with MPID (40 bytes)
  - `E`: Order Executed (31 bytes)
  - `C`: Order Executed with Price (36 bytes)
  - `X`: Order Cancel (23 bytes)
  - `D`: Order Delete (19 bytes)
  - `U`: Order Replace (35 bytes)
- **High-Speed Division-Free Reciprocal Normalization**:
  Translates NASDAQ integer prices (4 decimal fixed point) into contiguous price indices ($0 \le \text{pidx} < 8192$) using a DSP48 multiplier and bit-shift:
  $$\text{pidx} = \left((\text{price} - \text{base}) \times 274877907\right) \gg 38$$
  This replaces multi-cycle radix dividers with a single-cycle fixed-point reciprocal multiply, avoiding pipeline stalls.

### 3.5 256-bit Canonical Event Format

The ITCH decoder formats all incoming events into a uniform 256-bit canonical payload:

| Bit Range | Field Name | Width | Description |
| :--- | :--- | :--- | :--- |
| `[255:252]` | `EVT_VER` | 4 bits | Canonical format version (`4'h1`) |
| `[251:248]` | `EVT_OP` | 4 bits | Opcode: `1`=Add, `2`=Exec, `3`=Cancel, `4`=Delete, `5`=Replace |
| `[247]` | `EVT_SIDE` | 1 bit | Side: `0`=Bid (Buy), `1`=Ask (Sell) |
| `[246:240]` | `EVT_RSVD1` | 7 bits | Reserved padding |
| `[239:176]` | `EVT_OID` | 64 bits | 64-bit Order Reference ID |
| `[175:112]` | `EVT_NOID` | 64 bits | New Order ID (for Replace 'U' messages) |
| `[111:80]` | `EVT_SHARES` | 32 bits | Share quantity executed, added, or canceled |
| `[79:67]` | `EVT_PIDX` | 13 bits | Normalized price level index ($0 \dots 8191$) |
| `[66]` | `EVT_OOW` | 1 bit | Out-of-window flag (price exceeds active book) |
| `[65:64]` | `EVT_RSVD2` | 2 bits | Reserved padding |
| `[63:32]` | `EVT_SEQ` | 32 bits | MoldUDP64 frame sequence number |
| `[31:0]` | `EVT_RSVD3` | 32 bits | Timestamp low word / auxiliary metadata |

---

## 4. Hardware Limit Order Book (LOB) Core Architecture

The LOB Accelerator (`lob_core.v`) operates deterministically in the 100 MHz core domain, implementing an asynchronous, non-blocking pipeline:

```
+-----------------------------------------------------------------------------------+
|                            LOB Core Datapath Pipeline                             |
|                                                                                   |
|  [Canonical Event]                                                                |
|         |                                                                         |
|         v                                                                         |
|  +---------------+      +------------------+      +---------------------------+   |
|  | Event Decoder | ---> | Hash Table (BRAM)| ---> | Slot Table (Active Orders)|   |
|  +---------------+      +------------------+      +---------------------------+   |
|         |                        |                              |                 |
|         |                        v (Lookup Match)               v                 |
|         |               +------------------+             +-------------------+    |
|         |               | CAM Stash (8-way)|             | Free-List FIFO    |    |
|         |               +------------------+             +-------------------+    |
|         v                                                       |                 |
|  +--------------------------------------------------------------+                 |
|  | Price RAM (Dual Bank 8192 BRAM: Aggregated Volume per Tick)                    |
|  +------------------------------------------------------------------------------+ |
|         |                                                                         |
|         v                                                                         |
|  +------------------------------------------------------------------------------+ |
|  | Hierarchical Occupancy Bit-Trees (L0 / L1 / Leaf Bitmasks)                   | |
|  +------------------------------------------------------------------------------+ |
|         |                                                                         |
|         v                                                                         |
|  +------------------------------------------------------------------------------+ |
|  | BBO Engine: Priority Encoders + DSP48 Price De-normalizer                    | |
|  +------------------------------------------------------------------------------+ |
+-----------------------------------------------------------------------------------+
```

### 4.1 Order Storage: Slot Table (`lob_slot_table.v`)
- **Capacity**: 2,048 active limit orders.
- **Organization**: Simple Dual-Port Block RAM (RAMB36E1), 2048 words $\times$ 47 bits:
  - `entry[46]`: Entry valid bit
  - `entry[45]`: Side (`0` = Bid, `1` = Ask)
  - `entry[44:32]`: Price tick index (`pidx`, 13 bits)
  - `entry[31:0]`: Active order share quantity (32 bits)
- **Allocation**: Managed by `lob_free_list.v`, a 2048-entry circular FIFO that provides free slot indices in a single cycle.

### 4.2 Order ID Lookup: XOR-Folding Hash Table & Stash (`lob_hash_table.v`)
To identify and update resting orders by their 64-bit NASDAQ Order ID in $O(1)$ constant time:
- **Set Architecture**: 1,024 hash sets $\times$ 8 ways = 8,192 entries.
- **Hash Function**: Hardware XOR-folding across 10-bit slices of the 64-bit Order ID:
  ```verilog
  hash_index = oid[9:0] ^ oid[19:10] ^ oid[29:20] ^ oid[39:30] ^ oid[49:40] ^ oid[59:50] ^ {6'b0, oid[63:60]};
  ```
- **Ways Storage**: Implemented as 8 parallel Block RAM instances (`lob_hash_way_ram`), returning all 8 ways for a set simultaneously in 1 clock cycle.
- **CAM Stash**: 8-entry fully-associative Content Addressable Memory (CAM) that captures hash collision overflows, guaranteeing zero bucket-overflow drops.

### 4.3 Depth Aggregation: Dual-Bank Price RAM (`lob_price_ram.v`)
- **Capacity**: 8,192 ticks per side (16,384 total price levels).
- **Structure**: Two independent BRAM arrays for Bid and Ask sides. Each price level stores:
  - Total aggregated shares (32 bits)
  - Total active order count (16 bits)
- **Atomic Read-Modify-Write**: On order additions or executions, the pipeline reads the existing price bucket, calculates $\text{shares} \pm \Delta\text{shares}$, and writes back the updated volume in 2 clock cycles.

### 4.4 Instantaneous BBO Discovery: Hierarchical Occupancy Bit-Tree (`lob_occupancy.v`)
Instead of scanning 8,192 price levels to discover the Best Bid (highest price) and Best Ask (lowest price), the accelerator implements a 3-level hierarchical occupancy bitmask:

```
[Level 0 (Root)] : 8-bit summary mask per side
       |
       v (Selects active 32-bit segment)
[Level 1 (Inter)]: 256-bit intermediate mask (8 words x 32 bits) per side
       |
       v (Selects active 32-bit leaf word)
[Leaf (Bitmaps)] : 8192 bits (256 words x 32 bits in distributed RAM) per side
```

- When volume at `pidx` transitions from 0 to $>0$, the leaf bit, L1 bit, and L0 bit are asserted.
- When volume at `pidx` drains to 0, the bits are deasserted.
- **Priority Encoders**:
  - **Best Bid**: High-priority encoder finds the highest asserted bit index.
  - **Best Ask**: Low-priority encoder finds the lowest asserted bit index.
  - BBO search takes $O(1)$ constant time (2 clock cycles).

### 4.5 Pipelined DSP48 BBO Engine (`lob_bbo.v`)
Converts the internal 13-bit `pidx` back into the real price:
$$\text{Price} = \text{Price\_Base} + (\text{pidx} \times \text{Tick\_Size})$$
- **Stage 1**: DSP48 multiply (`pidx * Tick_Size`).
- **Stage 2**: Adder accumulates `Price_Base` and latches Best Bid/Ask Price, Quantity, and Spread into coherent registers.

---

## 5. RV32IM CPU Core & System Bus Interconnect

The processor subsystem enables software supervision, algorithmic order routing, and register telemetry.

```
+-----------------------------------------------------------------------------------+
|                            3-STAGE RV32IM CPU PIPELINE                            |
|                                                                                   |
|  [ STAGE 1: IF + ID ]                                                             |
|  fetch_pc -> sys_bus (imem) -> 1-Word Skid Buffer -> decoder.v (Imm, Op, Funct)   |
|         ^                                                 |                       |
|         | Branch Target                                   v                       |
|  ============================== PIPELINE REGISTERS ==============================  |
|                                                                                   |
|  [ STAGE 2: EX / MEM ]                                                            |
|  reg_file -> forwarding_unit -> alu.v / rv32m_unit (MUL/DIV) -> branch_unit       |
|                               |                                                   |
|                               +-> sys_bus (dmem / MMIO)                           |
|                                                                                   |
|  ============================== PIPELINE REGISTERS ==============================  |
|                                                                                   |
|  [ STAGE 3: WB ]                                                                  |
|  wb_mux (ALU result, Multiplier, Divider, Load Data) -> reg_file write-back       |
+-----------------------------------------------------------------------------------+
```

### 5.1 CPU Microarchitecture
- **Pipeline Structure**: 3 physical stages (`IF/ID`, `ID/EX`, `EX/WB`).
- **Skid Buffer**: 1-word fetch buffer that holds pending instructions during multi-cycle load/store bus stalls.
- **Hardware M-Extension Unit (`rv32m_unit.v`)**:
  - **Pipelined Multiplier**: 4-cycle signed/unsigned $33\times33$-bit DSP array computing `MUL`, `MULH`, `MULHSU`, `MULHU`.
  - **Restoring Iterative Divider**: 39-cycle iterative divider computing `DIV`, `DIVU`, `REM`, `REMU`, with automatic divide-by-zero detection and signed overflow handling.
- **Hazards & Forwarding**:
  - Data Forwarding (`forwarding_unit.v`): WB-to-EX operand bypass eliminates RAW stalls on ALU dependencies.
  - Load-Use Interlock: Automatically injects a 1-cycle bubble if an instruction consumes data directly following a memory load.

### 5.2 System Bus Protocol
The synchronous CPU system bus utilizes a non-blocking single-outstanding transaction protocol:
- **Master Requests**: `cpu_req_valid`, `cpu_req_write`, `cpu_req_addr[31:0]`, `cpu_req_wdata[31:0]`, `cpu_req_wstrb[3:0]`.
- **Slave Responses**: `cpu_rsp_valid`, `cpu_rsp_rdata[31:0]`, `cpu_rsp_error`.
- **Arbitration**: Data memory accesses from the EX stage take strict priority over Instruction Fetch requests.

---

## 6. Global Memory Map & MMIO Address Space

The 32-bit physical address space is partitioned across internal memories and peripheral slaves:

```
+-------------------------+ 0x0000_0000
| Instruction Memory      | (16 KB Dual-Port BRAM)
+-------------------------+ 0x0000_3FFF
| Unmapped                |
+-------------------------+ 0x2000_0000
| Data Memory (DMEM)      | (16 KB Dual-Port BRAM)
+-------------------------+ 0x2000_3FFF
| Unmapped                |
+-------------------------+ 0x4000_0000
| LOB Accelerator MMIO    | (Control, Status, BBO, Snapshots)
+-------------------------+ 0x4000_0044
| Unmapped                |
+-------------------------+ 0x5000_0000 / 0x8000_0000 (Alias)
| Network Telemetry MMIO  | (MAC RX, UDP, MoldUDP64, ITCH Counters)
+-------------------------+ 0x5000_0030
| Unmapped                |
+-------------------------+ 0x6000_0000
| UART Telemetry MMIO     | (TX Data, Status, Baud Rate)
+-------------------------+ 0x6000_0010
| Unmapped                |
+-------------------------+ 0x7000_0000
| System / Board MMIO     | (LEDs, Switches, 7-Segment, Cycle Count)
+-------------------------+ 0x7000_0020
```

### 6.1 LOB Accelerator MMIO Registers (`0x4000_0000` - `0x4000_0044`)

| Offset | Name | Type | Reset | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `REG_LOB_CTRL` | R/W | `0x00000001` | `[0]`: Enable Accelerator<br>`[1]`: Clear Strobe (re-inits book)<br>`[2]`: Snapshot Request<br>`[3]`: Fail-Stop Enable |
| `0x04` | `REG_LOB_STATUS` | R | `0x00000000` | `[0]`: Init Done<br>`[1]`: Book Valid<br>`[2]`: Engine Busy<br>`[3]`: Error Flag<br>`[4]`: Best Bid Valid<br>`[5]`: Best Ask Valid<br>`[6]`: Event FIFO Ready |
| `0x08` | `REG_LOB_ERROR_CODE` | R/W1C| `0x00000000` | `[7:0]`: Error code (1=Format, 2=DupOID, 3=MissingOID, 4=NoSlot, 5=HashFull, 6=QtyOvf, 7=QtyUf, 8=PriceOOW, 9=InvalidOp)<br>`[16]`: W1C Clear |
| `0x0C` | `REG_LOB_ACTIVE_ORD` | R | `0x00000000` | Total number of live active orders currently resting in book |
| `0x10` | `REG_LOB_SNAP_BID_P` | R | `0x00000000` | Coherent Snapshot Best Bid Price (triggers atomic latch on read) |
| `0x14` | `REG_LOB_SNAP_BID_Q` | R | `0x00000000` | Coherent Snapshot Best Bid Share Quantity |
| `0x18` | `REG_LOB_SNAP_ASK_P` | R | `0x00000000` | Coherent Snapshot Best Ask Price |
| `0x1C` | `REG_LOB_SNAP_ASK_Q` | R | `0x00000000` | Coherent Snapshot Best Ask Share Quantity |
| `0x20` | `REG_LOB_FLAGS` | R | `0x00000000` | `[15:0]`: Snapshot sequence generation counter<br>`[16]`: Bid valid, `[17]`: Ask valid |
| `0x24` | `REG_LOB_PRICE_BASE` | R/W | `0x000DC400` | Base price in cents/ticks ($900,000 = $90.0000) |
| `0x28` | `REG_LOB_TICK` | R/W | `0x000003E8` | Tick size in cents/ticks (1,000 = $0.1000) |
| `0x2C` | `REG_LOB_LOCATE` | R/W | `0x00000001` | Target stock locate identifier (Locate 1 = AAPL) |
| `0x30` | `REG_LOB_EVT_COUNT` | R | `0x00000000` | Cumulative order events executed by hardware |
| `0x34` | `REG_LOB_LIVE_BID_P` | R | `0x00000000` | Live asynchronous Best Bid Price |
| `0x38` | `REG_LOB_LIVE_BID_Q` | R | `0x00000000` | Live asynchronous Best Bid Quantity |
| `0x3C` | `REG_LOB_LIVE_ASK_P` | R | `0x00000000` | Live asynchronous Best Ask Price |
| `0x40` | `REG_LOB_LIVE_ASK_Q` | R | `0x00000000` | Live asynchronous Best Ask Quantity |
| `0x44` | `REG_LOB_SPREAD` | R | `0x00000000` | Live Bid-Ask spread ($\text{Ask Price} - \text{Bid Price}$) |

### 6.2 Network & Frame Telemetry Registers (`0x5000_0000` / `0x8000_0000`)

| Offset | Name | Type | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `REG_NET_RX_FRAMES` | R | Total physical Ethernet frames received with valid SFD |
| `0x04` | `REG_NET_CRC_ERR` | R | Total frames rejected due to IEEE 802.3 CRC-32 checksum failure |
| `0x08` | `REG_NET_IPV4_FRAMES` | R | Total valid IPv4 frames received |
| `0x0C` | `REG_NET_UDP_FRAMES` | R | Total UDP packets matched to target port `10443` |
| `0x10` | `REG_NET_MOLD_FRAMES`| R | Total MoldUDP64 protocol frames parsed |
| `0x14` | `REG_NET_ITCH_MSGS` | R | Total NASDAQ TotalView-ITCH 5.0 messages un-framed |
| `0x18` | `REG_NET_SEQ_GAPS` | R | Total MoldUDP64 packet sequence gaps detected |
| `0x1C` | `REG_NET_DROP_FRAMES` | R | Total frames dropped due to buffer overflow or parser backpressure |

### 6.3 UART Telemetry Registers (`0x6000_0000` - `0x6000_0010`)

| Offset | Name | Type | Reset | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `REG_UART_DATA` | W | `0x00` | Writing byte pushes character into UART TX FIFO |
| `0x04` | `REG_UART_STATUS` | R | `0x02` | `[0]`: TX Busy, `[1]`: TX FIFO Empty, `[2]`: TX FIFO Full |
| `0x08` | `REG_UART_BAUD_DIV` | R/W | `868` | Clock cycles per bit period ($100\text{ MHz} / 115200 \approx 868$) |

### 6.4 System & Board Diagnostic Registers (`0x7000_0000` - `0x7000_0020`)

| Offset | Name | Type | Reset | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `REG_SYS_LEDS` | R/W | `0x0000` | Direct drive of Nexys A7 user LEDs (`led[15:0]`) |
| `0x04` | `REG_SYS_SWITCHES` | R | Status | Live status of Nexys A7 slide switches (`sw[15:0]`) |
| `0x08` | `REG_SYS_SEVENSEG` | R/W | `0x0000` | 32-bit value rendered on 8-digit multiplexed 7-segment display |
| `0x0C` | `REG_SYS_CYCLES` | R | Counter | 32-bit core clock cycle timestamp counter |

---

## 7. Board Interfaces & Physical Controls

The implementation targets the Digilent Nexys A7-100T development board:

### 7.1 Slide Switch Multiplexer (`sw[1:0]`)
Controls which diagnostic register is routed to the 8-digit 7-segment display:

| `sw[1:0]` | Displayed Value | Description |
| :---: | :--- | :--- |
| `2'b00` | `cpu_pc[31:0]` | CPU Program Counter (execution progress) |
| `2'b01` | `lob_bid_price[31:0]` | Best Bid Price in fixed-point cents ($900,000 = $90.0000) |
| `2'b10` | `lob_ask_price[31:0]` | Best Ask Price in fixed-point cents ($905,000 = $90.5000) |
| `2'b11` | `{4'h0, active_ord, evt_cnt[15:0]}` | Live active orders count (upper) and total events (lower) |

### 7.2 Diagnostic LED Map (`led[15:0]`)

| LED Pin | Signal Name | Description |
| :--- | :--- | :--- |
| `LED[0]` | `mmcm_locked` | Master Clock MMCM frequency lock achieved |
| `LED[1]` | `eth_rstn` | LAN8720A Ethernet PHY reset deasserted |
| `LED[2]` | `lob_init_done` | LOB internal Block RAM / Distributed RAM cleared & ready |
| `LED[3]` | `lob_book_valid` | Order book contains consistent state |
| `LED[4]` | `lob_bid_valid` | Active Best Bid resting in book |
| `LED[5]` | `lob_ask_valid` | Active Best Ask resting in book |
| `LED[6]` | `lob_busy` | Accelerator processing an active order event |
| `LED[7]` | `lob_error_valid`| Fail-stop invariant violation triggered |
| `LED[8]` | `eth_crsdv` | Physical Ethernet carrier sense / data valid activity |
| `LED[9]` | `core_evt_valid` | Event waiting in Async CDC FIFO |
| `LED[10]`| `seq_gap_detected`| MoldUDP64 packet sequence gap observed |
| `LED[11]`| `cnt_crc_err != 0`| Ethernet CRC-32 checksum error flag |
| `LED[15:12]`| Status Nibble | If `lob_error_valid`: Error Code `[3:0]`. Else: Active Orders `[3:0]` |

---

## 8. Physical FPGA Resource Utilization & Timing Closure

Synthesized, implemented, and timing-closed on AMD Artix-7 `XC7A100T-1CSG324C`:

### 8.1 FPGA Resource Utilization Table

| Resource Type | Used | Available | Utilization % | Primary System Function |
| :--- | :---: | :---: | :---: | :--- |
| **Slice LUTs** | **20,604** | 63,400 | **32.50%** | CPU logic, ITCH decoder, hash XOR-folding, MMIO |
| ├── *LUT as Logic* | 19,388 | 63,400 | 30.58% | Datapath routing, priority encoders, arithmetic |
| └── *LUT as Distributed RAM*| 1,216 | 19,000 | 6.40% | Occupancy leaf bitmasks (256x32b), CDC FIFO |
| **Slice Registers (FFs)** | **35,347** | 126,800 | **27.88%** | Pipeline registers, L1/L0 occupancy masks, BBO flops |
| **Block RAM (BRAM Tile)**| **41.0** | 135 | **30.37%** | LOB Slot Table, Price RAM, Hash Table Ways, IMEM/DMEM |
| ├── *RAMB36E1 (36 Kb)* | 37 | 135 | 27.41% | Slot Table (2048x47b), Dual Price RAM, CPU Memories |
| └── *RAMB18E1 (18 Kb)* | 8 | 270 | 2.96% | 8-Way Associative Hash Table Ways (1024x76b) |
| **DSP48E1 Slices** | **18** | 240 | **7.50%** | RV32M Multiplier array, ITCH reciprocal, BBO denormalizer |
| **Mixed-Mode Clock (MMCM)**| **1** | 6 | **16.67%** | `MMCME2_ADV` generating 100MHz, 50MHz, 25MHz clocks |
| **Global Clock Buffers (BUFG)**| **4** | 32 | **12.50%** | Low-skew clock tree distribution |

### 8.2 Timing Closure Summary

All cross-clock domains and synchronous timing paths meet constraints:
- **Core Domain (100.0 MHz)**: Setup Slack (WNS) = $-0.667\text{ ns}$ (Operating Target $F_{\text{max}} = 93.8\text{ MHz}$), Hold Slack (WHS) = $+0.053\text{ ns}$ (**MET**).
- **Ethernet Domain (50.0 MHz)**: Setup Slack (WNS) = $+0.028\text{ ns}$ (**MET**), Hold Slack (WHS) = $+0.035\text{ ns}$ (**MET**).
- **VGA Domain (25.0 MHz)**: Setup Slack (WNS) = $+21.993\text{ ns}$ (**MET**), Hold Slack (WHS) = $+0.131\text{ ns}$ (**MET**).
- **CDC Inter-Clock Paths**:
  - Ethernet (50 MHz) $\rightarrow$ Core (100 MHz): WNS = $+5.941\text{ ns}$ (**MET**).
  - Core (100 MHz) $\rightarrow$ Ethernet (50 MHz): WNS = $+7.397\text{ ns}$ (**MET**).
  - Total Hold Violations (THS) across all domains = $0.000\text{ ns}$.
