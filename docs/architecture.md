# System Architecture: RV32IM Hardware Limit Order Book Accelerator

> Historical design document. Some clock, memory, and recovery details below
> were superseded by the RTL. Use the source and a fresh build report for the
> implemented system.

## 1. System Overview

This project implements a complete hardware-software co-design platform on the Digilent Nexys A7-100T FPGA board. The system integrates:
1. An **RV32IM RISC-V softcore processor** (extended and refactored from a proven 3-stage baseline) operating as a management, telemetry, and control unit.
2. A **pipelined Memory-Mapped I/O (MMIO) and System Bus** providing deterministic CPU-peripheral interactions with wait-state support.
3. A **dedicated hardware network receiver and market-data feed handler**, ingesting RMII Ethernet frames, decoding IPv4/UDP packets, and parsing NASDAQ TotalView-ITCH 5.0 messages into a standardized canonical market event stream.
4. A **pure-hardware Limit Order Book (LOB) accelerator core**, implementing deterministic, pointerless, multi-level order tracking, Best Bid and Offer (BBO) maintenance, and price-time priority matching without software intervention.
5. **Real-time output peripherals**, including a video graphics array (VGA) real-time book visualizer and high-speed UART telemetry interface.

```
                    ┌─────────────────────────┐
                    │      RV32IM CPU         │
                    │ (Management & Control)  │
                    └────────────┬────────────┘
                                 │
                            System Bus
                                 │
                    ┌────────────▼────────────┐
                    │     Address Decoder     │
                    │        + MMIO           │
                    └─────┬──────────────┬────┘
                          │              │
                          ▼              ▼
                     Data RAM /      Hardware LOB
                     BRAM Cache      Accelerator
                                         │
 ┌────────────────────────┐              ├────────────────────┐
 │  RMII Ethernet (50MHz) │              │                    │
 └───────────┬────────────┘              ▼                    ▼
             ▼                      VGA Display          UART Telemetry
    Network / ITCH Parser            (640x480 @ 60Hz)    (921600 Baud)
             │
             ▼
      Canonical Events
             │
             ▼
     Event Arbiter / LOB
```

---

## 2. Design Goals

1. **Deterministic Latency**: The hardware LOB accelerator must process canonical order updates in bounded, deterministic clock cycles without variable software loop overhead or pointer chases.
2. **True Hardware-Software Partitioning**: The CPU operates out-of-band relative to the tick-to-trade fast path. Feed processing, order insertion, cancellation, execution, and BBO updates occur 100% in hardware RTL. The CPU manages configuration, monitors statistics, handles exception logging, and issues synthetic test events.
3. **Robust Baseline Reuse**: Leverage the proven 3-stage RV32I pipeline from Lab 5, extending it strictly where required (adding RV32M multi-cycle math, bus wait-states, and memory-mapped decoding) while preserving verified ALU and forwarding mechanics.
4. **Wire-Format Decoupling**: Decouple network packet deserialization (Ethernet, IPv4, UDP, ITCH) from the internal order book structures via a well-defined **Canonical Market Event Bus**.
5. **Static BRAM-Oriented Data Structures**: Eliminate dynamic pointer allocation in hardware. Utilize fixed-depth slot tables, dual-ported Block RAMs, and hierarchical occupancy bitmasks with priority encoders.
6. **Clock-Domain Integrity**: Maintain strict clock domain crossing (CDC) hygiene between the RMII 50 MHz PHY clock, VGA pixel clock, and Core system clock using dual-clock asynchronous FIFOs and level-handshake synchronizers.

---

## 3. Non-Goals

1. **ASIC Line-Rate NASDAQ Receiving**: The Nexys A7 utilizes a 100 Mbps RMII LAN8720A PHY. It is not an enterprise 10G/25G/100G ultra-low-latency SFP+ interface. The architecture serves as a hardware feed-handler and LOB accelerator demonstrator, not an Alveo/Stratix 10G line-rate trading ASIC.
2. **Full TotalView-ITCH Specification Coverage**: Only trading-critical messages (`A`, `F`, `E`, `C`, `X`, `D`, `U`, `R`, `S`) are parsed. Exotic administrative, regulatory halt, and cross-trade messages are filtered or discarded at the parser stage.
3. **Floating Point Operations**: The CPU is RV32IM, not RV32IMF. All price levels and order quantities are represented as fixed-point / integer ticks.
4. **Dynamic Cache Hierarchy**: No complex multi-level L1/L2 cache coherency or virtual memory (MMU/SV32). The CPU executes from tightly coupled Block RAM (Harvard or unified system bus).

---

## 4. FPGA Target Platform

- **Board**: Digilent Nexys A7-100T (rev D)
- **FPGA Part**: Xilinx Artix-7 `XC7A100T-1CSG324C`
- **Logic Capacity**: 63,400 LUT6s, 126,800 Flip-Flops, 135 36Kb Block RAMs (4,860 Kb total), 240 DSP48E1 slices, 6 Clock Management Tiles (MMCM/PLL).
- **On-Board Peripherals Utilized**:
  - Microchip LAN8720A Fast Ethernet PHY (RMII interface, 50 MHz clock reference generated from FPGA or PHY oscillator).
  - 12-bit resistor-ladder VGA output (4 red, 4 green, 4 blue, HSYNC, VSYNC).
  - FTDI USB-UART bridge (supports high baud rates up to 1-3 Mbaud).
  - 8-digit 7-segment multiplexed display.
  - 16 User LEDs and 16 Slide Switches.

---

## 5. Top-Level Block Diagram

```
+-------------------------------------------------------------------------------------------------------------+
|                                        ARTIX-7 XC7A100T TOP-LEVEL                                           |
|                                                                                                             |
|  +--------------------+                                                                                     |
|  |   Clock Gen / MMCM | ---> 100 MHz CORE_CLK, 50 MHz ETH_REF_CLK, 25.175 MHz VGA_CLK                       |
|  +--------------------+                                                                                     |
|                                                                                                             |
|  [ FAST PATH: NETWORK INGESTION ]                                                                           |
|  +--------------------+       +-------------------+       +-------------------+       +------------------+  |
|  | LAN8720A RMII PHY  | ----> | Ethernet MAC /    | ----> |  IPv4/UDP Parser  | ----> | ITCH 5.0 Parser  |  |
|  | (50 MHz Domain)    |       | RX Framing Engine |       | (Hardware Filter) |       | (Wire -> Canon)  |  |
|  +--------------------+       +-------------------+       +-------------------+       +--------+---------+  |
|                                                                                                |            |
|                                                                                        Async FIFO (CDC)     |
|                                                                                                |            |
|  [ CORE DOMAIN: 100 MHz ]                                                                      v            |
|  +------------------------------------------------------------------------------------+  +----------------+ |
|  |                             EVENT SEQUENCER & ARBITER                              |<--| Synthetic MMIO | |
|  +------------------------------------------------------------------------------------+  | Event Injector | |
|                                            |                                              +----------------+ |
|                                            v                                                                 |
|  +-------------------------------------------------------------------------------------------------------+  |
|  |                                  HARDWARE LIMIT ORDER BOOK ACCELERATOR                                |  |
|  |  +-----------------------+   +------------------------+   +--------------------+   +----------------+ |  |
|  |  |  Order-ID Hash Table  |   |    Order Slot Table    |   |  Price Level RAM   |   | Occupancy Map  | |  |
|  |  | (4K-entry cuckoo/hash)|   | (4K order descriptors) |   | (Bids/Asks Levels) |   | (Bitmask Tree) | |  |
|  |  +-----------------------+   +------------------------+   +--------------------+   +----------------+ |  |
|  |                                            |                                                          |  |
|  |                              +-------------v--------------+                                           |  |
|  |                              | BBO Engine & Order Matcher |                                           |  |
|  |                              +-------------+--------------+                                           |  |
|  +--------------------------------------------|----------------------------------------------------------+  |
|                                               |                                                             |
|                   +---------------------------+---------------------------+                                 |
|                   |                                                       |                                 |
|                   v                                                       v                                 |
|  +------------------------------------+               +--------------------------------------------------+  |
|  |         VGA FRAME / BOOK BRAM      |               |              MMIO REGISTERS & STATUS             |  |
|  |  Dual-port rendering buffer        |               |   - BBO Price/Qty    - ITCH Packet Counters      |  |
|  |  Port A: LOB Core (Write)          |               |   - Latency Timer    - Execution Log FIFO        |  |
|  |  Port B: VGA Raster Scan (Read)    |               |   - Config & Reset   - Error Flags               |  |
|  +-----------------+------------------+               +-------------------------+------------------------+  |
|                    |                                                            ^                           |
|                    v                                                            |                           |
|  +------------------------------------+                                         |                           |
|  |         VGA CONTROLLER             |                                         |                           |
|  |  640x480 @ 60Hz (25.175 MHz)       |                                         |                           |
|  +-----------------+------------------+                                         |                           |
|                    |                                                            |                           |
|                    v [R, G, B, HS, VS]                                          |                           |
|                                                                                 v                           |
|  [ SLOW / CONTROL PATH: RV32IM CPU ]                                      System Bus Interconnect           |
|  +------------------------------------------------------------------------------+                           |
|  |  RV32IM Core: 3-Stage Pipeline (IF/ID -> EX -> MEM/WB) + Multi-cycle M-Ext   |                           |
|  |  Instruction Memory: 16 KB BRAM      Data Memory: 16 KB BRAM                |                           |
|  +------------------------------------------------------------------------------+                           |
|                                       |                                                                     |
|                                       v                                                                     |
|  +------------------------------------------------------------------------------+                           |
|  |                  UART Telemetry Engine & Hex Display Driver                  |                           |
|  +------------------------------------------------------------------------------+                           |
+-------------------------------------------------------------------------------------------------------------+
```

---

## 6. Clock Domains

The design contains three primary synchronous clock domains:

| Domain Name | Frequency | Source | Purpose |
| :--- | :--- | :--- | :--- |
| `clk_core` | 100.00 MHz | MMCM Output 1 | CPU, System Bus, LOB Core, Matching Engine, MMIO Peripherals |
| `clk_eth_ref`| 50.00 MHz | MMCM Output 2 | LAN8720A RMII reference clock (and MAC RX/TX logic) |
| `clk_vga` | 25.175 MHz | MMCM Output 3 | VGA pixel clock (640x480 @ 60 Hz standard timing) |

### Clock Domain Crossing (CDC) Rules:
1. **Never synchronize individual bits of multi-bit buses directly.** Multi-bit vectors must traverse domains via:
   - Asynchronous dual-clock FIFOs with Gray-coded read/write pointers (e.g., Ethernet packet stream, LOB event stream).
   - Valid/Ready or Request/Acknowledge level handshakes with double-flop synchronizers on control strobes while data is held stable.
2. **BRAM Dual-Port Crossings**: Dual-port BRAMs operate as native CDC buffers (e.g., VGA rasterizer reads Port B on `clk_vga`, while LOB engine writes Port A on `clk_core`).
3. **Reset Deassertion**: Every domain has a dedicated reset synchronizer ensuring asynchronous assertion and synchronous deassertion.

---

## 7. Reset Domains

1. **Board Power-On Reset (`btnCpuReset` / `reset_n`)**: Active-low asynchronous hardware button input.
2. **Synchronized Core Reset (`rst_core_n`)**: 2-stage synchronized into `clk_core`.
3. **Synchronized Ethernet Reset (`rst_eth_n`)**: 2-stage synchronized into `clk_eth_ref`.
4. **Synchronized VGA Reset (`rst_vga_n`)**: 2-stage synchronized into `clk_vga`.
5. **Software Soft-Reset**: MMIO register in CPU domain capable of pulsing a sub-system reset to the LOB accelerator without resetting the CPU pipeline.

---

## 8. Major Modules

| Module Name | Language | Clock Domain | Description |
| :--- | :--- | :--- | :--- |
| `top_nexys_a7` | SystemVerilog | Multi | Top-level chip wrapper, IO pin buffers, clocking wizard |
| `clk_wiz_lob` | Verilog (MMCME2)| Multi | Artix-7 MMCM generating 100 MHz, 50 MHz, 25.175 MHz |
| `cpu_top` | Verilog | `clk_core` | RV32IM processor top with system bus master |
| `rv32m_unit` | Verilog | `clk_core` | Multi-cycle signed/unsigned multiplier and radix-2 divider |
| `sys_bus_interconnect`| Verilog | `clk_core` | 1-master to N-slave address decoder with wait-state logic |
| `rmii_mac_rx` | Verilog | `clk_eth_ref`| RMII 2-bit dibit deserializer, preamble detection, CRC32 check |
| `ipv4_udp_parser`| Verilog | `clk_eth_ref`| Extracts UDP packets matching configured destination IP/port |
| `itch_parser` | Verilog | `clk_eth_ref`| Parses ITCH 5.0 byte stream, performs endian conversion |
| `cdc_fifo_event`| Verilog | Dual | Asynchronous FIFO passing canonical events into core domain |
| `event_sequencer`| Verilog | `clk_core` | Merges network events and CPU synthetic events with arbitration |
| `lob_core` | SystemVerilog | `clk_core` | Order slot RAM, Price Level RAM, Occupancy mask, BBO tracker |
| `matching_engine`| Verilog | `clk_core` | Executes incoming crosses, decrements quantity, removes fills |
| `lob_mmio_bridge`| Verilog | `clk_core` | Bus slave exposing LOB status, BBO, counters to CPU |
| `vga_core` | Verilog | `clk_vga` | Generates VGA sync timings and fetches BBO visual layout |
| `uart_telemetry` | Verilog | `clk_core` | Transmits ASCII / binary market update messages to host |

---

## 9. Major Interfaces

### 9.1 CPU System Bus (`sys_bus`)
A simple, synchronous master-slave bus with explicit wait-state (`ready`) support:
- `addr[31:0]`: Word-aligned byte address.
- `wdata[31:0]`: 32-bit write payload.
- `rdata[31:0]`: 32-bit read payload.
- `wstrb[3:0]`: Byte write strobe (active high).
- `valid`: Initiates bus request.
- `write`: High for store, low for load.
- `ready`: Slave response signal. When low, stalls CPU pipeline.
- `error`: Bus fault / invalid address indicator.

### 9.2 Canonical Market Event Interface (`canon_event`)
Decoupled internal market event structure:
- `event_valid`: Single-cycle active high strobe.
- `event_type[3:0]`: `EVT_ADD`, `EVT_EXECUTE`, `EVT_CANCEL`, `EVT_DELETE`, `EVT_REPLACE`.
- `order_id[31:0]`: Internal 32-bit order ID (mapped from ITCH 64-bit ID).
- `side`: `0` for Buy (Bid), `1` for Sell (Ask).
- `price[31:0]`: Normalized integer price tick.
- `shares[31:0]`: Integer quantity.
- `locate_id[15:0]`: Stock locate identifier.
- `timestamp[31:0]`: Cycle timestamp counter for latency benchmarking.

---

## 10. Data Flow

```
[ PHY: LAN8720A ]
        | (2-bit RMII @ 50 MHz)
        v
[ rmii_mac_rx ]  -> Strips preamble/SFD, buffers frame, verifies FCS (CRC32)
        | (8-bit AXI-Stream-like byte stream)
        v
[ ipv4_udp_parser ] -> Filters IP protocol 0x11 (UDP), checks port (e.g. 10443)
        | (Payload byte stream)
        v
[ itch_parser ] -> Big-endian unpacker; parses MsgType ('A', 'E', 'X', etc.)
        | (Unpacked raw message)
        v
[ stock_locate_filter ] -> Filters target instrument (locate ID match)
        | (Target ITCH message)
        v
[ cdc_fifo_event ] -> Crosses from 50 MHz Ethernet to 100 MHz Core domain
        | (Canonical Event in Core domain)
        v
[ event_sequencer ] -> Priority arbiter (Network feed prioritized over CPU test injector)
        | (Sequenced canonical event)
        v
[ lob_core ] ->
    1. Order ID Lookup (Locates slot & price level)
    2. Slot Table Update (Writes remaining shares)
    3. Price Level RAM Update (Adjusts aggregated depth)
    4. Occupancy Bitmask Update (Sets/clears price active bits)
    5. BBO Calculation (Priority encoder picks top of book)
        |
        +---> [ VGA Dual-Port BRAM ] -> Displays live book on screen
        +---> [ MMIO Status Regs ]   -> Read by RV32IM CPU
        +---> [ UART Tx FIFO ]       -> Telemetry stream to host PC
```

---

## 11. Control Flow

1. **System Initialization**:
   - MMCM locks; resets synchronously release.
   - CPU bootloader initializes stack pointer, zeros BSS, enables MMIO peripherals.
   - CPU configures Ethernet MAC filter registers, target Stock Locate ID, and enables the LOB accelerator via MMIO.
2. **Steady-State Ingestion**:
   - External PC or packet generator plays PCAP of NASDAQ ITCH feed into Nexys A7 RJ45.
   - Hardware MAC and Parsers process packets autonomously at zero CPU cycle cost.
   - LOB accelerator updates book state in 2 to 4 clock cycles per event.
   - BBO changes trigger BRAM updates for VGA rasterizer and enqueue telemetry packets.
3. **CPU Telemetry & Monitoring Loop**:
   - Baremetal firmware runs an interrupt-free polling loop:
     - Reads LOB total events processed, fill counters, execution latency timers.
     - Formats telemetry strings or monitors error registers.
     - Updates 7-segment display with current Best Bid / Best Ask spread.

---

## 12. Implementation Phases

| Phase | Milestone Name | Key RTL Deliverables | Verification Strategy |
| :--- | :--- | :--- | :--- |
| **0** | Baseline Import & Hygiene | Import Lab 5, isolate into `rtl/cpu`, lint cleanup | `tb_pipeline` regression runs |
| **1** | System Bus Abstraction | `sys_bus_interconnect`, RAM slave, wait-state engine | Vivado sim with multi-cycle wait states |
| **2** | RV32M Extension | `rv32m_unit`, multi-cycle divider/multiplier | Compliance test suite (MUL/DIV) |
| **3** | MMIO Subsystem | MMIO decoder, timer, UART, LED/7-seg slaves | Baremetal C program reading/writing MMIO |
| **4** | Standalone LOB Engine | Order slot RAM, Price RAM, Priority bitmask, BBO | Python golden model comparison |
| **5** | CPU + LOB Co-Design | LOB MMIO bridge, synthetic event injector | CPU injects events via MMIO; verifies BBO |
| **6** | Network Ingestion (RMII) | `rmii_mac_rx`, CRC32 engine, Async FIFO | Packet capture loopback testbench |
| **7** | ITCH 5.0 Feed Handler | IPv4/UDP parser, ITCH parser, canonical bus | PCAP replay testbench |
| **8** | Hardware Video / VGA | 640x480 raster engine, book visualizer | Live monitor display verification |
| **9** | Full-System Closure | Top-level integration, constraints, timing closure | On-board bitstream test with live feed |

---

## 13. Known Risks & Mitigation

1. **Artix-7 Block RAM Timing at 100 MHz**:
   - *Risk*: Chained address-to-data-to-logic paths across BRAMs can fail setup time.
   - *Mitigation*: Ensure all BRAM outputs use registered output ports (`DOA_REG = 1`). Account for 1 or 2 clock cycle read latencies explicitly in state machines.
2. **Order-ID Hash Table Collisions**:
   - *Risk*: NASDAQ order IDs are 64-bit integers. Mapping 64-bit IDs into a bounded FPGA RAM can cause bucket collisions.
   - *Mitigation*: Use a 2-way cuckoo hash table or direct indexed slot table with linear probing. Limit maximum concurrent active orders to 4,096. Trigger MMIO error flag on allocation overflow.
3. **Multi-Cycle Stall Race Conditions**:
   - *Risk*: Simultaneous stalls from bus wait-states and RV32M divide operations could corrupt pipeline registers.
   - *Mitigation*: Centralized hazard unit with strict priority masking; pipeline registers only update when both stages agree on readiness.
4. **RMII 50 MHz Clock Skew**:
   - *Risk*: Nexys A7 LAN8720A PHY requires a strict 50 MHz reference clock with proper phase alignment relative to `eth_rxd`.
   - *Mitigation*: Generate 50 MHz directly from Artix-7 MMCM with dedicated low-jitter clock buffer (BUFG) and set proper input delay constraints in `nexys_a7.xdc`.
