# FPGA LOB Block Diagrams Application

Interactive, presentation-themed technical block diagrams for the RV32IM + pure-hardware Limit Order Book (LOB) accelerator on Xilinx Artix-7 (Nexys A7-100T).

## Running

```bash
cd docs/diagrams
pnpm install
pnpm dev
```

Visit the local URL: `http://localhost:5174/` (or default `http://localhost:5173/`).

## Diagram Views

Navigate using the top tabs, keyboard arrows (`←`, `→`, `Space`), or numbers `1`–`7`:

1. **Top-Level System Architecture (`#system`)**: Full-page 3-clock-domain overview (`clk_eth` 50 MHz, `clk_core` 100 MHz, `clk_vga` 25.175 MHz) showing the complete dataflow across network front-end, async CDC FIFO, 3-stage CPU, system bus interconnect, memory slaves, pure-hardware LOB core, and VGA display.
2. **CPU Pipeline (`#pipeline`)**: Detailed 3-stage pipeline (IF · ID · EX · WB) with exact stage boundaries, 3 physical pipeline registers (`IF/ID`, `ID/EX`, `EX/WB`), MUX selectors, WB→EX forwarding loops, and 2-cycle branch hazard logic.
3. **4-Cycle Pipelined Multiplier RTL Datapath (`#mul`)**: Pure RTL hardware schematic (no FSM bubbles) with 1-to-1 Verilog correspondence to `rv32m_unit.v`. Shows signed/unsigned sign-extension MUXes, 33×33-bit multiplication array, 66-bit partial product accumulation, lower/upper 32-bit formatting MUX, and output handshake across Cycles 1 to 4.
4. **39-Cycle Restoring Divider RTL Datapath (`#div`)**: Pure RTL hardware schematic (no FSM bubbles) with 1-to-1 Verilog correspondence to `rv32m_unit.v`. Shows absolute value negator MUXes, corner-case detectors (div-by-zero, overflow), 36-iteration restoring recurrence loop (`shifted_rem - div_reg`, borrow bit, remainder restoration MUX, quotient shift-in), sign correction MUXes, priority exception MUX, and output handshake across Cycles 1 to 39.
5. **Pure-Hardware Limit Order Book Accelerator (`#lob`)**: 10-cycle Add schedule, 8-cycle Cancel/Delete schedules, Op Sequencer, 2048-set 4-way Hash Table (24 BRAMs), CAM Stash, 4096-entry Slot Table (15 BRAMs), Free-List FIFO, 65536-entry Price Level RAM (64 BRAMs), 3-level Occupancy Mask, BBO Engine, coherent MMIO shadow registers, and fail-stop invariants.
6. **Pipeline Execution Timing Diagram (`#timing`)**: Interactive cycle-by-cycle trace from real hardware simulation (`tb_rv32m_pipeline.v`) across 25 clock cycles, demonstrating multi-cycle execution, skid buffer holding, RAW hazard forwarding, and hazard bubbles.
7. **Module Summary & FPGA Resource Estimates (`#modules`)**: Exhaustive technical table of all 27 project modules classified by language and purpose, alongside the Artix-7 XC7A100T utilization budget and verification strategy.
