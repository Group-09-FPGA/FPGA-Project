# CPU Architecture & Refactoring Specification: RV32IM

> Historical CPU design notes. The integrated system currently clocks the CPU
> at 50 MHz; standalone 100 MHz projections below are not a routed
> full-system result.

## 1. Baseline Lab 5 Processor Review

The baseline processor is an academic 3-stage pipelined RV32I softcore originally targeted for the Nexys A7 FPGA.

```
       Stage 1: IF + ID              Stage 2: EX              Stage 3: MEM + WB
     ┌───────────────────┐       ┌─────────────────┐       ┌─────────────────┐
     │ - Program Counter │       │ - Register File │       │ - Data Memory   │
     │ - Instr Memory    │ ────► │   Read & Muxes  │ ────► │   Byte Align    │
     │ - Instruction Dec │       │ - ALU Core      │       │ - RegFile Write │
     │ - Imm Generator   │       │ - Branch Comp   │       │ - Branch Stall  │
     └───────────────────┘       └─────────────────┘       └─────────────────┘
               ▲                                                    │
               └────────────────── Feedback / Flush ────────────────┘
```

### 1.1 Inherited Bug Fixes (Preserved Behavior)
The following critical hardware bugs were previously diagnosed and resolved in the baseline:
1. **Multi-Driver Write-Address Contention**: Decoupled `wb_mem_address` (driven by `wb.v`) from `ex_store_addr_r` (pipeline register output feeding `wb.v` input).
2. **Store Address/Data Timing Mismatch**: Store address and data were made synchronous through `ex_mem_wb_reg` rather than bypassing combinatorially, ensuring proper alignment with `mem_write`.
3. **Unintended Store Output Delay**: `wb.v` store formatting (`wb_write_data_o`, `wb_write_byte_o`, `wb_mem_address_o`) was converted to combinational logic (`always @*`), eliminating an extraneous 1-cycle latency penalty.
4. **Stores Executing During Branch Stalls**: Gated `mem_write` in `ex_mem_wb_reg` with `!branch_stall` so speculative stores on taken branches do not corrupt memory.
5. **Instruction-Bus Feedback**: Fixed `IF_ID.v` where `instruction_o` was looping into `instruction_i`.
6. **Permanent Reset Stall**: Fixed `stall_read` reset state from `1'b1` to `1'b0`.
7. **Incorrect Store Immediate Handling**: Enabled `immediate_sel` for S-type instructions so the ALU properly adds `rs1 + imm` for store addresses.
8. **Garbage Instruction Propagation During Stalls**: Ensured that when `stall_read_i == 1`, `IF_ID` outputs a clean `NOP` (`0x00000013`) into the pipeline rather than old or undefined state.
9. **SLT Zero-Extension**: Ensured signed comparison bit `ex_result_subs[32]` is zero-extended to 32 bits (`{31'b0, ex_result_subs[32]}`).

---

## 2. Architectural Refactoring & Module Decomposition

To support standard memory bus transactions and hardware accelerator expansion, the monolithic Lab 5 files (`pipe.v`, `IF_ID.v`, `execute.v`, `wb.v`) are refactored into modular, testable components.

```
rtl/cpu/
├── cpu_top.v            # Top-level CPU wrapper integrating pipeline & bus master
├── reg_file.v           # 32x32-bit dual-read asynchronous, single-write synchronous
├── alu.v                # Combinational 32-bit integer ALU (RV32I operations)
├── rv32m_unit.v         # Multi-cycle signed/unsigned multiplier and serial divider
├── decoder.v            # Opcode, funct3, funct7 decode and immediate generator
├── hazard_unit.v        # Stall generation, forwarding controls, branch redirect
├── pipeline_if_id.v     # IF/ID stage registers and fetch PC generator
├── pipeline_id_ex.v     # ID/EX pipeline registers
└── pipeline_ex_wb.v     # EX/WB pipeline registers and load/store formatting
```

---

## 3. Pipeline Stages & Instruction Flow

The CPU retains the high-throughput 3-stage pipeline model:

### Stage 1: Instruction Fetch & Decode (IF / ID)
- **Fetch**: Current `pc` is presented to Instruction Memory. In parallel, `pc + 4` is prepared.
- **Synchronous BRAM Read**: Instruction arrives 1 cycle after PC update.
- **Decode**: Opcode, `rd`, `rs1`, `rs2`, `funct3`, `funct7`, and immediate formats (I, S, B, U, J) are decoded combinationally.
- **Pipeline Register 1 (`id_ex_reg`)**: Latch decoded control signals, immediate values, register select indices, and PC.

### Stage 2: Execute (EX)
- **Register Read**: Asynchronous read of `rs1` and `rs2` from `reg_file`.
- **Operand Forwarding**: Bypass muxes select between raw register output, WB-stage ALU result, or WB-stage load data.
- **ALU Operation**: Single-cycle integer arithmetic, logic, shifts, and comparisons.
- **M-Extension Acceleration**: Multi-cycle DSP multiplier (3 cycles) and radix-2 divider (33 cycles). Asserts `rv32m_busy` to hold pipeline.
- **Branch Evaluation**: Subtraction comparison evaluates condition (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`). Computes branch target (`pc + imm`) or jump target (`rs1 + imm`).
- **Load Address Generation**: Computes effective memory address `rs1 + imm`.
- **Pipeline Register 2 (`ex_wb_reg`)**: Latches execution result, store data, target address, and writeback control signals.

### Stage 3: Memory Access & Writeback (MEM / WB)
- **System Bus Transaction**:
  - For Stores: `sys_addr`, `sys_wdata`, `sys_wstrb` driven onto system bus.
  - For Loads: Reads formatted from `sys_rdata` according to `funct3` (`LB`, `LH`, `LW`, `LBU`, `LHU`) with sign/zero extension.
- **Wait-State Handling**: If `sys_ready == 0`, pipeline holds in place until transaction completes.
- **Writeback**: Synchronous write of load data or ALU/MUL/DIV result into `reg_file[rd]`.

---

## 4. Hazard Handling, Forwarding, and Stalls

### 4.1 Data Hazards & Forwarding
In our 3-stage pipeline, instruction $I_1$ in EX writes its result to WB on clock edge $k+1$. Instruction $I_2$ in EX at clock cycle $k+1$ requires operands that may depend on $I_1$.

```verilog
// Forwarding condition for rs1
assign forward_rs1 = (src1_sel != 5'd0) && wb_reg_write_en && (wb_dest_reg == src1_sel);
assign alu_op1_forwarded = forward_rs1 ? (wb_mem_to_reg ? wb_load_data : wb_result)
                                       : reg_rdata1;
```

- **ALU-to-ALU**: Result from EX is registered to WB and immediately forwarded back into EX during the following clock cycle with **0 stall cycles**.
- **Load-to-Use**: Load address is computed in EX and presented to memory. Because BRAM has 1-cycle synchronous read latency, data is available in the WB stage. Since the dependent instruction is in EX during that same cycle, the data is forwarded directly from the memory output with **0 stall cycles**.

### 4.2 Control Hazards (Branches & Jumps)
- Branches and jumps are resolved in the **EX stage**.
- When a branch is taken, two instructions are already in flight:
  1. Instruction currently being fetched in IF.
  2. Instruction currently held in the IF/ID register.
- **Resolution**:
  - The hazard unit asserts `branch_flush`.
  - Next PC is updated to the branch target address.
  - IF/ID pipeline register is overwritten with a hardware `NOP` (`0x00000013`).
  - Total penalty for taken branch: **2 clock cycles**.

---

## 5. RV32M Extension Implementation

### 5.1 Opcode Encoding
All M-extension instructions use `OPCODE = 7'b0110011` (`ARITHR`) with `funct7 = 7'b0000001`:

| Instruction | funct3 | Operation | Latency |
| :--- | :--- | :--- | :--- |
| `MUL` | `3'b000` | Lower 32 bits of $(rs1 \times rs2)$ | 3 cycles |
| `MULH` | `3'b001` | Upper 32 bits of signed $\times$ signed | 3 cycles |
| `MULHSU`| `3'b010` | Upper 32 bits of signed $\times$ unsigned | 3 cycles |
| `MULHU` | `3'b011` | Upper 32 bits of unsigned $\times$ unsigned | 3 cycles |
| `DIV` | `3'b100` | Signed quotient $(rs1 / rs2)$ | 33 cycles |
| `DIVU` | `3'b101` | Unsigned quotient $(rs1 / rs2)$ | 33 cycles |
| `REM` | `3'b110` | Signed remainder $(rs1 \% rs2)$ | 33 cycles |
| `REMU` | `3'b111` | Unsigned remainder $(rs1 \% rs2)$ | 33 cycles |

### 5.2 Multi-Cycle Multiplier (`rv32m_mult`)
- Leverages Artix-7 DSP48E1 slices configured as a 3-stage pipeline.
- Operands are sign/zero extended to 33 bits:
  - `A_ext = is_signed_op1 ? {op1[31], op1} : {1'b0, op1};`
  - `B_ext = is_signed_op2 ? {op2[31], op2} : {1'b0, op2};`
- DSP pipeline stages:
  - Stage 1: Input register.
  - Stage 2: Multiplier array.
  - Stage 3: Product pipeline register ($66$-bit result).
- Counter tracks 3 cycles before asserting `mult_done`.

### 5.3 Serial Divider (`rv32m_div`)
- Compact sequential non-restoring radix-2 division engine.
- Cycle 0: Latches operands, determines output sign, takes absolute values if signed.
- Cycles 1–32: Shifts partial remainder and dividend left by 1 bit, subtracts/adds divisor.
- Cycle 33: Fixes remainder sign, applies RISC-V corner-case quotient adjustments:
  - Divide by zero: Quotient = `32'hFFFF_FFFF` (signed) or `32'hFFFF_FFFF` (unsigned); Remainder = `op1`.
  - Overflow (`-2147483648 / -1`): Quotient = `-2147483648`; Remainder = `0`.
- Asserts `div_done`.

---

## 6. System Bus Interface

The CPU connects to the system interconnect using the master interface:

```verilog
module cpu_top (
    input  wire        clk,
    input  wire        reset_n,

    // Instruction Bus (Direct BRAM Port)
    output wire [31:0] ibus_addr,
    input  wire [31:0] ibus_rdata,

    // Data / System Bus Master
    output wire [31:0] sys_addr,
    output wire [31:0] sys_wdata,
    output wire [3:0]  sys_wstrb,
    output wire        sys_valid,
    output wire        sys_write,
    input  wire [31:0] sys_rdata,
    input  wire        sys_ready,
    input  wire        sys_error
);
```

### Bus Stall Mechanics:
- When a load or store instruction is in the MEM stage:
  - If `sys_ready == 1'b0`, the CPU hazard unit asserts `stall_bus = 1'b1`.
  - `fetch_pc`, `pipeline_if_id`, and `pipeline_id_ex` are held frozen.
  - When the peripheral responds with `sys_ready == 1'b1`, data is captured, and the pipeline resumes on the next clock edge.

---

## 7. Timing Expectations & Constraints

- **Target Frequency**: 100 MHz ($T_{clk} = 10.0\text{ ns}$).
- **Critical Paths**:
  1. ALU comparison subtraction to branch condition evaluation: ~4.2 ns.
  2. BRAM address generation through System Bus decoder: ~3.8 ns.
  3. DSP multiplier output to EX/WB pipeline register: ~3.1 ns.
- All intra-core paths meet timing comfortably on Artix-7 -1 speed grade at 100 MHz.
