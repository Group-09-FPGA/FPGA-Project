# End-to-End Hardware Limit Order Book (LOB) Accelerator & RV32IM SoC

<div align="center">

[![RTL Verification](https://github.com/Group-09-FPGA/FPGA-Project/actions/workflows/rtl_verification.yml/badge.svg)](https://github.com/Group-09-FPGA/FPGA-Project/actions/workflows/rtl_verification.yml)
[![Software & Market Feed](https://github.com/Group-09-FPGA/FPGA-Project/actions/workflows/software_and_feed.yml/badge.svg)](https://github.com/Group-09-FPGA/FPGA-Project/actions/workflows/software_and_feed.yml)
[![Hardware Synthesis Audit](https://github.com/Group-09-FPGA/FPGA-Project/actions/workflows/hardware_audit.yml/badge.svg)](https://github.com/Group-09-FPGA/FPGA-Project/actions/workflows/hardware_audit.yml)
<br>
[![Target FPGA](https://img.shields.io/badge/FPGA-AMD%20Artix--7%20XC7A100T-red?logo=xilinx&logoColor=white)](https://www.amd.com/en/products/accelerators/fpga-and-adaptive-socs.html)
[![System Architecture](https://img.shields.io/badge/Architecture-Specification-blue)](docs/system_architecture.md)
[![Command Reference](https://img.shields.io/badge/Commands-Cheatsheet-green)](docs/commands.md)
[![HDL](https://img.shields.io/badge/HDL-Pure%20Verilog%202001-informational)](rtl/)
[![Core Frequency](https://img.shields.io/badge/Core%20Clock-100%20MHz%20%7C%2050%20MHz%20Eth-purple)](docs/system_architecture.md#2-clock-domains--clock-domain-crossing-cdc-architecture)

<p align="center">
  <b>A sub-microsecond, pointer-free Limit Order Book hardware accelerator with an integrated RV32IM softcore processor on the Digilent Nexys A7-100T FPGA.</b>
</p>

</div>

---

## 📖 Primary Documentation Links

- **[System Architecture Specification](docs/system_architecture.md)**: Exhaustive architectural reference detailing the physical Ethernet ingestion stack, async CDC FIFO, 4-way associative hash table, slot table, price level RAM, hierarchical occupancy bit-trees, BBO engine, MMIO register maps, and resource utilization.
- **[Master Command Reference & Cheatsheet](docs/commands.md)**: Copy-pasteable bash commands for Vivado environment setup, Python environment (`uv`), full-system simulation, batch synthesis, bitstream generation, JTAG programming, and hardware packet injection.
- **[Interactive Diagrams Application](docs/diagrams/README.md)**: Local interactive web application visualizing the top-level architecture, 3-stage CPU pipeline, multiplier/divider hardware datapaths, and cycle-accurate execution timing traces.

---

## 📽️ System Architecture Highlights

### 1. Full System Overview
Physical RMII 100 Mbps Ethernet ingestion pipeline feeding an asynchronous dual-clock FIFO, high-throughput hardware LOB core, RV32IM supervisor CPU, and real-time diagnostic visualizers:

![Slide 2 - Complete System Architecture](docs/images/slide_2_architecture.png)

### 2. Network Ingestion Pipeline
Hardware parsing from raw Ethernet bits down to 256-bit canonical order events without CPU intervention:

![Slide 3 - Network Ingestion Pipeline](docs/images/slide_3_network_itch.png)

### 3. Cycle-Accurate CPU Execution Trace
3-stage RV32IM pipeline demonstrating EX-to-EX operand forwarding, multi-cycle multiplier/divider execution, and memory load interlocks:

![Slide 6 - Pipeline Execution Trace](docs/images/slide_6_pipeline_timing.png)

---

## ⚡ Core Technical Capabilities

1. **Deterministic Hardware Limit Order Book (LOB)**:
   - **Pointer-Free Design**: Eliminates linked-list overhead using a 2,048-entry Slot Table in BRAM with single-cycle free slot allocation (`lob_free_list.v`).
   - **O(1) Order Lookup**: 1,024-set 8-way set-associative hash table with hardware XOR-folding plus an 8-entry CAM stash for collision overflow.
   - **Dual-Bank Price RAM**: 8,192 price ticks per side (16,384 total levels) with atomic read-modify-write volume updates.
   - **Hierarchical Occupancy Bit-Trees**: 3-level priority encoder tree locating Best Bid and Best Ask in $O(1)$ constant time (2 clock cycles).

2. **Network Ingestion & ITCH Protocol Processing**:
   - **Physical RMII Receiver**: 50.0 MHz MAC RX with parallel IEEE 802.3 CRC-32 verification.
   - **Session & Message Decoders**: Hardware IPv4/UDP filtering (Port 10443), MoldUDP64 sequence tracking, and NASDAQ TotalView-ITCH 5.0 message extraction (`A`, `F`, `E`, `C`, `X`, `D`, `U`).
   - **Division-Free Reciprocal**: Single-cycle price normalization via DSP48 fixed-point reciprocal multiplication: $\text{pidx} = ((\text{price} - \text{base}) \times 274877907) \gg 38$.
   - **Async CDC FIFO**: 256-bit wide dual-clock FIFO with Gray-coded pointer synchronizers bridging the 50 MHz Ethernet and 100 MHz Core domains.

3. **3-Stage RV32IM RISC-V Supervisor Softcore**:
   - Complete integer arithmetic (RV32I) and hardware multiplication/division (RV32M).
   - 4-cycle pipelined signed/unsigned multiplier array and 39-cycle iterative restoring divider.
   - 16 KB Instruction Memory + 16 KB Data Memory connected over a non-blocking crossbar interconnect.

4. **Multi-Channel Diagnostic Outputs**:
   - **640x480 @ 60Hz VGA**: Visualizes top-of-book prices, market depth bars, and real-time trade activity.
   - **UART Serial Console**: 115,200 baud stream reporting real-time order executions and BBO quotes.
   - **Multiplexed 7-Segment Display**: Live display of PC, Bid Price, Ask Price, or active order counts.
   - **Board LEDs**: 16 status LEDs reporting clock lock, PHY link, book validity, and error invariants.

---

## 📂 Repository Directory Layout

```
fpga-lob/
├── constraints/                   # Physical pin and timing constraints
│   ├── nexys_a7_system.xdc        # Master pinout & CDC constraints for Nexys A7-100T
│   └── ...
├── docs/                          # Authoritative project documentation
│   ├── system_architecture.md     # Authoritative specification & microarchitecture
│   ├── commands.md                # Master command reference & cheatsheet
│   ├── FINAL_SYSTEM_IMPLEMENTATION_REPORT.md  # Final implementation & verification audit
│   ├── diagrams/                  # Interactive diagram application (Vite/React) & figures
│   ├── images/                    # Slide figures and visual assets
│   └── archive/                   # Archived phase 1 drafts and legacy scripts
│       └── phase1_drafts/
├── rtl/                           # Synthesizable IEEE 1364-2001 Verilog sources
│   ├── bus/                       # System bus slave wrappers (lob_mmio_slave.v)
│   ├── clocking/                  # Clock manager (clk_rst_mgr.v, MMCM wrappers)
│   ├── common/                    # Asynchronous event FIFO (async_event_fifo.v)
│   ├── cpu/core/                  # 3-stage RV32IM CPU, ALU, M-extension, memories
│   ├── display/                   # 640x480 VGA controller and pixel renderer
│   ├── ethernet/                  # RMII 100Mbps receiver and CRC-32 (rmii_rx.v)
│   ├── itch/                      # NASDAQ ITCH 5.0 decoder (itch_decoder.v)
│   ├── lob/                       # Hardware LOB accelerator (hash, slots, price RAM, BBO)
│   ├── network/                   # IPv4/UDP and MoldUDP64 decoders
│   ├── telemetry/                 # 115200 baud UART transmitter
│   └── top/                       # Top-level SoC wrapper (top_system.v)
├── sim/                           # Simulation testbenches and execution scripts
│   ├── integration/               # Full-system testbenches (tb_system_top.v, run_system_top.sh)
│   ├── unit/                      # Unit-level testbenches (CPU, M-extension, LOB units)
│   └── ...
├── software/                      # Embedded firmware and memory payloads
│   └── baremetal/lob_test/        # Hex initialization payloads (imem.hex, dmem.hex)
├── software_lob/                  # Deterministic Python reference model & test suite
│   ├── src/lob_sim/               # Pure Python LOB simulator and ITCH parser
│   ├── tests/                     # 42 unit, scenario, and invariant tests (pytest)
│   └── pyproject.toml             # uv configuration and dependencies
├── tools/                         # Hardware verification and bringup helpers
│   └── hardware_test_helper.py    # Ethernet UDP injector & UART serial monitor
└── vivado/scripts/                # Non-project batch synthesis and build scripts
    ├── build_system_bitstream.tcl # Full SoC synthesis, P&R, bitstream generator
    ├── synth_lob.tcl              # Out-of-context LOB synthesis & timing closure
    └── program_fpga.tcl           # JTAG FPGA programming script
```

---

## 🎛️ Board Controls: Switches & LED Diagnostics

Target: **Digilent Nexys A7-100T** (`XC7A100T-1CSG324C`)

### Slide Switches (`sw[1:0]`)
Controls the value rendered on the 8-digit multiplexed 7-segment display:

| `sw[1:0]` | Displayed Value | Meaning |
| :---: | :--- | :--- |
| `2'b00` | `cpu_pc[31:0]` | CPU Program Counter |
| `2'b01` | `lob_bid_price[31:0]` | Best Bid Price ($900,000 = $90.0000) |
| `2'b10` | `lob_ask_price[31:0]` | Best Ask Price ($905,000 = $90.5000) |
| `2'b11` | `{4'h0, active_ord, evt_cnt[15:0]}` | Active Orders (high nibbles) & Processed Events (low) |

### Diagnostic LEDs (`led[15:0]`)

| LED Pin | Signal | Hardware Meaning |
| :--- | :--- | :--- |
| `LED[0]` | `mmcm_locked` | Master Clock MMCM locked |
| `LED[1]` | `eth_rstn` | LAN8720A PHY reset deasserted |
| `LED[2]` | `lob_init_done` | LOB internal memory clear complete |
| `LED[3]` | `lob_book_valid` | Order book in consistent, valid state |
| `LED[4]` | `lob_bid_valid` | Active Best Bid present in book |
| `LED[5]` | `lob_ask_valid` | Active Best Ask present in book |
| `LED[6]` | `lob_busy` | Hardware LOB accelerator currently executing an order |
| `LED[7]` | `lob_error_valid` | Fail-stop invariant violation triggered |
| `LED[8]` | `eth_crsdv` | Ethernet carrier sense / receive activity |
| `LED[9]` | `core_evt_valid` | Order event waiting in Async CDC FIFO |
| `LED[10]` | `seq_gap_detected` | MoldUDP64 packet sequence gap detected |
| `LED[11]` | `cnt_crc_err != 0` | Ethernet frame failed IEEE 802.3 CRC-32 check |
| `LED[15:12]`| Status / Error | If error: `lob_error_code[3:0]`. Otherwise: `lob_active_orders[3:0]` |

---

## 🚀 Quickstart Guide

For a comprehensive command cheatsheet, see **[`docs/commands.md`](docs/commands.md)**.

### 1. Run End-to-End RTL Simulation
Executes the full-system integration testbench (`tb_system_top.v`), validating RMII Ethernet, CRC-32, MoldUDP64, ITCH 5.0, Async FIFO, LOB core, MMIO registers, VGA, and UART in XSim:

```bash
# Source Vivado environment
source /tools/Xilinx/2026.1/Vivado/settings64.sh

# Run end-to-end integration test
./sim/integration/run_system_top.sh
```

### 2. Run Software Golden Model Tests
Run the 42 unit, invariant, and differential tests for the Python reference simulator:

```bash
cd software_lob
uv sync --extra dev
uv run pytest
```

### 3. Synthesize & Implement Bitstream
Execute non-project batch synthesis and place-and-route targeting the Nexys A7:

```bash
# Synthesize out-of-context LOB accelerator core
vivado -mode batch -source vivado/scripts/synth_lob.tcl

# Build full system bitstream (outputs build_system/top_system.bit)
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

### 4. Program FPGA & Exercise Hardware
Connect the Nexys A7 via Micro-USB (port `J6`) and Ethernet (port `J2`):

```bash
# Program FPGA bitstream via JTAG
vivado -mode batch -source vivado/scripts/program_fpga.tcl

# In terminal 1: Monitor live UART telemetry (115200 baud)
python3 tools/hardware_test_helper.py --uart

# In terminal 2: Inject test NASDAQ ITCH 5.0 orders over UDP
python3 tools/hardware_test_helper.py --inject --ip 192.168.1.10
```

---

## 📊 FPGA Resource Utilization (Artix-7 XC7A100T)

| Resource | Used | Available | Utilization % |
| :--- | :---: | :---: | :---: |
| **Slice LUTs** | **20,604** | 63,400 | **32.50%** |
| **Slice Registers (FF)** | **35,347** | 126,800 | **27.88%** |
| **Block RAM Tiles (BRAM)** | **41.0** | 135 | **30.37%** |
| **DSP48E1 Slices** | **18** | 240 | **7.50%** |
| **Global Clock Buffers (BUFG)** | **4** | 32 | **12.50%** |
| **Clock Management (MMCM)** | **1** | 6 | **16.67%** |
| **Timing Closure** | **Operating @ 100 MHz Core / 50 MHz Eth / 25 MHz VGA** | | **MET** |

---

## 👥 Team
* **Group:** Group 09 (CS2202L Hardware Lab)
* **Target Board:** Digilent Nexys A7-100T FPGA (AMD Artix-7 `XC7A100T-1CSG324C`)
