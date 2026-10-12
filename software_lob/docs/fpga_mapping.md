# FPGA Hardware–Software Mapping & Co-Design Specification

This document maps the Python Limit Order Book (LOB) software reference model to the target FPGA architecture, detailing data structure correspondences, hardware pipeline blocks, MMIO register definitions, and RTL verification strategies.

---

## 1. System Architecture Overview

The target hardware system is an FPGA-accelerated electronic market-data processor comprising:
1. **Physical Layer**: 100 Mbps / 1 Gbps Ethernet RMII/MII interface.
2. **Network Processing Clock Domain (`clk_net`, 50/125 MHz)**:
   - Ethernet MAC + IP/UDP parser.
   - MoldUDP64 packet decapsulator & sequence checker.
   - ITCH 5.0 binary field extractor.
3. **Asynchronous Dual-Clock FIFO**:
   - Bridges the network clock domain (`clk_net`) and the core LOB processing clock domain (`clk_lob`).
4. **Order Book Pipeline Clock Domain (`clk_lob`, 100/200 MHz)**:
   - Order Table (CAM / Hash Table in BRAM).
   - Price-Level RAM & BBO Priority Tree.
   - LOB Sequencer State Machine.
   - Top-of-Book MMIO Snapshot Registers.
5. **Host CPU Domain**:
   - RV32IM RISC-V soft processor reading BBO registers via memory-mapped IO.
   - VGA Framebuffer Controller displaying real-time market ladder and stats.

```
       +--------------------------------------------------------------+
       |                  Network Clock Domain (clk_net)              |
       |  [Ethernet RMII] -> [MAC] -> [UDP] -> [MoldUDP64/ITCH Dec.]  |
       +--------------------------------------------------------------+
                                      |
                                      v
                       +-----------------------------+
                       |    Asynchronous FIFO        |
                       +-----------------------------+
                                      |
                                      v
       +--------------------------------------------------------------+
       |                LOB Engine Clock Domain (clk_lob)             |
       |  [LOB Sequencer] <-> [Order RAM / CAM]                       |
       |         |        <-> [Price Level RAM]                       |
       |         v                                                    |
       |  [BBO Priority Logic / Bitmap Hierarchy]                     |
       |         |                                                    |
       |         v                                                    |
       |  [Top-of-Book MMIO Registers]                                |
       +--------------------------------------------------------------+
                     |                                |
                     v                                v
       +----------------------------+   +-----------------------------+
       |   RV32IM RISC-V Soft Core  |   |    VGA Display Controller   |
       +----------------------------+   +-----------------------------+
```

---

## 2. Hardware–Software Concept Mapping

| Python Reference Model | FPGA RTL Hardware Equivalent | Hardware Implementation Details |
| :--- | :--- | :--- |
| **Order Lookup (`dict[uint64, Order]`)** | **Hash Table / Cuckoo Hash in BRAM or CAM** | 64-bit Order ID hashed into a 14-bit index in Block RAM (BRAM). Collision handling via cuckoo hashing or linked bucket pointers. |
| **Per-Order Record (`Order` dataclass)** | **Slot Table / Order Descriptor RAM** | Packed memory record: `{valid[0], side[1], price[31:0], remaining_qty[31:0], next_order_ptr[13:0]}` (64 to 96 bits wide). |
| **Free Storage Allocation** | **Hardware Free-List FIFO / Stack** | Pre-initialized stack of unused BRAM slot indices. Allocate on `Add`, push back on `Delete` / `Fill`. |
| **Price-Level Aggregate (`PriceLevel`)** | **Price-Level Dual-Port BRAM** | Price index mapped to `{total_qty[31:0], order_count[15:0], head_ptr[13:0], tail_ptr[13:0]}`. |
| **Best-Price Search (`max(bids)`, `min(asks)`)** | **Occupancy Bitmap Tree / Priority Encoder** | Multi-level hierarchical bitmask (e.g. 64-bit blocks with priority encoders) enabling 1-to-2 cycle BBO determination. |
| **Sequential Event Application (`step()`)** | **LOB Sequencer FSM** | Multi-stage hardware pipeline: Read Order $\rightarrow$ Read Price Level $\rightarrow$ Compute New Quantities $\rightarrow$ Writeback $\rightarrow$ Update BBO. |
| **Event Stream Queue** | **Asynchronous Dual-Clock FIFO** | Dual-clock Gray-code pointer FIFO bridging network clock domain to LOB clock domain. |
| **TOB Snapshot (`TOBSnapshot`)** | **Top-of-Book MMIO Registers** | Set of 32-bit registers mapped into the RISC-V bus address space (e.g., `0x8000_0000`). |
| **`step()` Audit Record** | **Testbench Expected Output Vector** | Deterministic JSON/hex files replayed in ModelSim / Vivado XSIM / Verilator testbenches. |
| **Python Structural Invariants** | **SystemVerilog Assertions (SVA)** | Assertions checking: `assert (level_qty >= 0)`, `assert (best_bid <= best_ask)` (when active), etc. |

---

## 3. Software Convenience vs. Exact Hardware Behavior

### Software-Only Conveniences:
1. **Dynamic Memory & Python Dictionaries**: Python dynamically resizes dictionaries and lists. FPGA hardware uses fixed-size BRAM allocations (e.g., maximum 8,192 or 16,384 active orders, and 1,024 price levels).
2. **Arbitrary-Precision Numbers**: Python automatically promotes integers. Hardware uses fixed bit-widths (`uint64` for order IDs, `uint32` for prices and quantities).
3. **Strings**: Alphanumeric fields like MPID or symbol strings are formatted in Python for human readability; FPGA logic operates on raw ASCII byte values.

### Must-Match Exact Hardware Behaviors:
1. **Fixed-Point Price Representation**: Exactly 4 implied decimal places stored as unsigned 32-bit integers.
2. **Order Lifecycle Transitions**: Exact quantity decrement arithmetic on partial cancels and executions.
3. **Queue Eviction**: Price levels must be pruned immediately when their order count or total quantity reaches zero.
4. **BBO Resolution**: Best bid is always highest active price; best ask is lowest active price.
5. **No Negative Quantities**: Decrementing quantity past zero must trigger an assertion / error register flag and prevent memory corruption.

---

## 4. Top-of-Book MMIO Register Map (RISC-V Interface)

The hardware exposes the following memory-mapped 32-bit registers to the RV32IM CPU bus:

| Offset | Register Name | Access | Width | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `LOB_STATUS` | R | 32 | Bit 0: Book Valid; Bit 1: Crossed Market; Bit 2: Locked; Bit 3: Bid Empty; Bit 4: Ask Empty; Bits 31..16: Active Order Count. |
| `0x04` | `BEST_BID_PRICE` | R | 32 | Best bid price in 4-decimal fixed-point units (`0` if empty). |
| `0x08` | `BEST_BID_QTY` | R | 32 | Aggregate shares resting at best bid price (`0` if empty). |
| `0x0C` | `BEST_ASK_PRICE` | R | 32 | Best ask price in 4-decimal fixed-point units (`0` if empty). |
| `0x10` | `BEST_ASK_QTY` | R | 32 | Aggregate shares resting at best ask price (`0` if empty). |
| `0x14` | `SPREAD_PRICE` | R | 32 | Spread in price units (`best_ask - best_bid`). |
| `0x18` | `MIDPOINT_PRICE` | R | 32 | Integer midpoint `(best_ask + best_bid) >> 1`. |
| `0x1C` | `TOTAL_TRADE_VOL` | R | 32 | Cumulative executed trade volume. |
| `0x20` | `TRADE_COUNT` | R | 32 | Cumulative trade execution count. |
| `0x24` | `EVENT_SEQ_NUM` | R | 32 | Sequence number of the last processed event. |

---

## 5. Deterministic RTL Test Vector Specification

The Python reference model exports test vectors in structured JSON and Verilog Memory Hex (`.hex`) formats to facilitate simulation in Verilator or Vivado:

### Schema per Event Step:
```json
{
  "step_index": 1,
  "input_event": {
    "type": "ADD_ORDER",
    "order_id": 101,
    "side": "BUY",
    "price": 1000000,
    "quantity": 50
  },
  "expected_state": {
    "status_flags": 1,
    "active_orders": 1,
    "best_bid_price": 1000000,
    "best_bid_qty": 50,
    "best_ask_price": 0,
    "best_ask_qty": 0,
    "spread": 0,
    "midpoint": 0,
    "cumulative_volume": 0,
    "trade_count": 0,
    "book_valid": true,
    "validation_error": null
  }
}
```
This enables bit-level lockstep verification between software simulation and RTL synthesis.
