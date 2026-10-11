# FPGA LOB Block Diagrams Application

Interactive, presentation-themed technical block diagrams for the RV32IM + pure-hardware Limit Order Book (LOB) accelerator on Xilinx Artix-7 (Nexys A7-100T).

## Running

```bash
cd diagrams
pnpm install
pnpm dev
```

Visit the local URL (e.g. `http://localhost:5173/` or `http://localhost:5174/`).

## Diagram Views

Use the sidebar navigation or keyboard keys (`←`, `→`, `PageUp`, `PageDown`):

1. **System Overview (`#system`)**: Top-level 3-clock-domain architecture (`clk_eth` 50 MHz, `clk_core` 100 MHz, `clk_vga` 25.175 MHz), showing RMII PHY, MAC RX, network parser, async CDC FIFO, 3-stage RV32IM CPU core, system bus interconnect, memory slaves, hardware LOB core, and display path.
2. **CPU Pipeline (`#cpu`)**: Detailed 3-stage pipeline (IF, EX, WB) with decoded control signals, operand multiplexers, ALU, branch condition unit, multi-cycle `rv32m_unit`, register file, WB-to-EX forwarding paths, 2-cycle branch hazard stalls, and bus master arbiter with priority `WB > EX > IF`.
3. **RV32M Unit (`#rv32m`)**: Deep-dive into the hardware extension: 4-state FSM (`IDLE`, `MULT`, `DIV`, `DONE`), 3-stage pipelined multiplier (3-cycle stall), 32-iteration restoring divider (33-cycle stall), div-by-zero, overflow detection, and funct3 truth table.
4. **Hardware LOB Core (`#lob`)**: 10-cycle Add schedule, 8-cycle Cancel/Delete schedules, Op Sequencer FSM, 2048-set 4-way CRC32-C Hash Table (24 BRAMs), CAM Stash, 4096-entry Slot Table (15 BRAMs), Free-List FIFO, 65536-entry Price Level RAM (64 BRAMs), 3-level Occupancy Mask, priority-encoder BBO Engine, shadow snapshot registers, and fail-stop invariants.
5. **Ethernet & ITCH Ingestion (`#eth`)**: 50 MHz RMII RX, ping-pong Packet RAM bank-ownership protocol, IPv4/UDP parser, MoldUDP64 sequence gap/duplicate handling, ITCH 5.0 message parser (`A`, `F`, `E`, `C`, `X`, `D`, `U`), 128-bit Canonical Event bitfield layout, and dual-clock async FIFO.
6. **Complete Module Table (`#modules`)**: Exhaustive status table of all 32 modules across CPU, Memory, Bus, I/O, LOB, Clock, Ethernet, ITCH, CDC, and Display subsystems with exact source file paths and implementation status, plus Artix-7 XC7A100T FPGA resource utilization budget.
