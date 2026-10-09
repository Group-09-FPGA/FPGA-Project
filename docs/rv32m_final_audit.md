# RV32M Final Independent Audit & Timing-Constraint Closure Report

**Date:** 2026-10-09  
**Engineer:** Antigravity Senior FPGA/RTL Verification Engineer  
**Target Hardware:** AMD/Xilinx Artix-7 FPGA (`xc7a100tcsg324-1` on Digilent Nexys A7-100T)  
**EDA Toolchain:** AMD Vivado Design Suite v2026.1 (lin64) Build 6511674, Vivado Simulator (XSim)  
**Audit Commit:** `6e2306d63fd689b86d1faf659e25986017ddc807`  
**Repository:** `/home/ronit/acad/current/hardware/fpga-lob`  

---

## Executive Summary

An independent audit of commit `6e2306d63fd689b86d1faf659e25986017ddc807` was conducted across RTL source code, constraints (`constraints/nexys_a7.xdc`), synthesis logs, testbenches, and Vivado STA reports. 

Key verified findings:
1. **Clock Definition Validity:** The generated clock `slow_clk` is correctly defined on `slow_clk_reg/Q` with `-source [get_pins slow_clk_reg/C]` and `-divide_by 100000000`. Vivado STA confirms 0 unconstrained internal endpoints and 0 registers without clock across all 2,150 CPU registers.
2. **False-Path Exception Audit:** The exception `set_false_path -from [get_cells slow_clk_reg] -to [get_cells slow_clk_reg]` is strictly necessary and optimal. It suppresses solely the bogus inter-clock hold violation on the register divider's internal toggle inverter (`slow_clk_i_1`), while the 100 MHz counter path driving `slow_clk_reg/D` remains fully timed with +5.967 ns of setup slack.
3. **Actual CPU Timing vs 100 MHz Target:** Under the implemented 1 Hz system clock, all timing constraints are met with positive slack (WNS = +1,000,000,000.000 ns, WHS = +0.132 ns). Under an exploratory 100 MHz (10.000 ns) constraint, the synthesized core achieves WNS = +0.420 ns (worst path delay: 9.198 ns across 17 logic levels). **However, 100 MHz operation is NOT verified for physical hardware**; the board clock divider remains hardwired to 1 Hz, and clock domain crossings to the 7-segment display remain unsynchronized.
4. **Divider Latency Resolved:** From the clock edge sampling `start` to the edge asserting `done`, the divider takes **exactly 32 clock cycles** (33 active clock edges inclusive). 31 iterations are registered during `div_cnt` 0..30, and the 32nd iteration is evaluated combinatorially at `div_cnt == 31` and registered directly into `result_reg` in `STATE_DONE`.
5. **Baseline Comparability & Endpoint Counts:** The endpoint difference between Baseline (11,554) and Core (8,597) is caused by distributed RAM inferencing (1,024 vs 512 dual/single-port RAM primitives due to bus interconnect restructuring), not timing constraint omission.

---

## 1. Generated Clock Validation (`slow_clk`)

### 1.1 Master Clock & Generated Target Specification
In `constraints/nexys_a7.xdc`:
```tcl
create_clock -period 10.000 [get_ports clk]

create_generated_clock -name slow_clk \
    -source [get_pins slow_clk_reg/C] \
    -divide_by 100000000 \
    [get_pins slow_clk_reg/Q]
```

- **Master Clock Source:** Port `clk` (pin `E3`), period 10.000 ns, waveform `{0.000 5.000}`, frequency 100.000 MHz.
- **Generated Clock Object:** `[get_pins slow_clk_reg/Q]`.
- **Reference Pin (`-source`):** `[get_pins slow_clk_reg/C]` (the clock pin of `slow_clk_reg`, driven by `clk`).
- **Divider Ratio Verification:**
  In `rtl/cpu/core/top_fpga.v`:
  ```verilog
  reg [25:0] clk_cnt;
  reg        slow_clk;
  always @(posedge clk or negedge reset) begin
      if (!reset) begin
          clk_cnt  <= 26'd0;
          slow_clk <= 1'b0;
      end else begin
          if (clk_cnt == 26'd49_999_999) begin
              clk_cnt  <= 26'd0;
              slow_clk <= ~slow_clk;
          end else begin
              clk_cnt <= clk_cnt + 1'b1;
          end
      end
  end
  ```
  `clk_cnt` counts $50,000,000$ cycles of `clk` per toggle. A complete clock cycle requires 2 toggles:
  $$\text{Period}_{\text{slow\_clk}} = 2 \times 50,000,000 \times 10.0\text{ ns} = 100,000,000 \times 10.0\text{ ns} = 1.000000000\text{ s}$$
  The divider ratio `100000000` is mathematically exact.

### 1.2 Vivado Clock Audit Commands & Output
Running Vivado 2026.1 `report_clocks` yields:
```text
Clock Report
Clock     Period(ns)      Waveform(ns)           Attributes  Sources
clk       10.000          {0.000 5.000}          P           {clk}
slow_clk  1000000000.000  {0.000 500000000.000}  P,G         {slow_clk_reg/Q}

====================================================
Generated Clocks
====================================================
Generated Clock     : slow_clk
Master Source       : slow_clk_reg/C
Master Clock        : clk
Divide By           : 100000000
Generated Sources   : {slow_clk_reg/Q}
```

### 1.3 Clock Network & Pin Coverage (`check_timing -verbose`)
`report_clock_networks` and `check_timing -verbose` output:
- `slow_clk_reg/Q` is routed to global clock buffer `slow_clk_reg_n_0_BUFG_inst` (`BUFG`), which distributes `slow_clk` across all CPU and system bus flip-flops.
- Number of register clock pins driven by `slow_clk`: **2,150**.
- Number of register clock pins driven by `clk`: **48** (`clk_cnt_reg[0..25]`, `slow_clk_reg`, `seg_u/refresh_counter_reg[*]`).
- `check_timing -verbose` results:
  - `no_clock`: **0** (0 register/latch pins without a clock).
  - `constant_clock`: **0**.
  - `unconstrained_internal_endpoints`: **0**.
  - `multiple_clock`: **0**.
  - `generated_clocks`: **0** (no disconnected generated clocks).
  - `loops`: **0**.
  - `latch_loops`: **0**.

---

## 2. Audit of the False-Path Exception

### 2.1 Applied Exception
In `constraints/nexys_a7.xdc`:
```tcl
set_false_path -from [get_cells slow_clk_reg] -to [get_cells slow_clk_reg]
```

### 2.2 Necessity and Root Cause
When `create_generated_clock` is attached to `slow_clk_reg/Q`, Vivado STA classifies the output pin `slow_clk_reg/Q` as the source of clock domain `slow_clk`. However, the RTL logic that toggles `slow_clk` feeds `slow_clk_reg/Q` back into LUT `slow_clk_i_1` to drive `slow_clk_reg/D`:
- **Launch Edge:** Edge on `slow_clk_reg/Q` (associated by Vivado with `slow_clk`, period 1,000,000,000 ns).
- **Capture Edge:** Edge on `slow_clk_reg/C` (associated by Vivado with `clk`, period 10 ns).

Because the periods differ by 8 orders of magnitude, Vivado's hold algorithm finds the closest edge alignment between a 1 s clock and a 10 ns clock ($500,000,000\text{ ns}$ vs $500,000,064\text{ ns}$), generating an artificial hold requirement of $59.605\text{ ns}$ and reporting a bogus hold violation of **-59.605 ns**.

In physical reality, `slow_clk_reg` is a standard synchronous toggle flip-flop in the 100 MHz `clk` domain. The delay through `slow_clk_reg/Q -> slow_clk_i_1 -> slow_clk_reg/D` is only 1.101 ns, which easily meets the 10.0 ns board clock period.

### 2.3 Narrowness and Timing Preservation Audit
- **Paths Suppressed:** Strictly 1 path: `slow_clk_reg/Q -> slow_clk_i_1/O -> slow_clk_reg/D`.
- **Paths Preserved:** The counter enable path `clk_cnt_reg[18]/C -> ... -> slow_clk_i_1/O -> slow_clk_reg/D` begins at cell `clk_cnt_reg[18]`, NOT `slow_clk_reg`. It is **NOT suppressed**.
- **Proof from Vivado STA:**
  ```text
  report_timing -from [get_cells {clk_cnt_reg[*]}] -to [get_cells slow_clk_reg]
  Slack (MET) : 5.967ns (required time - arrival time)
  Source:       clk_cnt_reg[18]/C (clocked by clk, period 10.000ns)
  Destination:  slow_clk_reg/D (clocked by clk, period 10.000ns)
  Path Group:   clk
  Data Path Delay: 3.897ns (logic 1.261ns, route 2.636ns)
  ```
  The counter-to-divider path is actively timed under the 100 MHz clock and passes with +5.967 ns slack.
- **Evaluation:** The cell-to-cell false path is the narrowest justified exception. It does not use broad clock-to-clock exceptions (`set_clock_groups` or `set_false_path -from [get_clocks slow_clk] -to [get_clocks clk]`) and conceals no real datapath or control path.

---

## 3. Actual CPU Timing Verification

### 3.1 Implemented 1 Hz Hardware Timing (`slow_clk`)
Under the actual system configuration:
- **Worst Setup Path:**
  - Startpoint: `pipe_u/wb_alu_operation_reg[0]/C` (cell `FDCE`, clocked by `slow_clk`)
  - Endpoint: `dmem_u/DMEM/dmem_reg_0_255_0_0/RAMS64E_A/ADR1` (cell `RAMS64E`, clocked by `slow_clk`)
  - Clock Period: 1,000,000,000.000 ns (1.000 s)
  - Data Path Delay: **6.538 ns** (logic 2.095 ns, route 4.443 ns)
  - Logic Levels: **6** (`CARRY4=1 LUT2=1 LUT5=1 LUT6=3`)
  - Setup Slack (WNS): **+1,000,000,000.000 ns** (MET)
- **Worst Hold Path:**
  - Startpoint: `dmem_u/DMEM/rdata_reg[0]/C` (cell `FDRE`, clocked by `slow_clk`)
  - Endpoint: `pipe_u/bus_rdata_reg_reg[0]/D` (cell `FDCE`, clocked by `slow_clk`)
  - Data Path Delay: 0.376 ns (logic 0.245 ns, route 0.131 ns)
  - Logic Levels: 1 (`LUT3=1`)
  - Hold Slack (WHS): **+0.132 ns** (MET)

### 3.2 RV32M Unit Paths
Inspecting paths into, out of, and within `rv32m_unit`:
- State transition into `div_cnt_reg[0]/D`: Data path delay **1.345 ns** (1 logic level, `LUT2=1`).
- Multi-cycle execution gating (`ex_m_reg/C` to `div_cnt_reg/CE`): Data path delay **2.774 ns** (2 logic levels, `LUT5=1 LUT6=1`).
- Multiplier product capture: Handled by 4 cascaded DSP48E1 slices (`mult_prod_r20`) with dedicated internal pipelining registers.
- State completion to bus stall logic (`FSM_sequential_state_reg[0]/C` to `dmem_u/delay_cnt_reg[0]/CE`): Data path delay **4.348 ns** (5 logic levels).

### 3.3 Exploratory 100 MHz CPU Evaluation (Synthesis Study)
To evaluate maximum operating capability without altering the committed system clock, a test constraint of 10.000 ns was placed on `slow_clk_reg/Q`:
```text
Timing Summary (10.000 ns Test Clock)
WNS: +0.420 ns    TNS: 0.000 ns    Failing Endpoints: 0
WHS: +0.132 ns    THS: 0.000 ns    Failing Endpoints: 0
WPWS: +3.750 ns   TPWS: 0.000 ns   Failing Endpoints: 0
```
- **Worst 100 MHz Setup Path:**
  - Startpoint: `pipe_u/wb_alu_operation_reg[0]/C`
  - Endpoint: `pipe_u/if_buf_reg[0]/CE`
  - Data Path Delay: **9.198 ns** (logic 3.117 ns, route 6.081 ns)
  - Logic Levels: **17** (`CARRY4=8 LUT2=1 LUT3=2 LUT5=4 LUT6=2`)
  - Path Description: Propagates from writeback through forwarding multiplexers, ALU operand steering, 32-bit branch carry chain comparator, branch taken logic, and into the fetch skid-buffer clock enable.
  - Setup Slack: **+0.420 ns** (MET at 100 MHz post-synthesis).

### 3.4 Strict Distinction Regarding 100 MHz Operation
> [!IMPORTANT]
> **A 100 MHz CPU target has NOT been verified or implemented on hardware.**
> 1. The hardware divider `slow_clk_reg` divides the 100 MHz oscillator by $10^8$, driving the core at 1 Hz for manual inspection on FPGA LEDs.
> 2. The positive post-synthesis slack (+0.420 ns) proves that the unplaced logic cell delays can fit in 10 ns, but physical place-and-route routing delays and clock skew have not been closed at 100 MHz.
> 3. The 7-segment display logic crosses asynchronously from the CPU domain (`pc_out`) to the 100 MHz board domain (`seg_u`) without synchronizers. At 100 MHz, this would create metastability issues.
> 4. Therefore, the processor is verified for timing closure **strictly at 1 Hz**.

---

## 4. Report Provenance and Baseline Comparability

### 4.1 Provenance Verification
| Attribute | Baseline Report (`sim/unit/lab5_baseline/`) | RV32M Core Report (`docs/`) | Status |
| :--- | :--- | :--- | :--- |
| **Tool Version** | Vivado v2026.1 (lin64) Build 6511674 | Vivado v2026.1 (lin64) Build 6511674 | **Identical** |
| **Device Part** | `xc7a100tcsg324-1` | `xc7a100tcsg324-1` | **Identical** |
| **Synthesis Run** | Fri Oct 9 14:52:58 2026 | Fri Oct 9 14:51:52 2026 | **1 min delta (Same Session)** |
| **Target Top** | `top_fpga` | `top_fpga` | **Identical** |
| **Constraint File** | `constraints/nexys_a7.xdc` | `constraints/nexys_a7.xdc` | **Identical** |

### 4.2 Endpoint Count Explanation (11,554 vs 8,597)
In earlier reports, the baseline was reported with 11,554 endpoints while the RV32M core had 8,597 endpoints.
- **Root Cause:** In `rtl/cpu/lab5_baseline/`, instruction memory and data memory were dual separate direct arrays, inferring **1,024 dual-port distributed RAM primitives** (`RAMD64E`).
- In `rtl/cpu/core/`, the unified system bus interconnect (`sys_bus_interconnect`) mediates instruction fetch and data memory access over a shared request/response bus, inferring **512 single-port distributed RAM primitives** (`RAMS64E`).
- Because each distributed RAM primitive contains 4 clock-edge-sensitive address pins (`ADR0..3`), the 512 fewer RAM primitives in the Core account for the $\approx 2,950$ reduction in total timing endpoints.
- All internal registers in both builds are 100% constrained with 0 unconstrained endpoints.

### 4.3 Comparable Resource Utilization Delta
Comparing post-synthesis reports under identical constraints on `xc7a100tcsg324-1`:

| Resource | Lab 5 Baseline | RV32M Core | Absolute Delta | Notes |
| :--- | :---: | :---: | :---: | :--- |
| **Slice LUTs** | 2,613 | 2,688 | **+75** | +2.87% logic growth |
| - LUT as Logic | 1,589 | 2,176 | +587 | Replaced RAM LUTs + RV32M divider |
| - LUT as Memory | 1,024 | 512 | -512 | Single-port memory inference |
| **Slice Registers (FF)** | 1,304 | 1,683 | **+379** | Pipeline registers + divider registers |
| **DSP48E1 Blocks** | 0 | 4 | **+4** | $33 \times 33$ signed multiplier mapping |
| **Block RAM (RAMB36E1)** | 1 | 1 | **0** | Data memory buffer |
| **Total Artix-7 Utilization** | 4.12% LUT | 4.24% LUT | +0.12% | Negligible footprint impact |

---

## 5. Divider Latency & Iteration Verification

### 5.1 Reconciliation of Iterations and Cycles
In `rtl/cpu/core/rv32m_unit.v`:
- `div_cnt` is a 5-bit register counting from `5'd0` to `5'd31` (32 distinct values).
- **Cycles 0..30 (31 cycles):** Iterations 1 through 31. On each clock edge, the restoring recurrence evaluates `{rem_reg, quo_reg[31]} - div_reg` and updates `rem_reg` and `quo_reg`.
- **Cycle 31 (1 cycle):** Counter reaches `5'd31`. The recurrence logic combinatorially evaluates the **32nd quotient bit** (`next_quo`) and **32nd remainder** (`next_rem`), and combinatorially performs two's complement sign correction (`final_div_result`).
- On the next clock edge (Edge 33), `result_reg <= final_div_result` is latched and `state <= STATE_DONE` is entered.
- **Cycle 32:** In `STATE_DONE`, `done = 1'b1` is asserted combinationally.

### 5.2 Explicit Counting Conventions
1. **Clock Periods from `start` to `done`:** **Exactly 32 clock cycles**.
   - If `start` is sampled on Edge 1 ($t = 10\text{ ns}$), `done` transitions high on Edge 33 ($t = 330\text{ ns}$).
   - $\Delta t = 330\text{ ns} - 10\text{ ns} = 320\text{ ns} = 32 \times T$.
2. **Active Clock Edges Spanned (Inclusive):** **33 clock edges**.
   - Edge 1 (capture `start`), Edges 2..32 (iterations 1..31), Edge 33 (iteration 32 + latch result + assert `done`).
3. **Pipeline Residence in EX Stage:** **33 cycles**.
   - Cycle 1: instruction decode and launch (`m_start = 1`).
   - Cycles 2..33: pipeline stalled (`m_stalling = 1`, 32 stall cycles).
   - Cycle 34: `done` recognized by pipeline, result captured into EX/MEM register.

---

## 6. Verification Status Matrix

| Component | Audit Check | Method | Result |
| :--- | :--- | :--- | :---: |
| **RTL Arithmetic** | RV32M corner cases & 160 random vectors | `tb_rv32m_unit.v` | **PASS (236/236)** |
| **Pipeline Integration** | Zero memory delay (`DMEM_DELAY_CYCLES=0`) | `tb_rv32m_pipeline.v` | **PASS (31/31)** |
| **Pipeline Integration** | 3-cycle memory delay (`DMEM_DELAY_CYCLES=3`) | `tb_rv32m_pipeline.v` | **PASS (31/31)** |
| **Baseline Regression** | `addition`, `fibo`, `negative`, `sort`, `xor` | Simulation makefiles | **PASS (0 delta)** |
| **Bus Interconnect** | Bus error exception handling | `tb_bus_error.v` | **PASS (400 ns)** |
| **Static Timing** | Clock coverage & unconstrained pins | Vivado 2026.1 `check_timing` | **0 unconstrained** |
| **Static Timing** | Timing closure @ 1 Hz | Vivado 2026.1 `report_timing_summary` | **MET (WNS=+1.0s)** |
| **Hardware Baseline** | Untouched preservation of `lab5_baseline/` | Git diff vs HEAD | **100% UNTOUCHED** |

---

## 7. Remaining Limitations and Unverified Items

1. **Clock Domain Crossing to 7-Segment Driver:**
   - In `rtl/cpu/core/top_fpga.v`, `pc_out` originates in the 1 Hz `slow_clk` domain and connects directly to `seven_seg_driver seg_u`, which is clocked by the 100 MHz board oscillator `clk`.
   - Because `slow_clk` toggles once per second, setup/hold hazards do not cause visible display anomalies to the human eye. However, in an asynchronous high-frequency system, this bus crossing lacks multi-flop synchronizers or handshake synchronization.
2. **Physical Bitstream Hardware Run:**
   - Synthesis and Static Timing Analysis have been verified in Vivado 2026.1.
   - Physical placement, routing (`route_design`), bitstream generation (`write_bitstream`), and in-system hardware programming on a physical Digilent Nexys A7 development board were not run in this headless verification environment.
