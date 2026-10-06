# Lab 5 CPU Baseline Implementation Record

This document records the exact state of the imported Lab 5 processor prior to architectural refactoring for the LOB project. It serves as an immutable reference model and performance baseline.

## 1. Exact Imported Modules
The following RTL and simulation files were imported directly from the verified Lab 5 source into `rtl/cpu/lab5_baseline` and `sim/unit/lab5_baseline`:
- `IF_ID.v`: Instruction Fetch & Decode stage, immediate generation, and IF/ID pipeline register.
- `execute.v`: Execution stage, single-cycle ALU, branch evaluation, next PC logic, EX/WB pipeline register.
- `wb.v`: Memory writeback formatting, byte-alignment logic, and 2-cycle branch stall logic.
- `pipe.v`: Top-level CPU pipeline integration, holding the `regs[31:1]` register file and forwarding multiplexers.
- `memory.v`: `instr_mem` and `data_mem` definitions.
- `opcode.vh`: RV32I opcode definitions and parameters.
- `seven_seg_driver.v` / `top_fpga.v`: Original FPGA wrapper and display drivers.

## 2. Original Pipeline Structure
- **3-Stage Pipeline**: `IF + ID` -> `EX` -> `MEM + WB`.
- Instruction fetch happens concurrently with decode; data memory is accessed sequentially over the transition from EX to WB.
- Next PC update logic occurs in the EX stage.

## 3. Existing Clock / Reset Behavior
- **Clock**: Driven by a divided 1 Hz `slow_clk` inside `top_fpga.v` for human observation on physical LEDs.
- **Reset**: Active-low, fully synchronous/asynchronous mix depending on the module. `stall_read` properly clears to `1'b0` preventing deadlocks on reset.

## 4. Existing Instruction Support
- **RV32I Base**: `LUI`, `JAL`, `JALR`, `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`, `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`.
- Fully tested and compliant with the unprivileged RISC-V specification.

## 5. Existing Memory Interface
- **Instruction Memory**: Synchronous 4 KB BRAM (`imem.hex`). 1-cycle read latency.
- **Data Memory**: Synchronous 4 KB BRAM (`dmem.hex`). Address issued dynamically from EX stage (`alu_operand1 + execute_immediate`), reads complete by WB stage. Features internal bypass forwarding for same-cycle read-after-write.

## 6. Existing Forwarding & Hazard Behavior
- **RAW Dependencies**: WB-to-EX forwarding provides 0-cycle stall penalty for consecutive ALU and Load operations.
- **Control Hazards**: Handled via 2-cycle branch flush (`wb_stall_first_o`, `wb_stall_second_o`). Evaluated in the EX stage. Speculative stores are properly gated by `!branch_stall`.

## 7. Existing Benchmark Results
The baseline was re-simulated using Vivado XSim. All tests passed correctly using the original `mem_generator` C-code toolchain:
- **`addition`**: Passed (`$finish` at 275 ns).
- **`fibo`**: Passed (`$finish` at 1605 ns).
- **`negative`**: Passed (`$finish` at 275 ns).
- **`sort`**: Passed (`$finish` at 1545 ns).
- **`xor`**: Passed (`$finish` at 275 ns).

## 8. Baseline FPGA Resource Utilization
Synthesized for `XC7A100T-1CSG324C` using Vivado 2026.1:
- **Slice LUTs**: 2,613 (4.12%)
- **Slice Registers (FF)**: 1,304 (1.03%)
- **Block RAM Tiles**: 1 (0.74%) *(Note: Remaining memory mapped to distributed RAM128X1D)*
- **DSPs**: 0 (0.00%)

## 9. Baseline Timing
- **Target Clock**: 100 MHz (10.000 ns period)
- **Worst Negative Slack (WNS)**: +5.959 ns
- **Worst Hold Slack (WHS)**: +0.140 ns
- **Timing Closure**: Met gracefully. Maximum theoretical operating frequency (Fmax) of the baseline is ~247 MHz.

## 10. Known Limitations Requiring Modification
- Register file is embedded directly inside `pipe.v`.
- BRAMs are hardcoded point-to-point connections rather than using a standard addressable bus.
- Pipeline hold logic (`stall_read`) is a 1-cycle delayed active-high feedback mechanism that must be replaced by a robust stall net allowing multi-cycle M-extension execution and explicit wait-states for MMIO/LOB transactions.
