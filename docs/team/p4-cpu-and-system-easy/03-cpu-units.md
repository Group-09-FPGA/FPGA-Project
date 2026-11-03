# The small CPU units

Each file is short; know what it does, its inputs and outputs.

## `decoder` (`rtl/cpu/core/decoder.v`, 73 lines)

**Job:** split a 32-bit instruction into fields and control flags (purely combinational).

| Output | Meaning |
| --- | --- |
| `rs1`, `rs2`, `rd`, `funct3` | register numbers (bits 19:15, 24:20, 11:7) and the function code (14:12) |
| `immediate` | sign-extended immediate; the shape depends on the format (I, S, B, U, J) |
| `immediate_sel` | use the immediate as the ALU's 2nd operand (JALR, loads, ARITHI, stores) |
| `alu` | register-register or register-immediate arithmetic (not the M extension) |
| `lui`, `auipc`, `jal`, `jalr`, `branch`, `mem_write`, `mem_to_reg` | which kind of instruction |
| `arithsubtype` | bit 30: distinguishes `ADD`/`SUB` and `SRL`/`SRA` |
| `m_op` | `opcode == ARITHR && funct7 == 0000001`: a multiply/divide instruction |
| `illegal_inst` | unrecognised opcode |

Constants come from `opcode.vh` (`ARITHR`, `ARITHI`, `LOAD`, `STORE`, `BRANCH`, `JAL`, `JALR`, `LUI`, `AUIPC`, ...). The immediate is built per opcode, e.g. for a store `{{20{inst[31]}}, inst[31:25], inst[11:7]}` (the immediate is split in two places in S-type encoding).

## `reg_file` (34 lines)

31 registers (`regs[31:1]`); `x0` reads as 0 and cannot be written. **Two read ports** (combinational) and **one write port** (clocked). Reset clears every register.
`assign read_data1 = (read_addr1 == 0) ? 0 : regs[read_addr1];`

## `alu` (28 lines)

Computes by `alu_op` (the instruction's `funct3`): `ADD` (with `arithsubtype` → `SUB`), `SLL`, `SLT` (signed compare), `SLTU` (unsigned compare), `XOR`, `SR` (`SRL`/`SRA` by `arithsubtype`), `OR`, `AND`. The signed compare uses a 33-bit subtraction and takes the sign bit.

## `branch_unit` (25 lines)

Compares two operands by `branch_op`: `BEQ` (difference = 0), `BNE`, `BLT` (signed difference negative), `BGE`, `BLTU`, `BGEU` (unsigned). Output `condition_met`.

## `forwarding_unit` (34 lines)

Described in the pipeline chapter: bypasses the register file when the WB stage holds the value EX needs. Rules: `x0` → 0; otherwise if the WB stage writes that register and is not stalled → forward (load data if the WB instruction is a load); else the register-file value.

## `hazard_unit` (29 lines)

Two flip-flops `wb_stall_first`, `wb_stall_second` shifting `wb_branch`: they hold for two cycles after a taken branch to flush the wrong-path instructions. `wb_stall_o` is their OR.

## `rv32m_unit` (204 lines)

Implements the M extension: `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU` (selected by `funct3`).

### State machine: `STATE_IDLE → STATE_MULT or STATE_DIV → STATE_DONE`

| State | Job |
| --- | --- |
| `IDLE` | waits for `start` (a 1-cycle strobe from EX). If `funct3[2] == 0` it is a multiply → capture operands, go to `MULT`; else a divide → initialise, go to `DIV` |
| `MULT` | **3-stage pipelined multiplier**: stage 1 registers the 33-bit sign-extended operands; stage 2 captures the 66-bit product; stage 3 picks the low 32 bits (`MUL`) or the high 32 (`MULH*`); then `DONE` (about 3 cycles; the tool maps the multiply to DSP blocks) |
| `DIV` | **32-iteration restoring divider**: each cycle shifts the remainder, tries to subtract the divisor, and sets one quotient bit (the same algorithm as the display's price divider). Takes 32 cycles |
| `DONE` | holds `result` and `done = 1` until the pipeline accepts it (`!stall_pipeline`) |

`busy = (state == MULT) || (state == DIV)`; `done = (state == DONE)`; `m_stalling = ex_m && !m_done` in `cpu_core` freezes the pipeline while busy.

### Signed handling and the corner cases (a classic viva topic)

- Signed divide/remainder work on **absolute values** (`abs_op1`, `abs_op2`) and fix the signs afterwards: quotient negative if the operand signs differ (`neg_quo`), remainder takes the dividend's sign (`neg_rem`).
- **Divide by zero:** `DIV`/`DIVU` return `0xFFFFFFFF`; `REM`/`REMU` return the dividend (`orig_op1`). No exception.
- **Overflow** (`0x80000000 / -1`): `DIV` returns `0x80000000`, `REM` returns 0.

These are exactly the results the RISC-V specification requires; `tb_rv32m_unit` tests them.

### Where the M unit is used in this project

The supervisor firmware does not use M instructions, but the core supports them (the display CPU's C firmware may compile multiplications and divisions).

## `opcode.vh`

A header of constants for opcodes and `funct3` values, included by decoder, ALU and branch unit.
