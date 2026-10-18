# Phase 1.4 Definitive Architecture Specification: RV32IM + Ethernet/ITCH Limit Order Book Accelerator
Version: v5 (Corrective Audit)
Date: 2026-10-09

## 1. Scope and Assumptions

This document dictates the authoritative hardware-software architecture for an FPGA-based Limit Order Book (LOB) accelerator, managed by an RV32IM softcore.

**Assumptions & Exclusions:**
- **Target Device:** Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T).
- **Network Feed:** 100 Mbps RMII Ethernet, MoldUDP64, NASDAQ ITCH 5.0.
- **Price Range Limitation:** 15-bit price index (0 to 32,767 ticks). ITCH messages with prices > 32,767 are filtered and dropped by the hardware parser.
- **Checksum Offload:** IPv4/UDP checksums are ignored to save resources.
- **Replace Atomicity:** ITCH Replace (`U`) is executed as a sequential `Delete` and `Add`. If `Add` fails, the system transitions to `INVALID` (fail-stop).

## 2. Repository Baseline and Evidence Classification

- **Branch:** `main` | **Commit:** `7c2134f84706c82ec88efd0a24b01552755fb966`
- **State:** CPU/System Bus RTL is present and timing-closed at 1Hz in hardware. LOB/Network RTL is entirely unimplemented.

**Evidence Classification:**
- *Verified Fact:* XC7A100T primitive capabilities (135 RAMB36E1s available).
- *Calculated:* 132/135 BRAM inventory breakdown. Execution cycle schedules.
- *Design Decision:* Side-partitioned Price-Level RAM mapping. 15-bit price limit.
- *Requiring Validation:* P&R routing congestion at 97.8% BRAM utilization.

## 3. Architecture and Module Boundaries

```text
[LAN8720A PHY] 
    | 50MHz RMII 
    v
[MAC RX] -> [Single BRAM Dual-Bank Buffer] -> [IPv4/UDP/MoldUDP64/ITCH Parser]
    |                                                      |
    +------------------ clk_eth_ref (50 MHz) --------------+
    |                 CDC Canonical Event FIFO             |
    +------------------ clk_core (100 MHz) ----------------+
    |
    v (128-bit Canonical Event Bus)
[Event Sequencer] <---- [RV32IM CPU MMIO Event Injector]
    |
    v 
[Hardware LOB Core]
  - Free-List FIFO (2 BRAMs)
  - Hash Table & Stash (20 BRAMs)
  - Slot Table (15 BRAMs)
  - Price Level RAM (64 BRAMs)
  - Bid/Ask Occupancy Masks (2 BRAMs)
    |
    +--> [VGA Framebuffer] -> clk_vga (25.175 MHz)
    +--> [MMIO BBO Shadow Regs] -> CPU Sys Bus
```

## 4. Clock Domains, CDC, and Reset

| Domain | Frequency | Scope |
|---|---|---|
| `clk_eth_ref` | 50.00 MHz | RMII PHY, MAC, Packet Buffer, Parsers, CDC FIFO (Write) |
| `clk_core` | 100.00 MHz | CDC FIFO (Read), Event Sequencer, LOB Core, CPU, VGA (Write) |
| `clk_vga` | 25.175 MHz | VGA Framebuffer (Read), Display Sync |

- **RMII Clocks:** The FPGA generates `ETH_REF_CLK` (50 MHz) and drives it to the PHY. MAC RX samples `RXD[1:0]` and `CRS_DV` on the rising edge.
- **CDC Event FIFO:** 512 x 128-bit true asynchronous FIFO with Gray-coded read/write pointers and 2-flop synchronizers.
- **Reset:** Asynchronous assert, synchronous deassert per domain. A reset of `clk_eth_ref` or `clk_core` triggers a global `INVALID` LOB state.

## 5. Ethernet/RMII and Packet Buffers

- **Packet Buffer Storage:** 1x RAMB36E1 configured as 2K x 18 True Dual Port. 
  - `Bank 0`: Addr `0-1023`. `Bank 1`: Addr `1024-2047`.
  - Port A (50MHz Write): MAC RX. Port B (50MHz Read): Parser.
- **Ownership Protocol:** 
  - MAC writes to a `FREE` bank. On valid FCS and legal EOF, ownership transfers to `READY`.
  - Parser reads `READY` bank. On completion, ownership transfers to `FREE`.
  - If MAC requires a bank but both are `READY`, the frame is dropped (`rx_drop_cnt++`).
- **IPv4/UDP:** Drops IP fragments (MF=1 or FragOffset!=0). Validates UDP length against IP length.

## 6. MoldUDP64 and ITCH Parsing

- **MoldUDP64:**
  - Validates 10-byte Session against MMIO config. Session mismatch -> `INVALID`.
  - Tracks `Expected_Seq`.
- **ITCH 5.0:**
  - `A`, `F`: Maps to `Add`.
  - `E`, `C`: Maps to `Exec`. (Note: For `C`, the hardware strictly decrements shares from the resting order's original price. The execution price in the `C` message is ignored for book depth updates).
  - `X`: Maps to `Cancel`. `D`: Maps to `Delete`.
  - `U`: Generates `Delete` event, then `Add` event.

## 7. Canonical Event Format

128-bit bus out of CDC FIFO:
- `[127:125]` **Opcode:** `001`=Add, `010`=Exec, `011`=Cancel, `100`=Delete.
- `[124]` **Side:** `0`=Bid, `1`=Ask.
- `[123:60]` **Order ID:** 64-bit unsigned integer.
- `[59:43]` **Reserved:** 17 bits (Zero).
- `[42:28]` **Price:** 15-bit integer (Max 32,767).
- `[27:0]` **Shares:** 28-bit integer.

## 8. LOB Data Model and Invariants

**Side-Partitioned Address Mapping:**
Price Level RAM (64x RAMB36E1) uses a 16-bit physical address:
- `Addr[15]` = Side (`0` = Bid, `1` = Ask).
- `Addr[14:0]` = 15-bit Price.
This guarantees Bid and Ask quantities are independent, cleanly handling crossed books and eliminating side-ambiguity.

**Occupancy & BBO:**
- Bid Mask (32,768 bits) and Ask Mask (32,768 bits).
- Highest `1` in Bid Mask = Best Bid. Lowest `1` in Ask Mask = Best Ask.

## 9. Hashing, Slot Allocation, and Failure Semantics

- **Slot Table:** 4096 depth. 
- **Free-List FIFO:** 4096 depth (stores indices 0-4095).
- **Hash Table:** 2048 sets x 4 ways. CRC32-C (lower 11 bits). Stash: 16-entry CAM.
- **Fail-Stop Policy:** If Free-List is empty OR Hash is full during an `Add`, hardware sets `BOOK_VALID = 0`, enters `INVALID` state, and halts ingestion. 
- **Duplicate Handling:** On `Add`, if ID matches existing, the popped Slot Index is pushed back to Free-List, and event is ignored.

## 10. Full RAMB36E1 Inventory

| Component | Logical Bits | Legal Primitive Mode | Width/Depth Decomp | BRAMs | Ports |
|---|---|---|---|---|---|
| **Hash Table** | (2048 x 77) x 4 | 2K x 18 (TDP) | 5 wide per way x 4 ways | 20 | A: Read, B: Write |
| **Slot Table** | 4096 x 129 | 4K x 9 (SDP) | 15 wide x 1 deep | 15 | A: Read, B: Write |
| **Price Levels** | 65536 x 32 | 1K x 36 (SDP) | 1 wide x 64 deep | 64 | A: Read, B: Write |
| **Occ. Masks** | 32768 x 1 (x2) | 32K x 1 (SDP) | 1 wide x 1 deep (x2 masks) | 2 | A: Read, B: Write |
| **Free-List** | 4096 x 12 | 4K x 9 (SDP) | 2 wide x 1 deep | 2 | A: Read, B: Write |
| **Event FIFO** | 512 x 128 | 512 x 72 (SDP) | 2 wide x 1 deep | 2 | A: W (50M), B: R (100M)|
| **Pkt Buffer** | 2048 x 16 | 2K x 18 (TDP) | 1 wide x 1 deep | 1 | A: W (50M), B: R (50M) |
| **VGA Frame** | 307200 x 1 | 1Kx32 / 32Kx1 | 10 wide x 1 deep (Asymmetric) | 10 | A: W (32b), B: R (1b) |
| **CPU Mem** | 8192 x 32 (x2) | 1K x 36 (TDP) | 1 wide x 8 deep (x2 mems) | 16 | A: R/W |
| **TOTAL** | | | | **132** | (135 Available) |

## 11. Exact Operation State Machines and Memory Schedules

*Strict Sequential Concurrency: The next event is not popped from the CDC FIFO until the current event reaches DONE.*

**Add Schedule (8 Cycles):**
- `C0`: Read CDC FIFO. Issue CRC32(Order_ID). Pop Free-List.
- `C1`: Hash Addr valid. Free-List SlotIdx valid.
- `C2`: Issue Hash BRAM Read (Port A).
- `C3`: Hash BRAM DO_REG Data valid. Compare 4 ways + Stash. Check Duplicate.
- `C4`: If Dup -> Push SlotIdx to FreeList, DONE. Else -> Write Hash BRAM (Port B). Issue Slot BRAM Write. Issue PriceLevel/Occ Read (Addr={Side, Price}).
- `C5`: PriceLevel and Occ Read Data valid.
- `C6`: Compute `Qty = OldQty + Shrs`. Write PriceLevel (Port B). Write Occ (Port B) with `1`.
- `C7`: Priority Encoder cascades. DONE.

**Execute/Cancel/Delete Schedule (11 Cycles):**
- `C0-C3`: Same Hash lookup. Find hit way. Get SlotIdx. If miss -> DONE.
- `C4`: Issue Slot BRAM Read (Addr=SlotIdx).
- `C5`: Slot BRAM Read Data valid (yields resting Price, Side, OldShrs).
- `C6`: Issue PriceLevel/Occ Read (Addr={Side, RestingPrice}).
- `C7`: PriceLevel/Occ Read Data valid.
- `C8`: Compute `NewQty = OldQty - ExecShrs`. If `NewQty == 0`, `OccBit = 0` else `1`.
- `C9`: Write PriceLevel/Occ (Port B). Write Slot BRAM (Update shares or mark free).
- `C10`: If Slot free -> Delete from Hash. Push SlotIdx to FreeList. DONE.

## 12. BBO and MMIO Interface

- CPU Base `0x4000_0000`.
- CPU writes `1` to `0x0C` (`BBO_LATCH`). On the exact next cycle, hardware latches the output of the BBO priority encoders into stable shadow registers (`0x10`-`0x1C`).
- CPU reads shadows. Zero tearing risk.

## 13. Snapshot Recovery and Sequence Reconciliation

**State Machine:**
1. **Gap Detected:** LOB -> `INVALID`. `BOOK_VALID = 0`.
2. **Clear:** CPU issues MMIO soft-reset. Hardware clears Hash, Occ, and resets Free-List to 0..4095.
3. **Download:** CPU downloads GLIMPSE snapshot, injects synthetic `Add` events via MMIO.
4. **Reconcile:** CPU writes GLIMPSE closing sequence to `Expected_Seq`. Sets state -> `RECOVERING`.
5. **Replay:** Parser inspects live MoldUDP packets:
   - If `Pkt_Seq + MsgCount <= Expected_Seq`: Stale, dropped.
   - If `Pkt_Seq <= Expected_Seq` and `Pkt_Seq + MsgCount > Expected_Seq`: Overlap. Parser skips messages up to `Expected_Seq`, then resumes producing events.
   - Exact boundary match triggers state -> `VALID` and `BOOK_VALID = 1`.

## 14. Error Handling and Fail-Safe Behavior

**Replace Invalidation:** A `Replace` executes as `Delete` then `Add`. If the `Add` fails (Hash Full), the system asserts `ERR_HASH` and transitions to `INVALID`. A partial replace can never be treated as a valid book.

## 15. VGA Framebuffer

10x RAMB36E1 configured as asymmetric TDP (Port A: 1Kx32, Port B: 32Kx1). Total 327,680 bits. Allows CPU to write 32-bit words while the display sync reads 1-bit pixels sequentially without structural hazards.

## 16. Throughput and Buffering Analysis

- **Arrival Bound:** 100 Mbps RMII = max 1.4M canonical ITCH msgs/sec.
- **Service Bound:** Worst-case operation (Delete) = 11 cycles. At 100 MHz, service rate is 9.09M ops/sec.
- **Result:** Hardware service rate is strictly 6.4x faster than maximum wire rate. Backpressure to the MAC only occurs if CPU stalls the Event Sequencer.

## 17. Verification and Acceptance Criteria

- **Unit:** Synthesize Price Level and VGA RAMs to confirm 1Kx36 and Asymmetric inference.
- **Integration:** PCAP replay of MoldUDP64 sequences with injected sequence gaps to prove exact recovery invariant `BOOK_VALID` toggle behavior.

## 18. Implementation Roadmap and Blockers

- **Gate 1:** RMII MAC, CDC FIFO, and ITCH Parser.
- **Gate 2:** LOB Memories & Event Sequencer.
- **Blocker:** Post-synthesis Place & Route (P&R) congestion validation. 132/135 BRAMs (97.8%) must route at 100 MHz before physical hardware viability is confirmed.

## 19. Independent Consistency Audit and Traceability

| ID | Severity | Finding | Affected Section | Resolution | Evidence Level | Required Validation |
|---|---|---|---|---|---|---|
| AUD-01 | P0 | BRAM count impossible for independent Bid/Ask quantities | 8, 10 | Created Side-Partitioned address mapping (15-bit price + 1-bit side). Recalculated total to 132 BRAMs. | Calculated | P&R |
| AUD-02 | P0 | Missing Free-List BRAMs and single Packet Buffer optimization | 5, 10 | Allocated 2 BRAMs for Free-List. Consolidated Packet Buffers into 1 asymmetric TDP BRAM. | Calculated | Synth |
| AUD-03 | P0 | Incomplete Delete/Cancel memory schedule | 11 | Specified 11-cycle state machine capturing Slot reads before Price reads. | Design Decision | XSim |
| AUD-04 | P0 | Replay reconciliation undefined | 13 | Defined exact overlap handling and message skipping logic for MoldUDP parser. | Protocol Logic | PCAP TB |
| AUD-05 | P0 | VGA Framebuffer 1-bit write impossible | 10, 15 | Configured VGA BRAMs as Asymmetric TDP (Port A 32-bit, Port B 1-bit). | Datasheet | Synth |

## 20. Final Readiness Verdict

**CONDITIONALLY READY**

Gate 1 (Network Parsers and CDC FIFO) is fully specified and may proceed to RTL implementation. Gate 2 (LOB Core) must first pass a strict synthesis and P&R routing congestion test to prove the 132-BRAM utilization is physically viable on the XC7A100T.
