# Exhaustive Technical Audit & Architecture Handoff Report
**Historical audit from October 11, 2026.** Its missing-module findings no longer describe the repository. See [the current implementation](CURRENT_IMPLEMENTATION.md).
**FPGA-Based RV32IM Hardware Limit Order Book (LOB) Accelerator**

**Audit Date:** October 11, 2026  
**Auditor:** Principal FPGA Architect, Senior RTL Verification Engineer, RISC-V CPU Architect, Hardware-Software Co-Design Lead  
**Target Hardware:** Digilent Nexys A7-100T (AMD/Xilinx Artix-7 `XC7A100T-1CSG324C`, Speed Grade -1)  
**EDA Environment:** AMD Vivado Design Suite v2026.1 (lin64) Build 6511674, Vivado Simulator (XSim)  
**Repository Root:** `/home/ronit/acad/current/hardware/fpga-lob` (Symlink to `/home/ronit/acad/sem-3/hardware/fpga-lob`)  
**Commit Baseline:** `7c2134f84706c82ec88efd0a24b01552755fb966` (`HEAD -> main`, `origin/main`)  
**Audit Mode:** STRICT READ-ONLY AUDIT  

---

## Evidence Classification Legend

Every technical claim in this document is tagged according to the following strict evidence taxonomy:
- `[VERIFIED]`: Confirmed directly by code inspection, simulation logs, or synthesis/implementation reports in this audit.
- `[REPORTED]`: Documented in repository Markdown files or commit logs, but not independently re-verified or lacking physical proof.
- `[INFERRED]`: Derived through engineering analysis and deduction from source RTL, constraints, or architecture.
- `[PROPOSED]`: Recommended future design or specification, not yet implemented in RTL.
- `[UNKNOWN]`: Information cannot be established from the repository contents or accessible external documentation.

---

# A. Executive Summary

### A.1 Project Objective
The project goal is to build a line-rate market-data feed handler and Limit Order Book (LOB) reconstruction system implemented as a hardware-software co-design on the Digilent Nexys A7-100T FPGA board. The system is designed to ingest 100 Mbps RMII Fast Ethernet frames, parse IPv4/UDP packets, extract MoldUDP64 messages, decode NASDAQ TotalView-ITCH 5.0 binary order updates, feed a pure-hardware LOB pipeline maintaining a deterministic order book and Best Bid/Offer (BBO) state, and expose status/telemetry to an onboard RV32IM RISC-V softcore processor over a memory-mapped system bus, alongside a VGA real-time book visualizer.

### A.2 Actual Completion Status
An exhaustive, file-by-file inspection of the repository reveals a stark dichotomy between the **CPU subsystem** (which is implemented and functional) and the **trading pipeline** (which exists entirely on paper):
- **CPU & System Bus:** **IMPLEMENTED & VERIFIED.** A 3-stage RV32IM RISC-V processor (`rtl/cpu/core/cpu_core.v`) with a custom single-outstanding-transaction bus interconnect (`sys_bus_interconnect.v`), 4 KB instruction memory, 4 KB data memory, and multi-cycle M-extension unit (`rv32m_unit.v`) is fully written, simulated, synthesized, and routed to a bitstream (`build/top_fpga.bit`).
- **Network Pipeline:** **0% IMPLEMENTED.** The directories `rtl/ethernet`, `rtl/network`, `rtl/itch` are 100% empty. There is zero RTL for the RMII receiver, Ethernet MAC, CRC-32 checker, IPv4/UDP parser, MoldUDP64 handler, or ITCH 5.0 decoder.
- **Hardware LOB Accelerator:** **0% IMPLEMENTED.** The directories `rtl/lob` and `rtl/matching` are 100% empty. There is zero RTL for the order slot table, hash table, free list, price-level RAM, occupancy bitmask tree, BBO engine, or event FIFO.
- **Peripherals (VGA, UART, Telemetry):** **0% IMPLEMENTED.** The directories `rtl/display`, `rtl/telemetry`, `rtl/common` are 100% empty. The only implemented peripheral is an 8-digit multiplexed 7-segment display driver (`seven_seg_driver.v`) and an LED register latch in `top_fpga.v`.
- **Software Golden Model:** **0% IMPLEMENTED.** There is no Python, C++, or SystemC reference model in `sim/golden/`, `software/golden/`, or `tools/`.

### A.3 Strongest Verified Achievements
1. **Fully Modularized RV32IM Pipeline (`rtl/cpu/core/`):** Successfully refactored the legacy monolithic Lab 5 CPU (`rtl/cpu/lab5_baseline/`) into modular components (`decoder`, `alu`, `branch_unit`, `reg_file`, `forwarding_unit`, `hazard_unit`, `rv32m_unit`), achieving 100% bit-exact cycle trace match across baseline workloads `addition`, `fibo`, `negative`, `sort`, `xor`. `[VERIFIED: docs/cpu-refactor.md, diff_*.txt]`
2. **Complete RV32M Multiply/Divide Unit (`rtl/cpu/core/rv32m_unit.v`):** Fully implemented 3-stage pipelined multiplier (DSP48E1 cascaded) and 32-cycle restoring divider with complete RISC-V compliance for divide-by-zero and signed overflow corner cases. Verified across 236 directed/random test vectors (`tb_rv32m_unit.v`) and 31 pipeline integration checks (`tb_rv32m_pipeline.v`). `[VERIFIED: sim/unit/core/tb_rv32m_unit.v, sim/unit/core/tb_rv32m_pipeline.v]`
3. **Decoupled System Bus with Wait-State & Skid-Buffer Handling (`rtl/cpu/core/`):** Introduced a synchronous master-slave bus with priority arbitration (WB store > EX load > IF fetch) and a 1-word instruction skid buffer (`if_buf`) that guarantees zero dropped instructions during multi-cycle data memory stalls or divider latency. `[VERIFIED: rtl/cpu/core/cpu_core.v:L352-372, sim/unit/core/output_addition_delay3.log]`
4. **Physical Bitstream Generation (`build/top_fpga.bit`):** Generated a complete routed bitstream for the Nexys A7-100T using non-project batch script `vivado/scripts/build_bitstream.tcl`. The bitstream executes `code_rv32m.s`, displays PC on 7-segment cathodes, and latches store transactions to LEDs, confirming pass sentinel `0xCAFE`. `[VERIFIED: build/top_fpga.bit, build/post_route_timing.rpt]`
5. **Rigorous Architectural Specification (`docs/phase1_architecture_final_v7.md`):** Completed a 489-line independent microarchitectural specification (v7) that rectifies critical flaws in prior drafts (normalizes prices, specifies 256-bit compound Replace, designs 1024x8 hash + 8-entry CAM stash, and schedules cycle-accurate BRAM ports). `[VERIFIED: docs/phase1_architecture_final_v7.md]`

### A.4 Largest Blockers
1. **Physical CPU Clock Frequency & False 100 MHz Illusion (`B5`):** The physical FPGA top-level (`top_fpga.v`) hardwires a clock divider counting 50,000,000 cycles, running the CPU at **1 Hz** (`slow_clk`) for human observation of LEDs. While post-synthesis static timing analysis indicates a theoretical margin of +0.420 ns at 100 MHz, **100 MHz CPU operation has never been routed or hardware-verified**. Running the CPU at 1 Hz cannot service a line-rate network feed. `[VERIFIED: rtl/cpu/core/top_fpga.v:L37-52, build/post_route_timing.rpt:L152-167]`
2. **Total Absence of RTL for Ingestion and LOB Accelerator (`B7`):** Every module from Ethernet PHY ingestion to ITCH decoding and LOB management exists exclusively in documentation. No RTL, testbenches, or synthesis data exist for the primary core of the project. `[VERIFIED: rtl/ethernet/, rtl/network/, rtl/lob/]`
3. **Missing System Bus Decoders and Peripherals (`P0`):** `sys_bus_interconnect.v` only decodes IMEM (`0x0...`) and DMEM (`0x2...` / `0xF...`). Any access to `0x4000_0000` (LOB MMIO) or `0x5000_0000` (Network) returns an immediate 1-cycle bus error (`rsp_error`), asserting CPU exception. The CPU currently has no hardware mechanism to interact with any accelerator. `[VERIFIED: rtl/cpu/core/sys_bus_interconnect.v:L38-40, L84-98]`
4. **Unconstrained Hardware Interfaces in XDC (`B4`):** `constraints/nexys_a7.xdc` only constrains 100 MHz clock `clk`, button `reset`, 16 LEDs, and 8-digit 7-segment display. There are **zero pin assignments or I/O constraints** for RMII Ethernet (`eth_*`), VGA (`vga_*`), or UART (`uart_*`). Furthermore, the physical direction of `ETH_REFCLK` (pin D5) remains unverified against primary board schematics. `[VERIFIED: constraints/nexys_a7.xdc]`
5. **Unsolvable On-Chip Buffer Deficit for Live Snapshot Recovery (`B2/B3`):** The FPGA lacks an Ethernet TX path, ARP, and TCP/IP stack. It cannot request GLIMPSE snapshots autonomously. At 100 Mbps line rate, 1 second of live feed traffic equals 12.5 MB, which exceeds the entire Artix-7 100T Block RAM capacity (607.5 KB) by $20\times$. Live packet buffering during snapshot recovery is physically impossible on-chip; recovery is strictly dependent on an external host replay protocol. `[VERIFIED: docs/phase1_architecture_final_v7.md:L371-377]`

---

# B. Repository Snapshot

### B.1 Git Working-Tree Baseline
- **Active Branch:** `main` `[VERIFIED: git status]`
- **HEAD Commit:** `7c2134f84706c82ec88efd0a24b01552755fb966` `[VERIFIED: git log -n 1]`
- **Commit Message:** `feat(fpga): validate RV32IM CPU on physical Nexys A7-100T hardware` (Author: Ronit Sonawane, Date: Fri Oct 9 17:35:53 2026) `[VERIFIED]`
- **Remote Origin:** `https://github.com/Group-09-FPGA/FPGA-Project.git` `[VERIFIED: git remote -v]`
- **Working Tree State:** Dirty. Modified tracked files exist in simulation directories (`sim/unit/core/Makefile`, `sim/unit/core/tb_cpu_core.v`, `sim/unit/core/mem_generator/Makefile`, simulation binaries, and log files). Untracked files exist in `docs/` (`phase1_architecture_final_v4/v5/v6/v7.md`, diagram generators, and HTML mockups). In accordance with the Strict Read-Only Audit protocol, all working tree states were left completely undisturbed. `[VERIFIED: git status]`

### B.2 Directory Hierarchy Tree
```
/home/ronit/acad/current/hardware/fpga-lob/
├── build/                                # Vivado implementation checkpoints & bitstream
│   ├── top_fpga.bit                      # Generated FPGA bitstream (4,045,560 bytes)
│   ├── post_synth.dcp / post_route.dcp   # Design checkpoints
│   ├── post_route_timing.rpt             # Final post-route STA report
│   ├── post_route_utilization.rpt        # Final post-route resource report
│   └── imem.hex / dmem.hex               # Memory initialization payloads
├── constraints/
│   └── nexys_a7.xdc                      # Physical pin constraints (Clock, Reset, LEDs, 7-Seg)
├── docs/                                 # Architecture specs, audits, and diagrams
│   ├── architecture.md                   # Global system architecture
│   ├── cpu-baseline.md / cpu-refactor.md # Baseline CPU & Phase 2 modularization records
│   ├── cpu.md / system-bus.md / mmio.md  # CPU, Bus, and MMIO documentation
│   ├── rv32m_final_audit.md              # RV32M independent timing & latency audit
│   ├── phase1_architecture_final_v7.md   # Authoritative LOB microarchitectural spec (Oct 10)
│   ├── core_synth_timing.rpt / .util.rpt # Post-synthesis reports for core
│   ├── diagrams/                         # Python matplotlib diagram scripts & rendered figures
│   └── clocking.md, ethernet.md, itch.md # EMPTY (0 bytes) placeholder files
│       lob.md, matching.md, vga.md...
├── rtl/                                  # Verilog source tree
│   ├── cpu/
│   │   ├── core/                         # Refactored RV32IM CPU, bus, memories, top_fpga
│   │   │   ├── alu.v, branch_unit.v, cpu_core.v, decoder.v, forwarding_unit.v
│   │   │   ├── hazard_unit.v, opcode.vh, reg_file.v, rv32m_unit.v
│   │   │   ├── sys_bus_interconnect.v, imem_slave.v, dmem_slave.v, memory.v
│   │   │   ├── seven_seg_driver.v, top_fpga.v
│   │   └── lab5_baseline/                # Immutable Lab 5 baseline CPU reference
│   │       ├── execute.v, IF_ID.v, memory.v, opcode.vh, pipe.v, wb.v...
│   │   ├── bus/, clocking/, common/, display/, ethernet/    # ALL EMPTY DIRECTORIES (0 files)
│   │   ├── itch/, lob/, matching/, network/, telemetry/, top/
├── sim/
│   ├── unit/
│   │   ├── core/                         # Simulation harnesses for core CPU & RV32M
│   │   │   ├── tb_cpu_core.v, tb_top_fpga.v, tb_rv32m_unit.v, tb_rv32m_pipeline.v, tb_bus_error.v
│   │   │   ├── mem_generator/ (code_addition.c, code_rv32m.s, Makefile...)
│   │   │   └── Makefile, filelist.txt, output_*.log, xsim.dir/
│   │   └── lab5_baseline/                # Regression tests for Lab 5 baseline CPU
│   ├── golden/, integration/, vectors/   # ALL EMPTY DIRECTORIES (0 files)
├── software/
│   └── baremetal/, golden/               # ALL EMPTY DIRECTORIES (0 files)
├── tools/                                # EMPTY DIRECTORY (0 files)
└── vivado/
    └── scripts/
        └── build_bitstream.tcl           # Automated non-project batch synthesis/route script
```
*Excluded from listing: temporary Vivado runtime backup files (`vivado_*.backup.log/jou`, `xsim_*.backup.log/jou`).*

---

# C. Implemented Architecture

### C.1 CPU Microarchitecture
The implemented processor in `rtl/cpu/core/cpu_core.v` is a **3-stage pipelined RV32IM softcore processor**.
```
+---------------------------------------------------------------------------------------------------+
|                                          3-STAGE RV32IM PIPELINE                                   |
|                                                                                                   |
|  [ STAGE 1: IF + ID ]                                                                             |
|  +----------------+      +-------------------+      +-----------------+      +-----------------+  |
|  | fetch_pc (Reg) | ---> | sys_bus (imem_rd) | ---> | 1-Word Skid Buf | ---> | decoder.v       |  |
|  +----------------+      +-------------------+      | (if_buf_valid)  |      | - Imm Gen       |  |
|         ^                                           +-----------------+      | - Opcode / Funct|  |
|         | Branch Target                                                      +--------+--------+  |
|         +-------------------------------------------------------------+               |           |
|                                                                       |               v           |
|  ================================== PIPELINE REGISTERS (ID/EX) ==================================  |
|                                                                                                   |
|  [ STAGE 2: EX ]                                                                                  |
|  +--------------------+      +---------------------+      +----------------+      +------------+  |
|  | reg_file.v         | ---> | forwarding_unit.v   | ---> | alu.v          | ---> | branch_unit|  |
|  | (read addr=ex_rs1) |      | (WB -> EX bypass)   |  |   | (ADD, SUB, SLL)|      | (BEQ, BNE, |  |
|  +--------------------+      +---------------------+  |   +----------------+      |  BLT, BGE) |  |
|                                                       |                                   |       |
|                                                       +-> +----------------+              v       |
|                                                       |   | rv32m_unit.v   |        branch_taken  |
|                                                       |   | - 3-stage MUL  |              |       |
|                                                       |   | - 32-cycle DIV |              v       |
|                                                       |   +-------+--------+       +------------+ |
|                                                       |           |                | hazard_unit| |
|                                                       |           v                | (2-cycle   | |
|                                                       +-> ex_mem_address           |  flush)    | |
|                                                           (alu_op1 + imm)          +------------+ |
|                                                                                                   |
|  ================================== PIPELINE REGISTERS (EX/WB) ==================================  |
|                                                                                                   |
|  [ STAGE 3: MEM + WB ]                                                                            |
|  +---------------------------------+      +---------------------------------+                     |
|  | Store Alignment & Byte Strobes  |      | Load Aligner & Sign Extension   |                     |
|  | (SB, SH, SW -> bus_req_wstrb)   |      | (LB, LH, LW, LBU, LHU)          |                     |
|  +----------------+----------------+      +----------------+----------------+                     |
|                   |                                        ^                                      |
|                   v                                        | bus_rdata_reg                        |
|  +---------------------------------------------------------+----------------+                     |
|  |                      Single-Outstanding System Bus Interconnect          |                     |
|  +--------------------------------------------------------------------------+                     |
|                                        |                                                          |
|                                        v Writeback Data                                           |
|                           +--------------------------+                                            |
|                           | reg_file.v (Write Port)  |                                            |
|                           +--------------------------+                                            |
+---------------------------------------------------------------------------------------------------+
```

#### Detailed Pipeline Stage Behavior:
1. **Instruction Fetch & Decode (IF/ID):**
   - `fetch_pc` increments by 4 sequentially (`fetch_pc + 4`) unless a branch/jump is taken (`next_pc`) or a pipeline stall is asserted (`!stall_pipeline`). `[VERIFIED: rtl/cpu/core/cpu_core.v:L58-64]`
   - Instruction memory read request is issued to the system bus.
   - `if_buf` (1-word holding register) captures the bus read data if an instruction arrives while downstream stages are stalled (`stall_pipeline && !if_buf_valid`). `[VERIFIED: rtl/cpu/core/cpu_core.v:L352-367]`
   - `decoder.v` extracts opcode, registers (`rs1, rs2, rd`), `funct3`, `funct7`, and immediate formats combinationally. `[VERIFIED: rtl/cpu/core/decoder.v]`
2. **Execution (EX):**
   - Captured pipeline registers: `ex_pc`, `ex_imm`, `ex_rd`, `ex_rs1`, `ex_rs2`, `ex_alu_op`, `ex_m`, `ex_mem_write`, `ex_mem_to_reg`. `[VERIFIED: cpu_core.v:L114-129]`
   - **Crucial Architectural Detail:** Register file read ports are addressed by `ex_rs1` and `ex_rs2` (the EX stage register addresses), **not ID stage**. `reg_file.v` read data is sampled directly in the EX stage. `[VERIFIED: cpu_core.v:L141-148]`
   - `forwarding_unit.v` compares `ex_rs1`/`ex_rs2` against WB stage destination `wb_rd`. When `wb_reg_write_en` is active, it forwards `wb_result` or `wb_read_data` with zero stall penalty. `[VERIFIED: rtl/cpu/core/forwarding_unit.v]`
   - `alu.v` evaluates single-cycle operations (`ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND`). `[VERIFIED: rtl/cpu/core/alu.v]`
   - `branch_unit.v` evaluates branch conditions (`BEQ, BNE, BLT, BGE, BLTU, BGEU`). Next PC is computed as `ex_pc + ex_imm` (branches, JAL) or `alu_operand1 + ex_imm` (JALR). `[VERIFIED: rtl/cpu/core/branch_unit.v]`
   - When a branch is taken, `hazard_unit.v` asserts a 2-cycle flush (`wb_stall_first_o`, `wb_stall_second_o`), squashing instructions in flight. `[VERIFIED: rtl/cpu/core/hazard_unit.v]`
   - Memory load requests (`ex_mem_to_reg`) launch bus transactions directly from the EX stage (`launch_ex`). `[VERIFIED: cpu_core.v:L375-378]`
3. **Memory & Writeback (MEM/WB):**
   - Pipeline registers: `wb_result`, `wb_mem_address`, `wb_reg_rdata2`, `wb_dest_reg_sel`, `wb_alu_operation`, `wb_mem_write`, `wb_mem_to_reg`. `[VERIFIED: cpu_core.v:L246-264]`
   - Memory store requests (`wb_mem_write`) launch bus transactions from the WB stage (`launch_wb`). `[VERIFIED: cpu_core.v:L374-377]`
   - Store data and byte strobes (`SB, SH, SW`) are generated from `wb_reg_rdata2` and `wb_mem_address[1:0]`. `[VERIFIED: cpu_core.v:L271-301]`
   - Incoming load data is captured into `bus_rdata_reg` and formatted according to `LB, LH, LW, LBU, LHU` with proper sign or zero extension. `[VERIFIED: cpu_core.v:L306-338]`
   - Register file write occurs at the clock edge: `regs[write_addr] <= write_data`. `[VERIFIED: rtl/cpu/core/reg_file.v:L26-28]`

### C.2 M-Extension Execution Unit (`rv32m_unit.v`)
- **Multiplier Datapath:** 3-stage pipelined. Signed/unsigned operands are sign-extended to 33 bits (`ext_a`, `ext_b`).
  - Stage 1: Captures signed 33-bit operands (`mult_reg_a`, `mult_reg_b`).
  - Stage 2: Evaluates 66-bit product `mult_prod_r2 <= mult_reg_a * mult_reg_b` (mapped to 4 cascaded DSP48E1 primitives).
  - Stage 3: Captures lower 32 bits (`MUL`) or upper 32 bits (`MULH, MULHSU, MULHU`) into `result_reg` and transitions to `STATE_DONE`.
  - Latency: 2 clock periods from `start` to `done` (3 clock edges inclusive). `[VERIFIED: rtl/cpu/core/rv32m_unit.v:L173-184]`
- **Divider Datapath:** 32-iteration restoring recurrence.
  - Takes absolute values of operands (`abs_op1`, `abs_op2`).
  - Iterates 31 cycles registered (`div_cnt` 0..30): `{rem_reg, quo_reg[31]} - div_reg`.
  - On 32nd cycle (`div_cnt == 31`), evaluates final quotient bit, applies two's complement sign correction (`final_div_result`), latches `result_reg`, and transitions to `STATE_DONE`.
  - Latency: Exactly 32 clock periods from `start` to `done` (33 clock edges inclusive). Pipeline stalls in EX for 32 cycles. `[VERIFIED: rtl/cpu/core/rv32m_unit.v:L186-196]`
- **Compliance Corner Cases:**
  - `div_zero`: Signed `DIV` returns `-1`, `DIVU` returns `0xFFFFFFFF`, `REM`/`REMU` returns original dividend `orig_op1`. `[VERIFIED: rv32m_unit.v:L97-104]`
  - `overflow` (`0x80000000 / -1`): Signed `DIV` returns `0x80000000`, `REM` returns `0`. `[VERIFIED: rv32m_unit.v:L105-110]`

### C.3 System Bus Architecture & Address Map
The system bus is a synchronous request/response interconnect with single-outstanding-transaction semantics.
- **Request Signals:** `cpu_req_valid`, `cpu_req_write`, `cpu_req_addr[31:0]`, `cpu_req_wdata[31:0]`, `cpu_req_wstrb[3:0]`.
- **Response Signals:** `cpu_rsp_valid` (1-cycle pulse), `cpu_rsp_rdata[31:0]`, `cpu_rsp_error` (1-cycle pulse).
- **Master Arbiter Priority:** Inside `cpu_core.v`, non-preemptive priority:
  $$\text{WB Store} > \text{EX Load} > \text{IF Fetch}$$
- **Actual Address Map (Decoded by `sys_bus_interconnect.v`):**

| Address Range | Selected Slave | Underlying Module | Memory Type | Size in RTL | Size in Docs | Status |
|---|---|---|---|:---:|:---:|---|
| `0x0000_0000 - 0x0FFF_FFFF` | `SEL_IMEM` | `imem_slave` | Block RAM (`instr_mem`) | **4 KB** (1024x32) | 16 KB | **IMPLEMENTED** |
| `0x2000_0000 - 0x2FFF_FFFF` | `SEL_DMEM` | `dmem_slave` | Distributed RAM (`data_mem`) | **4 KB** (1024x32) | 16 KB | **IMPLEMENTED** |
| `0xF000_0000 - 0xFFFF_FFFF` | `SEL_DMEM` | `dmem_slave` | Distributed RAM (`data_mem`) | Alias to DMEM | 64 KB Alias | **IMPLEMENTED** |
| `0x4000_0000 - 0x4FFF_FFFF` | `SEL_ERR` | *None* | *None* | 0 | 4 KB (LOB) | **UNMAPPED (Throws Bus Error)** |
| `0x5000_0000 - 0x5FFF_FFFF` | `SEL_ERR` | *None* | *None* | 0 | 256 B (Net) | **UNMAPPED (Throws Bus Error)** |
| `0x6000_0000 - 0x6FFF_FFFF` | `SEL_ERR` | *None* | *None* | 0 | 256 B (UART) | **UNMAPPED (Throws Bus Error)** |
| `0x7000_0000 - 0x7FFF_FFFF` | `SEL_ERR` | *None* | *None* | 0 | 256 B (Board) | **UNMAPPED (Throws Bus Error)** |
| All other addresses | `SEL_ERR` | *None* | *None* | 0 | - | **Throws Bus Error** |

`[VERIFIED: rtl/cpu/core/sys_bus_interconnect.v:L38-40, L84-98]`

### C.4 Top-Level Board Integration (`top_fpga.v`)
`top_fpga.v` is the active top-level module in synthesis and bitstream generation.
- **Clocking:** Board input `clk` (100 MHz oscillator, pin E3) drives counter `clk_cnt[25:0]`. When `clk_cnt == 49_999_999`, it toggles `slow_clk` (1.0 Hz). The entire CPU, interconnect, IMEM, and DMEM are clocked by `slow_clk`. `[VERIFIED: rtl/cpu/core/top_fpga.v:L40-52]`
- **Board Display:** Current fetch PC `pc_out` connects directly to `seven_seg_driver seg_u`, clocked at 100 MHz `clk` to multiplex 8 hex digits. `[VERIFIED: top_fpga.v:L189-196]`
- **Board LEDs:** `led_reg[15:0]` latches the lower 16 bits of `bus_req_wdata` whenever a bus write to data memory (`bus_req_addr[31:28] == 4'h2`) completes. Displays `0xCAFE` on test program completion. `[VERIFIED: top_fpga.v:L88-96]`

---

# D. Module-by-Module Inventory

| File Path | Module Name | Language | Purpose & Functionality | Status | Evidence & Verification |
|---|---|---|---|---|---|
| `rtl/cpu/core/cpu_core.v` | `cpu_core` | Verilog | 3-stage RV32IM core top; pipeline registers, bus master arbiter, hazard stall logic | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/tb_cpu_core.v, tb_rv32m_pipeline.v]` |
| `rtl/cpu/core/decoder.v` | `decoder` | Verilog | Combinational instruction decode and immediate extraction | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/xsim.log, rtl/cpu/core/decoder.v]` |
| `rtl/cpu/core/alu.v` | `alu` | Verilog | 32-bit arithmetic and logic unit (single cycle) | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/xsim.log, rtl/cpu/core/alu.v]` |
| `rtl/cpu/core/branch_unit.v` | `branch_unit` | Verilog | Signed/unsigned branch condition evaluation | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/xsim.log, rtl/cpu/core/branch_unit.v]` |
| `rtl/cpu/core/reg_file.v` | `reg_file` | Verilog | 31 x 32-bit general purpose register file (x0 hardwired 0) | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/xsim.log, rtl/cpu/core/reg_file.v]` |
| `rtl/cpu/core/forwarding_unit.v` | `forwarding_unit` | Verilog | WB-to-EX operand forwarding bypass multiplexers | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/xsim.log, rtl/cpu/core/forwarding_unit.v]` |
| `rtl/cpu/core/hazard_unit.v` | `hazard_unit` | Verilog | 2-cycle branch flush stall state machine | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/xsim.log, rtl/cpu/core/hazard_unit.v]` |
| `rtl/cpu/core/rv32m_unit.v` | `rv32m_unit` | Verilog | Multi-cycle M-extension: 3-stage MUL, 32-cycle DIV | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/tb_rv32m_unit.v, docs/rv32m_final_audit.md]` |
| `rtl/cpu/core/sys_bus_interconnect.v` | `sys_bus_interconnect` | Verilog | Single-master bus router; decodes IMEM (0x0) & DMEM (0x2, 0xF) | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/tb_bus_error.v]` |
| `rtl/cpu/core/imem_slave.v` | `imem_slave` | Verilog | 1-cycle latency instruction memory bus slave wrapper | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/output_addition.log]` |
| `rtl/cpu/core/dmem_slave.v` | `dmem_slave` | Verilog | Parameterized latency data memory bus slave wrapper | **IMPLEMENTED** | `[VERIFIED: sim/unit/core/output_addition_delay3.log]` |
| `rtl/cpu/core/memory.v` | `instr_mem`, `data_mem` | Verilog | Synchronous 4 KB memories initialized via `$readmemh` | **IMPLEMENTED** | `[VERIFIED: build/imem.hex, build/dmem.hex]` |
| `rtl/cpu/core/seven_seg_driver.v` | `seven_seg_driver` | Verilog | 8-digit multiplexed 7-segment hex display controller | **IMPLEMENTED** | `[VERIFIED: build/post_route_utilization.rpt]` |
| `rtl/cpu/core/top_fpga.v` | `top_fpga` | Verilog | Top-level FPGA wrapper with 1 Hz clock divider & LED latch | **IMPLEMENTED** | `[VERIFIED: build/top_fpga.bit, sim/unit/core/tb_top_fpga.v]` |
| `rtl/cpu/core/opcode.vh` | N/A | Verilog Header | Opcodes, funct3, and field slice definitions | **IMPLEMENTED** | `[VERIFIED: rtl/cpu/core/opcode.vh]` |
| `rtl/cpu/lab5_baseline/*` | Monolithic Baseline | Verilog | Untouched Lab 5 baseline CPU reference (`execute, IF_ID, pipe, wb...`) | **IMPLEMENTED** | `[VERIFIED: sim/unit/lab5_baseline/synth_timing.rpt]` |
| `rtl/ethernet/*` | N/A | Verilog | RMII PHY receiver, preamble/SFD detector, CRC32 FCS engine | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/network/*` | N/A | Verilog | IPv4 header validator, UDP port filter, MoldUDP64 handler | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/itch/*` | N/A | Verilog | TotalView-ITCH 5.0 binary message unpacker | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/lob/*` | N/A | SystemVerilog | Hardware LOB core, slot RAM, hash table, price RAM, occupancy | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/matching/*` | N/A | Verilog | Matching engine cross execution | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/display/*` | N/A | Verilog | VGA timing generator, framebuffer BRAM, book rasterizer | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/telemetry/*` | N/A | Verilog | UART transmitter and telemetry formatter | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/bus/*` | N/A | Verilog | MMIO peripheral bridges | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/clocking/*` | N/A | Verilog | MMCM clock wizard wrapper | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |
| `rtl/top/*` | N/A | Verilog | Full-system integrated top wrapper | **MISSING** | `[VERIFIED: Directory empty (0 files)]` |

---

# E. Verification Evidence

### E.1 Executed Testbench Matrix

| Testbench File | Target Module | Test Scenario | Expected Outcome | Execution Result | Evidence Source |
|---|---|---|---|:---:|---|
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_addition.c` execution | Result 102 at PC 0x2C, halt at 495 ns | **PASS** | `[VERIFIED: sim/unit/core/output_addition.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_fibo.c` execution | Fibonacci series computation, halt at 1605 ns | **PASS** | `[VERIFIED: sim/unit/core/output_fibo.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_negative.c` execution | Signed arithmetic & loads, halt at 495 ns | **PASS** | `[VERIFIED: sim/unit/core/output_negative.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_sort.c` execution | Bubble sort in memory, halt at 3065 ns | **PASS** | `[VERIFIED: sim/unit/core/output_sort.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_xor.c` execution | Bitwise XOR evaluation, halt at 495 ns | **PASS** | `[VERIFIED: sim/unit/core/output_xor.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_addition.c` with `DELAY_CYCLES=1` | Pipeline stalls on memory load/store; halt at 575 ns | **PASS** | `[VERIFIED: sim/unit/core/output_addition_delay1.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_addition.c` with `DELAY_CYCLES=3` | Multi-cycle stall handling; halt at 735 ns | **PASS** | `[VERIFIED: sim/unit/core/output_addition_delay3.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_fibo.c` with `DELAY_CYCLES=3` | Fibonacci under 3-cycle memory wait states; halt at 6915 ns | **PASS** | `[VERIFIED: sim/unit/core/output_fibo_delay3.log]` |
| `sim/unit/core/tb_cpu_core.v` | `cpu_core` | `code_rv32m.s` execution | 15 self-checking assertions covering all 8 M-instructions | **PASS** | `[VERIFIED: sim/unit/core/xsim_113110.backup.log]` |
| `sim/unit/core/tb_bus_error.v` | `sys_bus_interconnect` | Access unmapped address `0x3000_0000` | Interconnect asserts `bus_rsp_error`; CPU asserts `exception` | **PASS** | `[VERIFIED: sim/unit/core/tb_bus_error.v:L125-129]` |
| `sim/unit/core/tb_rv32m_unit.v` | `rv32m_unit` | Standalone MUL/DIV arithmetic, corner cases, 160 random vectors | 236 assertions pass; exact latencies (2 cycles MUL, 32 cycles DIV) | **PASS** | `[VERIFIED: sim/unit/core/tb_rv32m_unit.v, docs/rv32m_final_audit.md]` |
| `sim/unit/core/tb_rv32m_pipeline.v` | `cpu_core` + `rv32m` | RV32M pipeline integration with `DELAY_CYCLES=0` and `=3` | 31 checks pass; skid-buffer holds instruction during 32-cycle stall | **PASS** | `[VERIFIED: sim/unit/core/tb_rv32m_pipeline.v]` |
| `sim/unit/core/tb_top_fpga.v` | `top_fpga` | Board simulation: 15 DMEM stores, reset re-assertion while running | LED clears on reset, stably latches pass sentinel `0xCAFE` | **PASS** | `[VERIFIED: sim/unit/core/xsim.log:L15-35]` |

### E.2 Physical Hardware Synthesis, Implementation, and Timing Evidence
Evidence extracted from `build/post_route_timing.rpt` and `build/post_route_utilization.rpt` generated by Vivado 2026.1:
- **Device:** `xc7a100tcsg324-1` (Artix-7 100T)
- **Target Top:** `top_fpga`
- **Implementation Date:** Fri Oct 9 16:49:38 2026
- **Routing Status:** Fully routed (0 unrouted nets, 0 DRC violations in `build/post_route_drc.rpt`)
- **Clock 1 (`clk`):** 100.000 MHz (10.000 ns period)
  - Driven endpoints: 47 (26-bit divider `clk_cnt`, toggle flip-flop `slow_clk_reg`, 7-segment refresh counter `seg_u/refresh_counter_reg[*]`).
  - Setup Slack (WNS): **+5.515 ns** (MET)
  - Hold Slack (WHS): **+0.228 ns** (MET)
  - Pulse Width (WPWS): **+4.500 ns** (MET)
- **Clock 2 (`slow_clk`):** 1.000 Hz (1,000,000,000.000 ns period, generated clock)
  - Driven endpoints: 8,582 (all CPU core pipeline registers, distributed RAM primitives, interconnect).
  - Setup Slack (WNS): **+1,000,000,000.000 ns** (MET)
  - Hold Slack (WHS): **+0.150 ns** (MET)
- **Timing Exceptions:**
  - `set_false_path -from [get_cells slow_clk_reg] -to [get_cells slow_clk_reg]`: Suppresses the artificial hold violation on the register divider's internal toggle inverter. Verified narrow and correct. `[VERIFIED: docs/rv32m_final_audit.md:L98-129]`
- **Unconstrained Endpoints:** 0 internal pins unconstrained.
- **Physical Bitstream:** Successfully generated at `build/top_fpga.bit` (4,045,560 bytes). `[VERIFIED]`

---

# F. Network Pipeline Status

| Pipeline Stage | Sub-Function | Specification Status | RTL Implementation Status | Verification Status | Deficit & Implementation Detail |
|---|---|---|---|---|---|
| **RMII MAC** | PHY Clocking | Specified in v7 (§6) | **MISSING** | Unverified | Need 50 MHz generated from MMCM; LAN8720A pin D5 clock direction UNV |
| | Dibit Deserializer | Specified in v7 (§7) | **MISSING** | Unverified | Convert 2-bit `rxd[1:0]` @ 50 MHz to 8-bit bytes (4 clocks/byte) |
| | Preamble/SFD Detect | Specified in v7 (§7) | **MISSING** | Unverified | Match alternating `10101010` preamble and `11010101` SFD (0xD5) |
| | CRC-32 (FCS) Engine | Specified in v7 (§7) | **MISSING** | Unverified | Ethernet polynomial `0x04C11DB7`, residue check `0xC704DD7B` |
| | Frame Buffering | Specified in v7 (§8) | **MISSING** | Unverified | Ping-pong 2-bank buffer (2 x RAMB18 SDP, 2K x 9); drops overrun frames |
| **IPv4 / UDP** | EtherType Filter | Specified in v7 (§9) | **MISSING** | Unverified | Filter EtherType == `0x0800` (IPv4); reject 802.1Q VLAN or non-IP |
| | IPv4 Header Validate | Specified in v7 (§9) | **MISSING** | Unverified | Check Version=4, IHL=5, Protocol=17 (UDP), flags (MF=0, offset=0), header checksum |
| | UDP Filter | Specified in v7 (§9) | **MISSING** | Unverified | Filter destination port matching MMIO-configured feed port (e.g. 10443); UDP checksum skipped |
| **MoldUDP64** | Header Extraction | Specified in v7 (§9) | **MISSING** | Unverified | Parse 10-byte Session, 8-byte Sequence Number, 2-byte Message Count |
| | Sequence Tracking | Specified in v7 (§9, §19) | **MISSING** | Unverified | Compare sequence vs expected `NEXT_SEQ`; detect gaps, duplicates, heartbeats (count=0) |
| | Message Slicing | Specified in v7 (§9) | **MISSING** | Unverified | Parse consecutive 2-byte length headers + payload blocks |
| **ITCH 5.0** | Instrument Filter | Specified in v7 (§9) | **MISSING** | Unverified | Filter Stock Locate (offset 1, 16 bits) matching MMIO target instrument |
| | Add Order (`A`, `F`) | Specified in v7 (§10) | **MISSING** | Unverified | Length 36/40 bytes. Extract 64-bit Order ID, Side (B/S), Shares, Price |
| | Executed (`E`, `C`) | Specified in v7 (§10) | **MISSING** | Unverified | Length 31/36 bytes. Extract Order ID, Executed Shares (decrement display qty) |
| | Cancel (`X`) | Specified in v7 (§10) | **MISSING** | Unverified | Length 23 bytes. Extract Order ID, Canceled Shares (decrement display qty) |
| | Delete (`D`) | Specified in v7 (§10) | **MISSING** | Unverified | Length 19 bytes. Extract Order ID (remove entire resting order) |
| | Replace (`U`) | Specified in v7 (§10) | **MISSING** | Unverified | Length 35 bytes. Extract Old Order ID, New Order ID, New Shares, New Price |
| | Unsupported Messages | Specified in v7 (§9) | **MISSING** | Unverified | Administrative (S, R, H, P, Q...): advance Mold sequence, emit NO canonical event |
| **CDC Boundary** | Event Stream Crossing | Specified in v7 (§6) | **MISSING** | Unverified | 256-bit async FIFO crossing from 50 MHz `clk_eth` to 100 MHz `clk_core` |

---

# G. Limit Order Book Architecture Status

### G.1 Data Structure Architecture & Memory Layout (per `docs/phase1_architecture_final_v7.md`)

| Data Structure | Organization & Depth | Logical Entry Width | FPGA Primitive Mapping | Port Schedule & Latency | Implementation Status |
|---|---|---|---|---|---|
| **Order Slot Table** | 2,048 slots | 47 bits: `{valid[1], side[1], pidx[13], shares[32]}` | 3 x RAMB18E1 (2K x 18, SDP) | Port A: Write (C5/C9/C11). Port B: Read (C3/C4). Latency: 1 cycle. | **0% (UNWRITTEN)** |
| **Free-List Allocator** | 2,048 entries | 11 bits: `slot_id[10:0]` | 2 x RAMB18E1 (2K x 9, SDP) | LIFO Stack. Pop: read `stack[sp-1]` (C1). Push: write `stack[sp]` (C9). Latency: 1 cycle. | **0% (UNWRITTEN)** |
| **Order ID Hash Table** | 1,024 sets $\times$ 8 ways | 76 bits per way: `{valid[1], slot[11], key[64]}` | 40 x RAMB18E1 (5 x RAMB18 per way, 1K x 18 SDP) | Read: 8 ways read in parallel (C1). Write: Single way updated (C5/C10/C11). Latency: 1 cycle. | **0% (UNWRITTEN)** |
| **Hash Stash (CAM)** | 8 entries | 77 bits: `{valid[1], slot[11], key[64]}` | Slice Distributed Registers / LUTs | Fully parallel combinational compare in EX/C2 cycle. Zero read latency. | **0% (UNWRITTEN)** |
| **Price-Level RAM** | 16,384 levels (8,192 Bid, 8,192 Ask) | 32 bits: `total_shares[31:0]` | 16 x RAMB36E1 (1K x 36, SDP) = 32 RAMB18 | 16-deep cascaded with registered 16:1 output mux. Read Latency: **3 cycles**. Write: C5/C9/C11. | **0% (UNWRITTEN)** |
| **Occupancy Leaf RAM** | 2 sides $\times$ 256 words $\times$ 32 bits per side | 32 bits (bitmask of 32 price ticks) | 2 x RAMB18E1 (512 x 36 SDP, 1 per side) | Port A: Write (C5/C9/C11). Port B: Read (C1/C5/C6). Latency: 1 cycle. | **0% (UNWRITTEN)** |
| **Occupancy L1 Tree** | 256 bits per side | 1 bit per leaf word | Slice Registers / FFs | Combinational update on leaf word transitions; registered status. Latency: 0 cycles. | **0% (UNWRITTEN)** |
| **Occupancy L0 Tree** | 8 bits per side | 1 bit per 32-word group | Slice Registers / FFs | Evaluated combinationally from L1 bits. Feeds priority encoder. Latency: 0 cycles. | **0% (UNWRITTEN)** |
| **Event Async FIFO** | 512 entries | 256 bits (`canon_event_t`) | 4 x FIFO36E1 (512 x 72) | FWFT mode. Ingests from 50 MHz MAC, drains to 100 MHz LOB core. | **0% (UNWRITTEN)** |

### G.2 Canonical Event Schema (`canon_event_t`)
The canonical event format defined in v7 (§10) is a single-beat **256-bit bus structure**:
$$\text{Data}[255:0] = \{\text{ver}[4], \text{op}[4], \text{side}[1], \text{rsvd}[7], \text{oid}[64], \text{noid}[64], \text{shares}[32], \text{pidx}[13], \text{oow}[1], \text{rsvd}[2], \text{seq}[32], \text{rsvd}[32]\}$$
- `ver[3:0]`: `4'h1`. Version check; mismatches trigger fail-stop.
- `op[3:0]`: `1=ADD`, `2=EXEC`, `3=CANCEL`, `4=DELETE`, `5=REPLACE`.
- `side`: `0=Bid`, `1=Ask` (valid on `ADD`).
- `oid[63:0]`: ITCH 64-bit Order Reference Number.
- `noid[63:0]`: New 64-bit Order Reference Number (used exclusively by `REPLACE`).
- `shares[31:0]`: 32-bit share quantity.
- `pidx[12:0]`: 13-bit normalized price index: $\text{pidx} = (\text{Price} - P_{\text{base}}) / \text{TickSize}$.
- `oow`: Out-of-Window flag (`1` if price is outside the 8,192 level grid).
- `seq[31:0]`: MoldUDP64 sequence number for debugging/telemetry.

### G.3 Operation Execution Schedules (Core Domain @ 100 MHz)
1. **ADD (7 Clock Cycles, 70 ns):**
   - C0: Dequeue event from async FIFO.
   - C1: Format validation. Launch read: Hash set `h(oid)`, Free stack `sp-1`, Price RAM `{side, pidx}`, Occupancy leaf word.
   - C2: Compare 8 hash ways + 8 stash entries. Verify free slot available.
   - C3: Hazard check: abort if `hit` (duplicate ID) or `sp == 0` (book full) or hash bucket + stash full.
   - C4: Price RAM (latency 3) and Leaf RAM valid. Calculate new quantity `q' = q + shares`. Check 32-bit overflow.
   - C5: **COMMIT (Atomic single cycle):** Write Hash way, write Slot table, write Price RAM, update Leaf RAM, decrement `sp`, update L1/L0 bits.
   - C6: Pulse `done`, increment `EVT_ADD` counter, release `op_busy`.
2. **EXECUTE / CANCEL / DELETE (11 Clock Cycles, 110 ns; up to 21 Cycles if Best Level Removed):**
   - C0–C1: Dequeue event. Launch read: Hash set `h(oid)`.
   - C2–C3: Hash compare. If miss: fail-stop (or ignore if approximate mode). Launch read: `slot[slot_id]`.
   - C4: Slot read valid (`rem_shares, side, pidx`). Verify `shares <= rem_shares`. Calculate `rem' = rem - shares`.
   - C5–C7: Launch read: Price RAM `{side, pidx}` and Leaf RAM. Wait for 3-cycle price latency.
   - C8: Price read valid: `q' = q - shares`. Detect level empty (`q' == 0`) and order dead (`rem' == 0`).
   - C9: **COMMIT:** Write updated shares to Slot table (or invalidate). Write updated quantity to Price RAM. If level empty: clear bit in Leaf RAM, update L1/L0. If order dead: clear Hash way, push `slot_id` to free stack (`sp <= sp + 1`).
   - C10: Pulse `done`. If best level was emptied, trigger 10-cycle hierarchical BBO search (C11–C20).
3. **REPLACE (13 Clock Cycles, 130 ns; up to 23 Cycles with BBO Search):**
   - **Crucial Semantic Rule:** ITCH `U` preserves side and slot. It cannot be split into Delete+Add at the parser because ITCH `U` omits the Buy/Sell side indicator.
   - C1–C3: Lookup old Order ID `h(oid)` and verify hit. Lookup new Order ID `h(noid)` and verify absence (no duplicate).
   - C4: Read old slot descriptor to extract resting `side` and `pidx_old`.
   - C5–C8: Launch reads for old price level and new price level.
   - C9: Verify arithmetic.
   - C10: **COMMIT BEAT 1:** Invalidate old hash key, decrement old price level, clear old occupancy bit if empty.
   - C11: **COMMIT BEAT 2:** Insert new hash key `noid`, write new price level, write new shares to existing slot, set new occupancy bit.
   - C12: Pulse `done`. Fast-path BBO update or initiate hierarchical search.

### G.4 Invariants & Correctness Guarantees
- **I1 (Bijection):** Every active order slot maps to exactly one valid entry in the hash table or stash, and vice versa.
- **I2 (Partition):** The set of free slots on the LIFO stack and the set of active order slots strictly partition the 2,048 slot indices ($0..2047$).
- **I3 (Conservation of Shares):** For every price level, `Price_Level_RAM[side][pidx] == sum(Slot_Table[i].shares)` for all active slots `i` at that level.
- **I4 (Occupancy Consistency):** Occupancy bit is set if and only if `Price_Level_RAM[side][pidx] > 0`. L1 bit set if and only if Leaf word $\neq 0$. L0 bit set if and only if L1 group $\neq 0$.
- **I5 (BBO Extremum):** Best Bid equals $\max(\text{occupied bid indices})$; Best Ask equals $\min(\text{occupied ask indices})$.
- **Fail-Stop Policy:** Any protocol error (duplicate ID, missing ID in exact mode, slot exhaustion, quantity underflow/overflow, malformed frame) asserts `book_valid <= 0` **before any memory write occurs**, halts event intake, and latches an error code. `[VERIFIED: docs/phase1_architecture_final_v7.md:L171-192]`

---

# H. CPU, MMIO, VGA, and Recovery

### H.1 CPU Subsystem Implementation State
- **Implemented:** RV32IM core, bus arbiter, decoder, ALU, branch unit, register file, forwarding, hazards, M-extension multiplier/divider, IMEM, DMEM, 7-segment driver.
- **Microarchitectural Gaps in Existing CPU:**
  1. **Missing AUIPC Instruction:** Opcode `7'b0010111` (`AUIPC`) is completely missing from `rtl/cpu/core/opcode.vh` and `decoder.v`. Attempting to execute `AUIPC` triggers `illegal_inst = 1` and halts execution via `exception`. `[VERIFIED: rtl/cpu/core/decoder.v:L53-68, rtl/cpu/core/opcode.vh:L14-21]`
  2. **No Privileged/System Architecture:** CPU lacks `ECALL`, `EBREAK`, `CSR*`, and `MRET`. Exceptions do not trap to a software vector; they merely assert a 1-bit hardware pin `exception`.
  3. **No Dynamic Cache:** Relies strictly on 4 KB tightly coupled on-chip memory.

### H.2 MMIO Subsystem Status
- **Current State:** **STUBBED.** Only memory addresses `0x0...` (IMEM) and `0x2...` / `0xF...` (DMEM) are routed.
- **Proposed MMIO Mapping (v7 §18):**
  - Base address: `0x4000_0000` (`addr[31:12] == 20'h40000`).
  - `0x00`: `CTRL` (`ENABLE`, `CLEAR`, `SNAP_REQ`, `REC_MODE`, `OOW_POLICY`).
  - `0x04`: `STATUS` (`INIT_DONE`, `BOOK_VALID`, `FAIL`, `OP_BUSY`, `SNAP_VALID`, `FAIL_CODE[7:0]`).
  - `0x08`: `BBO_GEN` (Generation counter incremented per snapshot).
  - `0x0C`: `BID_PRICE` (Normalized integer price or raw units).
  - `0x10`: `BID_QTY` (Aggregated shares at Best Bid).
  - `0x14`: `ASK_PRICE` (Normalized integer price).
  - `0x18`: `ASK_QTY` (Aggregated shares at Best Ask).
  - `0x1C`: `BBO_FLAGS` (`bid_valid`, `ask_valid`).
  - `0x20..0x30`: Config registers (`PRICE_BASE`, `TICK`, `LOCATE`, `NEXT_SEQ`).
  - `0x80..0xFF`: Saturating performance & error counters (`ETH_FRAMES, FCS_BAD, SEQ_GAP, EVT_ADD...`).
- **Coherent Snapshot Handshake:** CPU writes `SNAP_REQ` bit in `CTRL`. When the LOB core is idle between events (`op_busy == 0`), hardware copies live BBO registers into MMIO snapshot registers in a single clock cycle, asserts `SNAP_VALID`, and increments `BBO_GEN`. The CPU reads shadow registers without tearing or stalling the LOB. `[PROPOSED: docs/phase1_architecture_final_v7.md:L330-356]`

### H.3 VGA Video Subsystem Status
- **Current State:** **0% IMPLEMENTED.** Directory `rtl/display/` is empty. `docs/vga.md` is 0 bytes. Pin constraints in `nexys_a7.xdc` are missing.
- **Architectural Specification (v7 §21):**
  - Standard 640x480 @ 60 Hz timing driven by 25.175 MHz pixel clock (`clk_vga`).
  - Internal framebuffer: 320x240 at 1 bit/pixel (76,800 bits total), displayed pixel-doubled ($2 \times 2$) to match 640x480 raster timing.
  - Physical mapping: 3 x RAMB36E1 configured as 32K $\times$ 1 true dual-port (TDP) RAMs.
  - Port A (Write): Clocked by 100 MHz `clk_core`. Driven by CPU MMIO or hardware depth renderer.
  - Port B (Read): Clocked by 25.175 MHz `clk_vga`. Directly drives RGB DAC pins via 2-stage pipelined shift register.
  - Resource footprint: 3 Block RAMs (negligible). Can be safely deferred until core LOB verification is complete. `[PROPOSED: docs/phase1_architecture_final_v7.md:L407-415]`

### H.4 Snapshot Recovery & Protocol Status
- **Current State:** **UNRESOLVED ARCHITECTURAL BLOCKER (`B1`, `B2`, `B3`).**
- **Core Invariant:** `NEXT_SEQ` defines the sequence number of the next incoming ITCH message.
- **Operational Rules:**
  - `S == NEXT_SEQ`: Packet accepted; `NEXT_SEQ <= S + C`.
  - `S + C <= NEXT_SEQ`: Duplicate packet; dropped silently.
  - `S < NEXT_SEQ < S + C`: Packet overlaps; skip initial `NEXT_SEQ - S` messages, apply remaining.
  - `S > NEXT_SEQ`: Packet gap detected; `book_valid <= 0`, latch `FAIL_SEQ_GAP`, halt intake, enter recovery.
- **Unresolved Recovery Deficits:**
  1. *B1 (GLIMPSE Closing Boundary):* GLIMPSE snapshot delivery sequence boundary (`GL_CLOSE`) is unverified (whether End-of-Snapshot sequence represents last applied message $L$ or next message $L+1$).
  2. *B2 (No On-Chip Network TX):* The FPGA has no Ethernet TX path or TCP/IP engine. GLIMPSE snapshot download cannot occur in hardware.
  3. *B3 (Unbounded Live Buffer Fallacy):* BRAM capacity cannot hold live traffic during snapshot loading. Recovery must rely on host software injecting synthetic events and orchestrating re-stream. `[REPORTED: docs/phase1_architecture_final_v7.md:L357-391]`

---

# I. Resource and Timing Budget

### I.1 Actual Measured Utilization (Physical Bitstream `build/top_fpga.bit`)
Data extracted from `build/post_route_utilization.rpt`:

| Primitive / Site Type | Used on Physical Chip | Total Available (XC7A100T) | Utilization Percentage | Functional Consumer |
|---|---:|---:|---:|---|
| **Slice LUTs** | **2,763** | 63,400 | **4.36%** | CPU Core logic & distributed RAM |
| - LUT as Logic | 2,251 | 63,400 | 3.55% | ALU, Decoder, Hazards, 7-Seg Mux |
| - LUT as Distributed RAM | 512 | 19,000 | 2.69% | Data Memory (`data_mem`, 512 x RAMS64E) |
| **Slice Registers (FF)** | **1,699** | 126,800 | **1.34%** | CPU pipeline registers, divider FFs |
| **Block RAM (RAMB36E1)** | **1** | 135 | **0.74%** | Instruction Memory (`instr_mem`) |
| **Block RAM (RAMB18E1)** | **0** | 270 | **0.00%** | Unused |
| **DSP48E1 Slices** | **4** | 240 | **1.67%** | RV32M multiplier (`mult_prod_r2`) |
| **Clock Buffers (BUFGCTRL)** | **2** | 32 | **6.25%** | Board `clk` (100 MHz) & `slow_clk` (1 Hz) |
| **Bonded IOB Pads** | **34** | 210 | **16.19%** | Clock, Reset, 16 LEDs, 8 Anodes, 8 Cathodes |
| **MMCM / PLL Blocks** | **0** | 6 | **0.00%** | None (Divider implemented in fabric) |

`[VERIFIED: build/post_route_utilization.rpt:L30-165]`

### I.2 Comprehensive Memory Primitive Mapping Budget (Proposed Full System)
Analytical inventory based on legal Xilinx 7-Series UG473 primitive configurations for the complete proposed system:

| Subsystem Memory Block | Logical Dimensions | Total Bits | Clock Domain | Read Latency | Xilinx Primitive Mapping | RAMB18 Equivalent | RAMB36 Equivalent |
|---|---|---:|---|:---:|---|---:|---:|
| **Order ID Hash Table** | 1024 sets $\times$ 8 ways $\times$ 76 b | 622,592 | `clk_core` | 1 | 40 x RAMB18E1 (1K x 18, SDP) | 40.0 | 20.0 |
| **Order Slot Table** | 2048 entries $\times$ 47 b | 96,256 | `clk_core` | 1 | 3 x RAMB18E1 (2K x 18, SDP) | 3.0 | 1.5 |
| **Free Slot Stack** | 2048 entries $\times$ 11 b | 22,528 | `clk_core` | 1 | 2 x RAMB18E1 (2K x 9, SDP) | 2.0 | 1.0 |
| **Price-Level RAM** | 16,384 levels $\times$ 32 b | 524,288 | `clk_core` | 3 | 16 x RAMB36E1 (1K x 36, SDP) | 32.0 | 16.0 |
| **Occupancy Leaf RAM** | 2 sides $\times$ 256 words $\times$ 32 b | 16,384 | `clk_core` | 1 | 2 x RAMB18E1 (512 x 36, SDP) | 2.0 | 1.0 |
| **Canonical Event FIFO** | 512 entries $\times$ 256 b | 131,072 | Dual (Async) | FWFT | 4 x FIFO36E1 (512 x 72) | 8.0 | 4.0 |
| **Ethernet Packet Buffers** | 2 banks $\times$ 2048 bytes | 32,768 | `clk_eth` | 1 | 2 x RAMB18E1 (2K x 9, SDP) | 2.0 | 1.0 |
| **VGA Framebuffer** | 320 $\times$ 240 $\times$ 1 b | 76,800 | Dual (TDP) | 2 | 3 x RAMB36E1 (32K x 1, TDP) | 6.0 | 3.0 |
| **CPU Instruction Memory** | 4096 words $\times$ 32 b (16 KB) | 131,072 | `clk_core` | 1 | 4 x RAMB36E1 (1K x 36, SDP) | 8.0 | 4.0 |
| **CPU Data Memory** | 4096 words $\times$ 32 b (16 KB) | 131,072 | `clk_core` | 1 | 4 x RAMB36E1 (1K x 36, Byte-WE) | 8.0 | 4.0 |
| **TOTAL PROJECTED BRAM** | — | **1,785,032** | — | — | — | **111.0** | **55.5** |

- **BRAM Feasibility Conclusion:** The complete system requires **55.5 RAMB36-equivalent tiles out of 135 available** on the Artix-7 100T (**41.1% total Block RAM utilization**). This leaves 79.5 BRAM tiles (58.9%) free for routing relief, FIFO buffering, and fabric optimization, completely eliminating the 97.8% congestion crisis identified in v5. `[INFERRED & VERIFIED: docs/phase1_architecture_final_v7.md:L237-261]`

### I.3 Projected Full-System Slice Logic & Clocking Budget

| Resource Category | Existing Core Usage | Estimated LOB Accelerator | Estimated Network / Parsers | Estimated Peripherals (VGA/UART) | Total Projected System | Available on Chip | Margin / Headroom |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Slice LUTs** | 2,763 | 4,500 | 2,200 | 1,100 | **10,563** | 63,400 | **83.3% Headroom** |
| **Slice Registers** | 1,699 | 3,800 | 2,400 | 950 | **8,849** | 126,800 | **93.0% Headroom** |
| **DSP48E1** | 4 | 0 | 0 | 0 | **4** | 240 | **98.3% Headroom** |
| **MMCM / PLL** | 0 | 0 | 1 (Clock Wizard) | 0 | **1** | 6 | **5 Tiles Free** |
| **BUFG** | 2 | 0 | 2 | 1 | **5** | 32 | **27 Free** |

`[INFERRED: Based on Artix-7 cell estimations and v7 architecture]`

---

# J. Architecture Contradictions and Blockers

### J.1 Prioritized Critical Blockers (P0)

1. **BLOCKER 1: Hardwired 1 Hz CPU Clock vs 100 MHz System Requirement (`B5`)**
   - *Evidence:* `rtl/cpu/core/top_fpga.v:L40-52` implements a 26-bit divider toggling `slow_clk` every 50,000,000 cycles. `constraints/nexys_a7.xdc:L7` defines `slow_clk` with period 1,000,000,000 ns.
   - *Impact:* The CPU runs at 1 Hz on physical hardware. It cannot service line-rate market data, run interactive UART telemetry, or manage book recovery. While post-synthesis STA shows +0.420 ns slack at 100 MHz, this has never been placed, routed, or closed on hardware.
   - *Resolution:* Replace the fabric clock divider with an MMCM generating a true 100 MHz `clk_core`. Introduce a clock-enable pulse for low-frequency board observation, or run the CPU at full 100 MHz.
2. **BLOCKER 2: Bus Interconnect Has No Slave for LOB or Network Accelerators (`P0-BUS`)**
   - *Evidence:* `rtl/cpu/core/sys_bus_interconnect.v:L38-40` contains only:
     ```verilog
     wire sel_imem = (cpu_req_addr[31:28] == 4'h0);
     wire sel_dmem = (cpu_req_addr[31:28] == 4'h2) || (cpu_req_addr[31:28] == 4'hF);
     ```
     Lines 84–98 generate an immediate 1-cycle bus error (`rsp_error`) for all other addresses.
   - *Impact:* CPU transactions to `0x4000_0000` (LOB) or `0x5000_0000` (Network) trigger bus faults. No accelerator can be accessed by software until the interconnect is modified.
   - *Resolution:* Add `sel_lob = (cpu_req_addr[31:12] == 20'h40000)` and instantiate a dedicated slave response port.
3. **BLOCKER 3: XDC File Omits All Ethernet, VGA, and UART Pins (`B4-XDC`)**
   - *Evidence:* `constraints/nexys_a7.xdc` contains only 64 lines defining pins for `clk`, `reset`, `led[0..15]`, `seg[0..6]`, `an[0..7]`, and `dp`.
   - *Impact:* Even if Ethernet or VGA RTL were written today, Vivado cannot implement or map the design to physical board pins.
   - *Resolution:* Import Digilent master XDC pin definitions for LAN8720A RMII (`ETH_MDC`, `ETH_MDIO`, `ETH_CRS_DV`, `ETH_RXD[0..1]`, `ETH_TXD[0..1]`, `ETH_TX_EN`, `ETH_REFCLK`, `ETH_RSTN`), VGA (`VGA_R[3:0]`, `VGA_G[3:0]`, `VGA_B[3:0]`, `VGA_HS`, `VGA_VS`), and FTDI USB-UART (`UART_TXD`, `UART_RXD`).
4. **BLOCKER 4: CPU Decoder Omits AUIPC Instruction (`ISA-BUG`)**
   - *Evidence:* `rtl/cpu/core/decoder.v:L53-68` does not decode opcode `7'b0010111` (`AUIPC`). `rtl/cpu/core/opcode.vh` lacks an `AUIPC` definition.
   - *Impact:* Standard GCC baremetal binaries (e.g. position-independent code, function pointer calls, global data offsets) emit `auipc`. Executing `auipc` asserts `illegal_inst` and halts the CPU with an unhandled exception.
   - *Resolution:* Add `AUIPC = 7'b0010111` to `opcode.vh`, decode it in `decoder.v`, and route `ex_result = ex_pc + ex_imm` in `cpu_core.v`.
5. **BLOCKER 5: Unsynchronized Clock Domain Crossing to 7-Segment Driver (`CDC-BUG`)**
   - *Evidence:* In `rtl/cpu/core/top_fpga.v:L189-196`, `pc_out` originates from the 1 Hz `slow_clk` domain and connects directly to `seven_seg_driver seg_u`, which is clocked by 100 MHz `clk`.
   - *Impact:* Multi-bit bus crossing across unrelated clock domains without synchronizer flip-flops or handshake. While visually unnoticeable at 1 Hz, this CDC hazard will cause metastability and display corruption as soon as the CPU clock frequency is altered.
   - *Resolution:* Implement a 2-stage synchronizer or register latch strobe.

### J.2 Major Documentation vs RTL Contradictions

| Topic | Architecture Document Claim | Actual Code in Repository | Architectural Reality & Resolution |
|---|---|---|---|
| **CPU Memories** | "Instruction Memory: 16 KB BRAM, Data Memory: 16 KB BRAM" (`docs/architecture.md:L135`) | 4 KB IMEM (`imem[0:1023]`), 4 KB DMEM (`dmem[0:1023]`) in `rtl/cpu/core/memory.v:L10, L49` | RTL implements 4 KB. Expand parameters `IMEMSIZE` and `DMEMSIZE` to 16 KB when scaling firmware. |
| **LOB MMIO Map** | `docs/mmio.md:L67-80` puts BBO at `0x4000_0100` and Synthetic Injector at `0x4000_0200` | `docs/phase1_architecture_final_v7.md:L336-350` puts BBO at `0x4000_000C` and Status at `0x04` | **Conflict.** v7 supersedes `mmio.md`. Adopt v7 compact offset mapping (`0x00..0x30`). |
| **Replace Semantics** | `docs/architecture.md:L49` claims sequential Delete+Add | `docs/phase1_architecture_final_v7.md:L134-137` proves Delete+Add is impossible because ITCH `U` omits Side | **v7 is correct.** Replace must be a 2-beat atomic compound operation maintaining resting side. |
| **Occupancy Bitmask** | v5 claimed 32K-bit bitmask in BRAM evaluated in 1 cycle | `docs/phase1_architecture_final_v7.md:L218-236` shows BRAM outputs 1 bit/cycle; requires 3-level tree | **v7 is correct.** Monolithic BRAM priority encoder is physically impossible; 3-level tree required. |
| **BRAM Utilization** | v5 claimed 132/135 BRAM36 (97.8% chip congestion) | v7 (§15) re-derives legal mapping: 111 RAMB18 = 55.5 RAMB36 (41.1% chip usage) | **v7 is correct.** 16 BRAMs for price levels provides 16,384 levels while maintaining 58.9% chip routing headroom. |
| **Active Peripherals** | `docs/architecture.md:L10` describes live VGA and 921600 Baud UART telemetry | `rtl/display/` and `rtl/telemetry/` are 100% empty | **Unimplemented.** Peripherals exist strictly as design proposals. |

---

# K. Completion Roadmap

To ensure maximum safety and avoid breaking existing verified CPU functionality, implementation must proceed in strictly gated, testable phases.

```
                      ┌──────────────────────────────────────────┐
                      │ PHASE 1: CPU Hygiene & Bus Extensibility │
                      │ - Fix AUIPC & CDC hazards                │
                      │ - Add LOB MMIO slot (0x4000_0000)        │
                      └────────────────────┬─────────────────────┘
                                           │
                                           ▼
                      ┌──────────────────────────────────────────┐
                      │ PHASE 2: Software Golden Reference Model │
                      │ - Python event generator & LOB simulator │
                      │ - Differential test vectors (1M+ events) │
                      └────────────────────┬─────────────────────┘
                                           │
                                           ▼
                      ┌──────────────────────────────────────────┐
                      │ PHASE 3: Hardware LOB Core Construction  │
                      │ - Order Slot RAM & Free-List Stack       │
                      │ - 1024x8 Hash Table & 8-Entry CAM Stash  │
                      │ - 16K Price RAM & 3-Level Occupancy Tree │
                      │ - Verify against Golden Model in XSim    │
                      └────────────────────┬─────────────────────┘
                                           │
                                           ▼
                      ┌──────────────────────────────────────────┐
                      │ PHASE 4: CPU-LOB Co-Design & MMIO Bridge │
                      │ - Connect LOB to sys_bus_interconnect    │
                      │ - Synthetic event injection via MMIO     │
                      │ - Coherent BBO shadow reading in C       │
                      │ [SMALLEST COMPLETE VERTICAL SLICE]       │
                      └────────────────────┬─────────────────────┘
                                           │
                                           ▼
                      ┌──────────────────────────────────────────┐
                      │ PHASE 5: Network Ingestion Pipeline      │
                      │ - MMCM clocking (100 MHz, 50 MHz, 25 MHz)│
                      │ - RMII MAC RX, CRC32, packet buffers     │
                      │ - IPv4, UDP, MoldUDP64, ITCH 5.0 parsers │
                      │ - Async Event FIFO crossing              │
                      └────────────────────┬─────────────────────┘
                                           │
                                           ▼
                      ┌──────────────────────────────────────────┐
                      │ PHASE 6: Recovery, VGA & System Closure  │
                      │ - Mold sequence gap & recovery protocol  │
                      │ - VGA 320x240 dual-port framebuffer      │
                      │ - Timing closure (WNS>=0 @ 100/50/25 MHz)│
                      │ - Physical hardware deployment on Nexys  │
                      └──────────────────────────────────────────┘
```

### Phase 1: CPU Hygiene, ISA Fixes & System Bus Expansion
- **Objective:** Fix known CPU bugs, eliminate CDC hazards, and expand system bus decoding to support MMIO peripherals without altering verified execution.
- **RTL Modifications:**
  - `rtl/cpu/core/decoder.v` & `opcode.vh`: Implement `AUIPC` instruction.
  - `rtl/cpu/core/sys_bus_interconnect.v`: Add address decode slot for LOB MMIO (`0x4000_0000 - 0x4000_0FFF`). Return 0 for read, accept write without bus error.
  - `rtl/cpu/core/top_fpga.v`: Add 2-stage synchronizer between `pc_out` and `seven_seg_driver seg_u`.
- **Verification Acceptance Criteria:** All 5 baseline tests + `tb_rv32m_unit` + `tb_rv32m_pipeline` re-run and pass with 0 errors.

### Phase 2: Software Golden Reference Model & Testbench Vector Generation
- **Objective:** Construct a bit-exact software simulator for NASDAQ ITCH 5.0, MoldUDP64, and the LOB accelerator to act as a verification oracle.
- **Deliverables:**
  - `tools/golden_lob.py`: Python object-oriented order book modeling order slots, 1024x8 hash table, 8-entry CAM stash, 16,384 price levels, 3-level occupancy bitmask, and exact cycle-accurate BBO tracking.
  - `tools/generate_vectors.py`: Script generating 1,000,000 synthetic canonical events covering random adds, cancels, replaces, executions, and adversarial hash collision vectors.
- **Acceptance Criteria:** Reference model passes all ITCH test vectors and verifies all invariants I1–I5.

### Phase 3: Hardware Limit Order Book (LOB) Core Construction
- **Objective:** Implement the pure-hardware LOB core in RTL driven by canonical 256-bit events.
- **Modules to Create:**
  - `rtl/lob/lob_slot_table.v`: 2,048 x 47-bit SDP RAM.
  - `rtl/lob/lob_free_stack.v`: 2,048 x 11-bit LIFO stack.
  - `rtl/lob/lob_hash_table.v`: 1,024 sets x 8 ways (40 RAMB18E1 primitives) + 8-entry CAM stash.
  - `rtl/lob/lob_price_ram.v`: 16,384 x 32-bit SDP RAM (16 RAMB36E1 primitives with registered 16:1 mux, 3-cycle latency).
  - `rtl/lob/lob_occupancy_tree.v`: 3-level bitmask tree (Leaf RAM, L1 FFs, L0 FFs) with priority encoder.
  - `rtl/lob/lob_core.v`: Top-level FSM implementing cycle schedules from v7 §16 (Add: 7 cycles, Execute/Cancel/Delete: 11 cycles, Replace: 13 cycles).
- **Verification Acceptance Criteria:** Co-simulation of `lob_core.v` against `golden_lob.py` over 100,000 randomized events with zero discrepancies in BBO or slot states.

### Phase 4: CPU–LOB Co-Design & MMIO Integration (Smallest Vertical Slice)
- **Objective:** Establish the first integrated hardware-software demonstrator.
- **Modules to Create:**
  - `rtl/bus/lob_mmio_bridge.v`: Connects `lob_core` to `sys_bus_interconnect` at `0x4000_0000`. Exposes Control, Status, BBO shadow registers, and a Synthetic Event Injector.
  - `software/baremetal/test_lob_mmio.c`: RISC-V C program that injects test orders via MMIO, verifies BBO results, and displays current spread on 7-segment display.
- **Acceptance Criteria:** Physical execution on Nexys A7-100T FPGA board demonstrating CPU-injected orders successfully updating hardware BBO registers.

### Phase 5: Network Ingestion Pipeline (RMII, IPv4/UDP, MoldUDP64, ITCH 5.0)
- **Objective:** Build the autonomous network receiver processing wire-speed Ethernet packets into canonical events.
- **Modules to Create:**
  - `rtl/clocking/clk_wiz_lob.v`: MMCM generating 100 MHz (`clk_core`), 50 MHz with phase shift (`clk_eth`), and 25.175 MHz (`clk_vga`).
  - `rtl/ethernet/rmii_mac_rx.v`: 2-bit dibit deserializer, preamble detector, CRC-32 checker.
  - `rtl/ethernet/pkt_buf.v`: Ping-pong 2-bank packet buffer.
  - `rtl/network/ipv4_udp_parser.v`: Protocol filter and destination IP/port validator.
  - `rtl/network/mold_parser.v`: MoldUDP64 sequence checker and message slicer.
  - `rtl/itch/itch_parser.v`: TotalView-ITCH 5.0 binary unpacker and price index normalizer.
  - `rtl/common/cdc_fifo_event.v`: 256-bit asynchronous FIFO passing canonical events into the 100 MHz LOB core.
- **Acceptance Criteria:** Testbench replay of recorded NASDAQ ITCH PCAP file successfully parses 100% of messages into canonical events with zero CRC errors or drops.

### Phase 6: Snapshot Recovery, VGA Display, and Full-System Timing Closure
- **Objective:** Complete the peripheral layer, implement recovery orchestration, close timing, and validate on physical hardware.
- **Deliverables:**
  - `rtl/display/vga_controller.v` & `vga_framebuffer.v`: 320x240 dual-port video engine displaying live bid/ask bars.
  - `constraints/nexys_a7.xdc`: Complete pin assignments for Ethernet, VGA, and UART.
  - Recovery FSM: Implements MoldUDP64 gap handling, book clearing, and synthetic snapshot reload.
- **Acceptance Criteria:** Post-route static timing closure across all clock domains ($WNS \ge 0, WHS \ge 0$). Physical demonstration of live Ethernet packet playback on Nexys A7 board with real-time VGA order book visualization.

---

# L. Immediate Next Action

### Recommended Milestone: **Phase 1 (CPU Hygiene, ISA Fixes & System Bus Expansion)**

**Justification:**  
Before any hardware accelerator can be connected, the CPU bus interconnect must possess a valid, non-faulting slave port to receive transactions. Currently, `sys_bus_interconnect.v` triggers an unhandled CPU bus error exception whenever address `0x4000_0000` is accessed. Furthermore, the CPU decoder contains a lurking architectural bug (`AUIPC` is unrecognized and throws an `illegal_inst` exception). 

Fixing `AUIPC` in `decoder.v`, implementing a proper 2-stage synchronizer on the 7-segment display CDC boundary in `top_fpga.v`, and adding the decoded `0x4000_0000` LOB slave port in `sys_bus_interconnect.v` represents a tightly bounded, 1-day engineering task that:
1. Stabilizes the CPU baseline and prevents compiler-induced crashes.
2. Clears the bus attachment path so that the LOB accelerator (or a mock loopback stub) can be integrated immediately.
3. Preserves all verified baseline simulation passes (`addition`, `fibo`, `rv32m`).

---

# M. Context for the Next AI Agent

### M.1 Mandatory Constraints & Safeguards
1. **Clock Domain Discipline:**
   - `clk_core` = 100.00 MHz (CPU, Bus, LOB Core, Matching Engine, MMIO).
   - `clk_eth` = 50.00 MHz (RMII PHY, MAC RX, Packet Buffers, ITCH Parser).
   - `clk_vga` = 25.175 MHz (VGA Raster Timing, Framebuffer Read Port).
   - *Rule:* Never pass multi-bit buses across clock domains using single flip-flop chains. All cross-domain events must traverse `FIFO36E1` asynchronous Gray-pointer FIFOs or toggle-handshake synchronizers.
2. **CPU Clocking Reality:**
   - The current CPU runs at 1 Hz on hardware (`slow_clk`). Do not assume it is running at 100 MHz. When migrating the CPU to 100 MHz, verify post-route timing closure in Vivado STA.
3. **Memory Primitive Boundaries:**
   - Target FPGA: `XC7A100T-1CSG324C` (135 RAMB36E1 tiles = 270 RAMB18E1).
   - Total system BRAM allocation must stay strictly within the 111 RAMB18 (55.5 RAMB36-equivalent) analytical budget defined in Section I.2.
   - Price-level memory read latency is **3 clock cycles** (`DOB_REG = 1` plus registered 16:1 multiplexer). Any state machine reading price levels must account for this 3-cycle delay.
4. **Order Replace Semantics:**
   - ITCH Order Replace (`U`) **does not contain a Buy/Sell indicator**. It cannot be decomposed into Delete and Add in the parser. It must be processed by `lob_core` as a compound 2-beat atomic commit that extracts the resting side from the existing slot descriptor.
5. **Recovery Realities:**
   - The FPGA has no network transmit path. It cannot download GLIMPSE snapshots over TCP. All recovery snapshots must be injected by host software as synthetic canonical events.

### M.2 Key File Locations
- Core CPU: `rtl/cpu/core/cpu_core.v`
- System Bus: `rtl/cpu/core/sys_bus_interconnect.v`
- M-Extension Unit: `rtl/cpu/core/rv32m_unit.v`
- Top FPGA: `rtl/cpu/core/top_fpga.v`
- Pin Constraints: `constraints/nexys_a7.xdc`
- Authoritative Specification: `docs/phase1_architecture_final_v7.md`
- Non-Project Vivado Build Script: `vivado/scripts/build_bitstream.tcl`
- Post-Route STA Report: `build/post_route_timing.rpt`
- Post-Route Utilization: `build/post_route_utilization.rpt`

---
*Report concluded. End of technical audit.*
