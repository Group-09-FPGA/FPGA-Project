# CPU Data-Path Modularization (Phase 2)

## Overview
This document summarizes Phase 2 of the RV32I CPU refactoring. The goal was to dismantle the monolithic pipeline registers and functional units in `lab5_baseline` (`IF_ID.v`, `execute.v`, `pipe.v`, `wb.v`) and extract them into clean, distinct, testable modules, while reproducing the exact 3-stage baseline structure (IF+ID -> EX -> MEM+WB).

## Module Mapping

| Old Baseline File | Extracted Core Modules | Description |
|-------------------|-------------------------|-------------|
| `pipe.v` | `reg_file.v`, `cpu_core.v` | Extracted the inline register array into `reg_file.v`. `cpu_core.v` serves as the top-level pipeline wrapper replacing `pipe.v`. |
| `pipe.v` | `forwarding_unit.v` | Extracted the inline EX-stage forwarding multiplexers. |
| `execute.v` | `alu.v`, `branch_unit.v` | Extracted ALU arithmetic and logical operations, as well as branch target/condition evaluation. |
| `IF_ID.v` | `decoder.v` | Extracted immediate formatting and instruction opcode decoding. |
| `wb.v` | `hazard_unit.v` | Extracted the 2-cycle branch stall state machine. |
| `pipe.v`, `wb.v` | `cpu_core.v` | Memory load aligner and store byte-enables were kept inline in `cpu_core.v` during the WB stage. |

## Verification Results
Differential verification was performed using the 5 provided benchmark programs (`addition`, `fibo`, `negative`, `sort`, `xor`).

A new testbench `tb_cpu_core.v` was created to instantiate `cpu_core`. 
The execution traces (including all `next_pc` values and cycle-accurate register writes) were compared against the baseline `lab5_baseline` trace logs. 

**Result**: 100% MATCH. All 5 programs exhibit identical PC progressions, data memory interactions, and register file contents cycle-by-cycle.

## Behavioral Notes
- The forwarding multiplexing and register file reads must occur in the EX stage, NOT the ID stage, to properly intercept data from the WB stage for a 1-cycle pipeline gap (e.g., `lw` -> `add`). The new `cpu_core.v` retains this architecture.
- The 2-cycle branch stall logic generates `wb_stall_first` and `wb_stall_second` using the delayed branch evaluation. This has been safely preserved in `hazard_unit.v`.

## Synthesis Results
The refactored `cpu_core.v` (inside `top_fpga.v`) was synthesized for XC7A100T-1CSG324C with a target clock of 100 MHz.

### Resource Utilization Comparison
| Metric | Baseline (`lab5_baseline`) | Refactored (`core`) |
|--------|----------------------------|---------------------|
| LUTs   | 2613                       | 2537                |
| FFs    | 1304                       | 1298                |
| BRAM   | 1                          | 1                   |
| DSP    | 0                          | 0                   |

### Timing Summary Comparison (100 MHz)
| Metric | Baseline (`lab5_baseline`) | Refactored (`core`) |
|--------|----------------------------|---------------------|
| WNS    | +5.959 ns                  | +5.959 ns           |
| WHS    | +0.207 ns                  | +0.140 ns           |

The refactored CPU achieves identical behavioral verification while successfully breaking down the legacy Lab 5 data-path into individual verifiable modules.
