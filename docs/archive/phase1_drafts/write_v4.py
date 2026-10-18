import os

content = """# Phase 1.4 Definitive Architecture Specification: RV32IM + Ethernet/ITCH Limit Order Book Accelerator
Version: v4 (Independent Audit Corrected)
Date: 2026-10-09

## 1. Scope, Assumptions, and Explicit Exclusions

This specification dictates the hardware-software architecture for an FPGA-based Limit Order Book (LOB) accelerator, managed by an RV32IM softcore. 

**Assumptions:**
- Target: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T).
- The network feed is standard 100 Mbps Ethernet (RMII) providing NASDAQ TotalView-ITCH 5.0 inside MoldUDP64/IPv4/UDP.
- BRAM read latency is exactly 1 cycle (DOA_REG = 0).

**Explicit Exclusions:**
- **No hardware TCP/IP:** GLIMPSE snapshot recovery is handled in software by the RV32IM CPU via an out-of-band management interface, not by the hardware parser.
- **No VLAN (802.1Q) support:** VLAN-tagged Ethernet frames are silently dropped.
- **Price Range Limitation:** The hardware tracks prices using a 16-bit integer index (0 to 65,535 ticks). ITCH prices exceeding this range are filtered and dropped by the hardware parser.
- **No Atomic Replace:** The ITCH Replace (`U`) message is NOT atomic in hardware. It is transformed into a sequential `Delete` followed by `Add`.

## 2. Repository Baseline and Evidence Classification

- **Branch:** `main`
- **Commit:** `7c2134f84706c82ec88efd0a24b01552755fb966`
- **State:** CPU, System Bus, and RV32M extensions exist in `rtl/cpu/core/` and have verified static timing analysis reports (+0.420 ns setup slack at 100 MHz constraint; physically verified at 1 Hz).
- **Unimplemented:** The MAC, ITCH Parser, and LOB Accelerator RTL do not exist in the repository.

**Evidence Classification:**
- *Verified Fact:* Artix-7 XC7A100T primitive capabilities and capacities. CPU baseline timing closure.
- *Calculated:* BRAM primitive counts, CDC FIFO depth, exact cycle schedules, and throughput bounds.
- *Design Decision:* Sequential Replace handling, Fail-Stop invalidation policy, Price-Level RAM mapping.
- *Requiring Validation:* 98.5% BRAM utilization routability (P&R congestion), 50MHz RMII setup/hold timing.

## 3. System Architecture and Module Boundaries

```text
[LAN8720A PHY] 
    | 50MHz RMII (RXD[1:0], CRS_DV)
    v
[MAC RX] -> [Dual-Bank Packet Buffers] -> [IPv4/UDP/MoldUDP64/ITCH Parser]
    |                                                  |
    +------------------ clk_eth_ref (50 MHz) ----------+
    |                 CDC Canonical Event FIFO         |
    +------------------ clk_core (100 MHz) ------------+
    |
    v (128-bit Canonical Event Bus)
[Event Sequencer] <---- [RV32IM CPU MMIO Event Injector]
    |
    v 
[Hardware LOB Core]
  - Free-List FIFO
  - Hash Table & Stash
  - Slot Table
  - Price Level RAM
  - Bid/Ask Occupancy Masks
    |
    +--> [VGA Framebuffer] -> clk_vga (25.175 MHz) -> VGA DAC
    +--> [MMIO BBO Shadow Regs] -> CPU Sys Bus
```

## 4. Clock-Domain and Reset Architecture

| Domain | Frequency | Source | Purpose / Modules |
|---|---|---|---|
| `clk_eth_ref` | 50.00 MHz | MMCM | RMII RX, MAC, Pkt Buffers, Parsers, CDC FIFO (Write) |
| `clk_core` | 100.00 MHz | MMCM | CDC FIFO (Read), LOB Core, CPU, MMIO, VGA (Write) |
| `clk_vga` | 25.175 MHz | MMCM | VGA Framebuffer (Read), VGA Sync timing |

**Reset:**
- External active-low `btnCpuReset` is captured asynchronously and synchronized into each of the three domains using standard 2-flop synchronizers.
- **CDC Reset Coordination:** If `clk_eth_ref` or `clk_core` resets, the entire LOB is invalidated. The CDC FIFO pointers are cleared on a synchronized reset in both domains. 
- A CPU-issued soft reset via MMIO can clear the LOB Core and CDC FIFO without resetting the CPU.

## 5. Ethernet/RMII Interface and Packet Buffering

**RMII Timing:** `clk_eth_ref` is sourced by the FPGA MMCM and driven to the PHY. `RXD[1:0]` and `CRS_DV` are sampled on the rising edge of `clk_eth_ref`. (Requires explicit `set_input_delay` constraints in XDC based on LAN8720A datasheet).

**Packet Buffers (Ping-Pong):**
- Two independent banks, 1024 x 16 bits each (Bank 0 and Bank 1).
- **State Machine:** `FREE` -> `FILLING` -> `READY` -> `PARSING`.
- **Ownership:** 
  1. MAC RX owns a `FREE` bank. Writes bytes.
  2. If Ethernet FCS is valid and length is legal, state becomes `READY`. Ownership passes to Parser.
  3. Parser extracts messages. When done, state becomes `FREE`.
- **Backpressure:** If MAC requires a bank but both are `READY`/`PARSING`, the MAC drops the incoming Ethernet frame and increments `rx_drop_cnt`.
- **FCS:** Frames with invalid FCS or malformed lengths are silently discarded; the bank is immediately returned to `FREE`.

## 6. IPv4/UDP, MoldUDP64, and ITCH Parsing

- **IPv4/UDP:** Validates Protocol 17 (UDP) and matches Target IP/Port (configurable via MMIO). **Checksums are ignored** (Design Acceptance: Checksum offload is omitted to save LUTs; corrupted UDP payloads that pass Ethernet FCS are probabilistically negligible but represent a known limitation).
- **MoldUDP64:** 
  - `Expected_Seq` is tracked.
  - If `Msg_Seq == Expected_Seq`: Parser processes `Message Count` messages.
  - If `Msg_Seq > Expected_Seq`: Gap detected. Parser asserts `ERR_SEQ_GAP`.
  - If `Msg_Seq < Expected_Seq`: Duplicate packet. Parser silently drops the payload and frees the buffer.
- **ITCH 5.0:**
  - Decodes `A`, `F`, `E`, `C`, `X`, `D`, `U`.
  - Messages with `Price > 65535` are dropped (logged to error counter).
  - `U` (Replace) generates two events sequentially: `Delete(Old_ID)` then `Add(New_ID)`.

## 7. Canonical Event Format

Transferred via the CDC FIFO (128 bits wide):
- `[127:125]` **Opcode:** `000`=NOP, `001`=Add, `010`=Exec, `011`=Cancel, `100`=Delete.
- `[124]` **Side:** `0`=Buy, `1`=Sell.
- `[123:60]` **Order ID:** 64-bit integer.
- `[59:44]` **Reserved:** 16 bits (Zeroed).
- `[43:28]` **Price:** 16-bit integer (Max 65,535).
- `[27:0]` **Shares:** 28-bit integer.

## 8. LOB Data Model and Invariants

- **Add:** Allocates slot, stores Order, adds shares to Price Level, updates Occupancy.
- **Exec / Cancel:** Reduces shares in Slot and Price Level. (ITCH `C` messages supply an execution price, but hardware decrements the resting order's original price).
- **Delete:** Clears slot, removes shares from Price Level, deallocates slot to Free-List. Removes from Hash.
- **BBO:** Highest active Bid and lowest active Ask, determined by priority encoders over the Occupancy masks.

## 9. Hashing, Slot Allocation, and Capacity Guarantees

**Capacity Guarantee:** Exactly 4,096 concurrent active orders, *subject to hash collision limits*.
- **Slot Table:** 4096 depth. 
- **Free-List FIFO:** 4096 depth. Initialized with indices 0..4095. Guarantees deterministic slot allocation.
- **Hash Table:** 2048-set, 4-way associative (8192 capacity). Hash function: CRC32-C (lower 11 bits for set index).
- **Stash:** 16-entry CAM.
- **Failure Semantics:** If an `Add` event occurs and the Free-List is empty OR the Hash Table way/stash is full, the hardware asserts `ERR_CAPACITY`, sets `BOOK_VALID = 0` (Fail-Stop), and ignores all subsequent events until a CPU-directed recovery.

## 10. Memory Inventory and Primitive-Level Resource Calculations

Calculated using Xilinx Artix-7 RAMB36E1 configurations:

| Memory | Logical Size | RAMB36E1 Config | Primitives Req | Domain |
|---|---|---|---|---|
| **Hash Table** | (2048 x 77) x 4 ways | 2K x 18 (True Dual Port) | 5 per way * 4 = 20 | `clk_core` |
| **Slot Table** | 4096 x 129 | 4K x 9 (Simple Dual Port) | 15 | `clk_core` |
| **Price Levels** | 65536 x 32 | 1K x 36 (cascade 64 deep) | 64 | `clk_core` |
| **Bid Occupancy** | 65536 x 1 | 32K x 1 (cascade 2 deep) | 2 | `clk_core` |
| **Ask Occupancy** | 65536 x 1 | 32K x 1 (cascade 2 deep) | 2 | `clk_core` |
| **CDC Event FIFO**| 512 x 128 | 512 x 72 (width 144) | 2 | `eth` / `core` |
| **Packet Buffers**| (1024 x 16) x 2 | 1K x 36 | 2 | `clk_eth_ref` |
| **VGA Framebuf** | 307200 x 1 | 32K x 1 (10 blocks needed) | 10 | `core` / `vga` |
| **CPU Mem (I/D)** | 8192 x 32 (x2) | 1K x 36 (8 per memory) | 16 | `clk_core` |
| **Total** | | | **133 / 135 (98.5%)** | |

*Conclusion:* The design fits the Artix-7 logically, but 98.5% BRAM utilization leaves effectively zero routing margin. Place and route congestion is a P0 risk.

## 11. Exact Operation State Machines and Cycle Schedules

**Add Operation (8 cycles, deterministic):**
- `C0`: Read CDC FIFO. Issue CRC32(Order_ID). Pop Free-List.
- `C1`: Route hash index to Hash BRAM Address. Free-List slot index available.
- `C2`: Read Hash BRAM (Port A). 
- `C3`: Hash Hit/Miss logic. Determine empty way. 
- `C4`: Write Hash BRAM (Port B). Issue Slot BRAM Write. Address Price Level RAM and Occupancy Mask (Port A).
- `C5`: Price Level and Occupancy Mask Read Data available.
- `C6`: Compute `Price_Shares + Evt_Shares`. Write Price Level RAM (Port B). Write Occupancy Mask (Port B).
- `C7`: BBO Priority Encoder cascades evaluate new BBO. Complete.

*Note:* Price Level RAM uses Port A for Read and Port B for Write. Hash uses TDP.

## 12. BBO Calculation and Price-Level Representation

- **Price Mapping:** 16-bit integer directly addresses the 65,536-deep Price Level RAM.
- **Side Separation:** The Price Level RAM stores unsigned quantity only. The side is tracked by the Bid Occupancy Mask and Ask Occupancy Mask.
- **BBO:** A 65,536-bit priority encoder (implemented as a pipelined tree) finds the highest `1` in the Bid Mask and the lowest `1` in the Ask Mask.

## 13. CPU Bus/MMIO Register Map

Base Address: `0x4000_0000`
- `0x00`: Control (Bit 0: Enable, Bit 1: LOB Reset).
- `0x04`: Status (Bit 0: Valid, Bit 1: Err_Gap, Bit 2: Err_Hash, Bit 3: Err_Cap).
- `0x08`: `Expected_Seq` (R/W).
- `0x0C`: `BBO_LATCH` (Write 1 to freeze shadows).
- `0x10`: Shadow Bid Price (R).
- `0x14`: Shadow Bid Qty (R).
- `0x18`: Shadow Ask Price (R).
- `0x1C`: Shadow Ask Qty (R).

## 14. Snapshot/Recovery State Machine

**Invariants:** `BOOK_VALID` is only `1` when the LOB is perfectly synced with the multicast sequence.
1. **Error:** Hash fails or Sequence Gap. State -> `INVALID`. `BOOK_VALID = 0`.
2. **Clear:** CPU writes LOB Reset. Hardware clears all Slot/Hash/Price BRAMs to 0.
3. **Load:** CPU downloads GLIMPSE snapshot over OOB network, writes synthetic Add events via MMIO.
4. **Reconcile:** CPU sets `Expected_Seq` to GLIMPSE closing sequence. CPU sets State -> `RECOVERING`.
5. **Resume:** Hardware waits for MoldUDP64 packet with `Msg_Seq == Expected_Seq`. When received, State -> `VALID`, `BOOK_VALID = 1`, and processing resumes. Packets received during `RECOVERING` with `Seq > Expected_Seq` are dropped.

## 15. Error Handling and Fail-Safe Behavior

- **Partial Replace Fail-Stop:** If a `Replace` message's `Delete` succeeds but the subsequent `Add` fails (hash full), the book is immediately marked `INVALID` and halted. A partially updated book will never be broadcast as valid.
- **Corrupt Packets:** Dropped without altering LOB state.

## 16. VGA/Framebuffer Architecture

- 640x480 Monochrome mapped to 307,200 bits.
- 10 RAMB36E1s in 32Kx1 mode = 327,680 addressable bits.
- `clk_core` writes 32-bit words (Port A).
- `clk_vga` reads 1-bit pixels sequentially (Port B).
- Simultaneous Read/Write: Allowed. Standard dual-port collision rules apply (old data read during write).

## 17. Throughput, Buffering, and Performance Bounds

- **Network Bound:** 100 Mbps RMII = Max 148,809 frames/sec. Worst-case min-size frames yielding ITCH messages equates to ~1.4M canonical events/sec.
- **Hardware Service Rate:** 8 cycles per operation at 100 MHz = 12.5M events/sec.
- **Conclusion:** Hardware service rate (12.5M) strictly exceeds worst-case arrival rate (1.4M). Backpressure to the MAC will only occur if the CPU halts the Event Sequencer.

## 18. Verification Plan and Acceptance Criteria

- **Gate 1 Validation:** Synthesize Hash and Price Level RAMs to verify 133 BRAM inference and routing feasibility.
- **Integration Test:** Inject 1M-message PCAP containing Add, Exec, Cancel, Delete, Replace. Compare final hardware BBO and MMIO status against Python golden model.

## 19. Open Decisions and Implementation Blockers

- **Blocker (Physical):** 98.5% BRAM utilization. **Decision Required:** Must run post-synthesis routing constraint checks before committing to the 65,536 Price Level depth.

## 20. Phase-by-Phase Implementation Roadmap

- **Gate 1:** CDC FIFO, MAC RX, and Parsers. (Target: `clk_eth_ref` timing closure).
- **Gate 2:** LOB Memories (Hash, Slot, Price, Occupancy) synthesis inference verification.
- **Gate 3:** Event Sequencer State Machine.
- **Gate 4:** CPU MMIO Integration and VGA.

## 21. Independent Consistency Audit and Traceability Table

| ID | Severity | Finding | Affected Section | Resolution | Evidence Level | Required Validation |
|---|---|---|---|---|---|---|
| AUD-01 | P0 | BRAM count mathematically incorrect for 32-bit Price RAM / 640x480 VGA | 10 | Recomputed exact RAMB36E1 physical mapping (64 blocks for price, 10 for VGA). Total 133. | Calculated | Synth utilization report |
| AUD-02 | P0 | Unrealistic guaranteed capacity via hashing | 9 | Reclassified capacity as probabilistic subject to hash collisions. Fail-stop on full. | Calculated | Hash collision sim |
| AUD-03 | P0 | Non-atomic Replace leaves book corrupted | 6, 15 | Instituted strict fail-stop policy. If Add phase fails, LOB transitions to INVALID. | Design Decision | PCAP fault injection TB |
| AUD-04 | P0 | Unclear BRAM read latencies in schedule | 11 | Explicitly budgeted 1 cycle latency for BRAM reads in 8-cycle state machine. | Datasheet | Post-route STA |
| AUD-05 | P1 | Event FIFO lacks explicit CDC parameters | 4, 10 | Defined dual-clock 512x128 FIFO with Gray-coded pointers crossing 50MHz to 100MHz. | Design pattern | `report_cdc` analysis |
| AUD-06 | P0 | Invalid Recovery Sequence matching | 14 | Defined Expected_Seq freeze and exact resumption trigger on matching MoldUDP header. | Protocol logic | GLIMPSE recovery TB |
| AUD-07 | P0 | Price limits vs 32-bit ITCH fields | 7, 8 | Down-sized canonical price to 16-bit to match affordable 65,536-deep BRAM bounds. | Design Decision | None |

## 22. Final Readiness Verdict

**CONDITIONALLY READY**

**Conditions for RTL Implementation:**
1. Gate 1 (Network Parsers and CDC FIFO) is cleared for full implementation.
2. Gate 2 (LOB Core) is cleared for RTL entry, but **MUST** undergo a synthesis and routing utilization check (P&R) to prove that 133/135 BRAMs (98.5%) can be successfully routed on the XC7A100T device before logic implementation proceeds further. If P&R fails, Price Level RAM depth must be halved to 32,768.
"""

with open("docs/phase1_architecture_final_v4.md", "w") as f:
    f.write(content)

print("v4 spec written successfully.")
