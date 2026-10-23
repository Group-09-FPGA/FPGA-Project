# Memory-Mapped I/O (MMIO) Specification

> Historical proposed address map. The RTL implements 4 KiB instruction and
> data memories, 256-byte peripheral windows, and no CPU event injector.
> Use `rtl/cpu/core/sys_bus_interconnect.v` and the slave modules for the
> implemented register map.

## 1. MMIO Architecture & Design Requirements

The Memory-Mapped I/O (MMIO) subsystem allows the RV32IM CPU to monitor and configure the hardware LOB accelerator and its peripheral environment.

### 1.1 Core Requirements Before Address Assignment
1. **Decoupled Accelerator Path**: MMIO accesses from the CPU must never stall or interfere with the fast-path streaming of live network market data. Registers must be dual-ported or shadow-buffered.
2. **Atomic Multi-Word Reads**: Market data quantities and timestamps often span 64 bits. Reading high and low words sequentially risks tearing (reading inconsistent halves across a market tick). MMIO registers holding 64-bit values (such as order ID, total shares, or cycle timers) must implement latch-on-read-low semantics or snapshot registers.
3. **Deterministic Access Latency**: Standard registers (counters, status flags, BBO snapshots) must respond with `sys_ready = 1` in exactly 1 clock cycle to avoid stalling the CPU pipeline. Variable-latency queues (such as execution log FIFOs or synthetic order injection) must support explicit status flags (`fifo_empty`, `fifo_full`) before CPU access.
4. **Natural Power-of-Two Base Alignments**: Each subsystem is assigned a 256-byte or 64 KB block aligned to a natural power-of-two boundary to minimize address decoding logic in Artix-7 LUTs (decoding only top address bits `addr[31:28]` and `addr[15:8]`).

---

## 2. Proposed Address Space Partitioning

The 32-bit physical address map is partitioned as follows:

```
0x0000_0000 ┌────────────────────────────────────────┐
            │   Instruction Memory (BRAM) - 16 KB    │ (Read/Execute)
0x0000_3FFF └────────────────────────────────────────┘
            │               RESERVED                 │
0x2000_0000 ┌────────────────────────────────────────┐
            │      Data Memory (BRAM) - 16 KB        │ (Read/Write Data & Stack)
0x2000_3FFF └────────────────────────────────────────┘
            │               RESERVED                 │
0x4000_0000 ┌────────────────────────────────────────┐
            │   Limit Order Book (LOB) Accelerator   │
            │   - 0x4000_0000: Control & Status      │
            │   - 0x4000_0100: BBO & Level Depth     │
            │   - 0x4000_0200: Synthetic Injector    │
            │   - 0x4000_0300: Execution Match FIFO  │
0x4000_0FFF └────────────────────────────────────────┘
0x5000_0000 ┌────────────────────────────────────────┐
            │   Ethernet & ITCH Feed Handler Stats   │ (Frame, Drop, CRC Counters)
0x5000_00FF └────────────────────────────────────────┘
0x6000_0000 ┌────────────────────────────────────────┐
            │       UART Telemetry Controller        │ (TX/RX FIFOs, Baud Generator)
0x6000_00FF └────────────────────────────────────────┘
0x7000_0000 ┌────────────────────────────────────────┐
            │     System Platform & Board Periphs    │
            │   - 0x7000_0000: 64-bit Cycle Timer    │
            │   - 0x7000_0010: 7-Segment Hex Driver  │
            │   - 0x7000_0020: User LEDs & Switches  │
            │   - 0x7000_0040: VGA Visualizer Config │
0x7000_00FF └────────────────────────────────────────┘
```

---

## 3. Detailed Register Definitions

### 3.1 LOB Accelerator Control & Status (`0x4000_0000 - 0x4000_00FF`)

| Offset | Register Name | Access | Reset | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `LOB_CTRL` | R/W | `0x00000000` | Bit 0: Accelerator Enable; Bit 1: Soft Reset (self-clearing); Bit 2: Clear Book State; Bit 3: Test Mode Enable. |
| `0x04` | `LOB_STATUS` | R | `0x00000000` | Bit 0: Book Initialized; Bit 1: BBO Valid; Bit 2: Event FIFO Full; Bit 3: Event FIFO Empty; Bit 4: Order Table Full. |
| `0x08` | `LOB_EVENT_COUNT` | R | `0x00000000` | Total canonical market events processed since reset. |
| `0x0C` | `LOB_ORDER_COUNT` | R | `0x00000000` | Number of currently active orders in book. |
| `0x10` | `LOB_FILL_COUNT` | R | `0x00000000` | Cumulative total of executed/filled orders. |
| `0x14` | `LOB_CANCEL_COUNT`| R | `0x00000000` | Cumulative total of canceled/deleted orders. |
| `0x18` | `LOB_ERROR_FLAGS` | R/W1C | `0x00000000` | Bit 0: Hash collision table full; Bit 1: Order ID not found; Bit 2: Negative share quantity underflow. |
| `0x1C` | `LOB_LATENCY_MAX` | R/W1C | `0x00000000` | Peak event processing latency (clock cycles). |

### 3.2 LOB Best Bid & Offer (BBO) & Depth (`0x4000_0100 - 0x4000_01FF`)

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `BBO_BID_PRICE` | R | Best Bid Price (integer price ticks). `0x00000000` if book empty. |
| `0x04` | `BBO_BID_QTY` | R | Best Bid aggregated shares at top price. |
| `0x08` | `BBO_ASK_PRICE` | R | Best Ask Price (integer price ticks). `0xFFFFFFFF` if book empty. |
| `0x0C` | `BBO_ASK_QTY` | R | Best Ask aggregated shares at top price. |
| `0x10` | `BBO_SPREAD` | R | Current spread (`Ask Price - Bid Price`). |
| `0x14` | `LOB_DEPTH_L2_BID`| R | Level 2 Bid: `{Price[15:0], Shares[15:0]}`. |
| `0x18` | `LOB_DEPTH_L2_ASK`| R | Level 2 Ask: `{Price[15:0], Shares[15:0]}`. |
| `0x1C` | `LOB_DEPTH_L3_BID`| R | Level 3 Bid: `{Price[15:0], Shares[15:0]}`. |
| `0x20` | `LOB_DEPTH_L3_ASK`| R | Level 3 Ask: `{Price[15:0], Shares[15:0]}`. |

### 3.3 Synthetic Market Event Injector (`0x4000_0200 - 0x4000_02FF`)

Allows the baremetal CPU to inject test orders directly into the event sequencer to verify matching behavior:

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `INJECT_ORDER_ID` | W | Order ID (32 bits). |
| `0x04` | `INJECT_PRICE` | W | Price tick (32 bits). |
| `0x08` | `INJECT_SHARES` | W | Shares quantity (32 bits). |
| `0x0C` | `INJECT_CMD` | W | Bit 0: Valid strobe; Bits 4..1: Event Type (`1=ADD`, `2=EXECUTE`, `3=CANCEL`, `4=DELETE`); Bit 5: Side (`0=Buy, 1=Sell`). Writing this register triggers event dispatch into the LOB arbiter. |
| `0x10` | `INJECT_STATUS` | R | Bit 0: Injector Ready; Bit 1: Injector Busy / Arbiter Full. |

### 3.4 Execution Log FIFO (`0x4000_0300 - 0x4000_03FF`)

Captures trade executions generated by the matching engine:

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `EXEC_FIFO_DATA_0`| R | Match Number / Execution ID (reading pops FIFO if auto-pop enabled). |
| `0x04` | `EXEC_FIFO_DATA_1`| R | Execution Price. |
| `0x08` | `EXEC_FIFO_DATA_2`| R | Executed Shares. |
| `0x0C` | `EXEC_FIFO_STATUS`| R | Bits 11..0: FIFO Entry Count; Bit 16: FIFO Empty; Bit 17: FIFO Full. |

### 3.5 Ethernet & ITCH Statistics (`0x5000_0000 - 0x5000_00FF`)

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `ETH_RX_PACKETS` | R | Total Ethernet frames received. |
| `0x04` | `ETH_CRC_ERRORS` | R | Frames dropped due to CRC32 mismatch. |
| `0x08` | `UDP_RX_PACKETS` | R | Valid UDP market data packets received. |
| `0x0C` | `UDP_PORT_FILTER` | R/W | Destination UDP port filter (Default: 10443). |
| `0x10` | `ITCH_MSG_COUNT` | R | Total ITCH 5.0 messages decoded. |
| `0x14` | `ITCH_LOCATE_ID` | R/W | Active target Stock Locate ID to filter (e.g., 0x0001). |
| `0x18` | `ITCH_DROPPED_MSG`| R | Messages dropped due to non-matching locate ID. |

### 3.6 UART Telemetry Interface (`0x6000_0000 - 0x6000_00FF`)

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `UART_TX_DATA` | W | Write 8-bit character to TX FIFO. |
| `0x04` | `UART_RX_DATA` | R | Read 8-bit character from RX FIFO. |
| `0x08` | `UART_STATUS` | R | Bit 0: TX Ready; Bit 1: TX Full; Bit 2: RX Valid; Bit 3: RX Empty. |
| `0x0C` | `UART_BAUD_DIV` | R/W | Clock divider: `F_clk / Baud` (Default: `100_000_000 / 921_600 = 109`). |

### 3.7 Board Peripherals & Timers (`0x7000_0000 - 0x7000_00FF`)

| Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `TIMER_CYCLES_LO` | R | Lower 32 bits of free-running 100 MHz clock cycle counter. |
| `0x04` | `TIMER_CYCLES_HI` | R | Upper 32 bits of cycle counter (latched when reading LO). |
| `0x10` | `SEVEN_SEG_VAL` | R/W | 32-bit hex value rendered directly onto 8-digit 7-segment display. |
| `0x20` | `BOARD_LEDS` | R/W | Bits 15..0 drive the 16 physical user LEDs. |
| `0x24` | `BOARD_SWITCHES` | R | Bits 15..0 read status of 16 slide switches. |
| `0x40` | `VGA_CTRL` | R/W | Bit 0: Enable visualizer; Bit 1: Color palette select (Dark/Light). |
> This is a proposed MMIO map and contains unimplemented registers. For the active hardware map, see [Current implementation](CURRENT_IMPLEMENTATION.md).

