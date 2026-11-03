# `cpu_core`: the 3-stage RV32IM pipeline

File: `rtl/cpu/core/cpu_core.v` (404 lines). Two instances exist in the chip: the **supervisor CPU** (`u_cpu` in `cpu_system`, runs `firmware_monitor.s`) and the **display CPU** (inside `kitty_ui_cpu`, owner 5, runs the UI firmware). Same module, different firmware.

## 1. RISC-V in one minute

**RV32IM** = 32-bit RISC-V with the **I**nteger base instructions and the **M** extension (multiply/divide). 32 registers `x0..x31` (`x0` is always 0). Every instruction is 32 bits. Formats you will see: R-type (register-register), I-type (immediate, loads), S-type (stores), B-type (branches), U-type (`lui`, `auipc`), J-type (`jal`).

*Analogy:* a laundry with three stations in a row. While shirt A is being washed (EX), shirt B is being collected (IF/ID) and shirt C is being folded (WB). Three shirts are in progress at once.

## 2. The three stages

```
   IF/ID                     EX                          WB
 ┌─────────────┐   ┌──────────────────────────┐   ┌─────────────────────────┐
 │ fetch_pc    │   │ register file read       │   │ write register          │
 │ fetch instr │──►│ forwarding               │──►│ store alignment (SB/SH/SW)
 │ decode      │   │ ALU / branch / multiply  │   │ load alignment (LB..LHU)│
 └─────────────┘   │ load request, next PC    │   └─────────────────────────┘
                   └──────────────────────────┘
```

| Stage | Registers | What happens |
| --- | --- | --- |
| **IF/ID** | `fetch_pc`, `if_buf`, `id_pc` | `fetch_pc` addresses instruction memory; the fetched word goes to the decoder (`u_decoder`) in the same cycle |
| **EX** | `ex_*` registers (`ex_pc`, `ex_imm`, `ex_rd`, `ex_rs1`, `ex_rs2`, `ex_alu_op` = funct3, control flags) | **the register file is read here** (`u_reg_file`, with `u_forwarding`), the ALU computes, the branch comparator decides, multiply/divide is started, a **load** is issued to the bus |
| **WB** | `wb_*` registers (`wb_result`, `wb_dest_reg_sel`, `wb_mem_write`, `wb_mem_address`, `wb_reg_rdata2`, ...) | result written to the register file; **stores** are issued to the bus; loaded bytes are aligned and sign-extended |

(Unusual detail worth knowing: the register file is read in the EX stage, not the decode stage, and the load/store requests come from EX/WB. This is the structure of the course baseline, extended with a bus.)

## 3. The program counter

```verilog
always @(posedge clk or negedge reset)
    if (!reset) fetch_pc <= RESET;                       // starts at 0x0000_0000
    else if (!stall_pipeline && !if_buf_valid)
        fetch_pc <= branch_stall ? fetch_pc + 4 : next_pc;
```

`next_pc` (combinational) is: `jal` → `ex_pc + imm`; `jalr` → `rs1 + imm`; a taken branch → `ex_pc + imm`; otherwise `fetch_pc + 4`. `pc_out = fetch_pc`, which is what the seven-segment shows in mode 11.

## 4. Instruction fetch and the "skid buffer"

The instruction comes back from the bus a clock after the request. If the pipeline stalls just as it arrives, it must not be lost:

```verilog
if (bus_state == ST_WAIT_IF && bus_rsp_valid) begin
    if (stall_pipeline && !if_buf_valid) begin if_buf <= bus_rsp_rdata; if_buf_valid <= 1; end   // save it
end
wire [31:0] fetched_instr = if_buf_valid ? if_buf : (arriving now) ? bus_rsp_rdata : NOP;
```

`if_buf` is a **one-word holding register** ("skid buffer"). A taken branch clears it (`if_buf_valid <= 0`) because the saved instruction is on the wrong path.

## 5. Hazards

### 5a. Data hazards: forwarding

Case: `add x5, x1, x2` followed immediately by `sub x6, x5, x3`. The second needs `x5` before the first has written it.
`forwarding_unit` solves it: if the instruction now in WB is writing the register that EX wants to read, **use the WB value directly**:

```verilog
assign rdata1 = (rs1 == 0) ? 0 :
                (!wb_stall && wb_reg_write_en && wb_rd == rs1) ? wb_forward_val : reg_rdata1_raw;
```

(`wb_forward_val` is the load data if the WB instruction is a load, else the ALU result.) No bubble needed.

### 5b. Control hazards: taken branches

`hazard_unit` keeps `wb_stall_first` and `wb_stall_second`: after a **taken** branch or jump (`wb_branch`) it suppresses the next two instructions already in flight (the wrong-path ones). `branch_stall = wb_stall_first || wb_branch`. This is a **2-cycle branch penalty**. There is no branch predictor: simple, and fine for a supervisor.

### 5c. Structural hazards: the single bus

One bus serves instruction fetch, loads and stores. See section 7.

## 6. The ALU result mux

```verilog
if      (ex_mem_write) ex_result = alu_operand2;     // store data
else if (ex_jal || ex_jalr) ex_result = ex_pc + 4;   // return address
else if (ex_lui)   ex_result = ex_imm;
else if (ex_auipc) ex_result = ex_pc + ex_imm;
else if (ex_alu)   ex_result = alu_out;
else if (ex_m)     ex_result = m_result;             // from rv32m_unit
```

The memory address of a load/store is `ex_mem_address = rs1 + imm` (a separate adder).

## 7. The bus master (the unusual part)

The CPU has **one** bus port, shared by three kinds of request:

| Source | Condition | Meaning |
| --- | --- | --- |
| **WB store** | `wb_mem_write && !wb_done` | write `wb_write_data` with byte strobes `wb_write_byte` |
| **EX load** | `ex_mem_to_reg && !ex_done && !branch_stall` | read at `ex_mem_address` |
| **IF fetch** | nothing else pending, `!if_buf_valid`, not stalled | read at `fetch_pc` |

**Priority: store > load > fetch** (`launch_wb`, `launch_ex = ex_req && !wb_req`, `launch_if` last). A small state machine `bus_state` (`ST_IDLE`, `ST_WAIT_IF`, `ST_WAIT_EX`, `ST_WAIT_WB`) remembers whose transaction is in flight.

```verilog
assign stall_pipeline = stall || wb_stalling || ex_stalling || if_stalling || m_stalling;
```

While any transaction is outstanding, or the multiply/divide unit is busy (`m_stalling`), the **whole pipeline freezes** (`stall_pipeline`). Most pipeline registers have `else if (!stall_pipeline)`, meaning they only advance when nothing is stalled.
`ex_done` / `wb_done` flags remember that a load or store already completed during a stall so it is not issued twice.

Bus signals out: `bus_req_valid`, `bus_req_write`, `bus_req_addr`, `bus_req_wdata`, `bus_req_wstrb[3:0]`; in: `bus_rsp_valid`, `bus_rsp_rdata`, `bus_rsp_error`.

## 8. Load and store alignment (the WB stage)

Memory is accessed in 32-bit words, but RISC-V has byte (`SB`/`LB`), half-word (`SH`/`LH`) and word (`SW`/`LW`) operations.

**Stores:** replicate the data and choose **byte strobes**:

| Instruction | `wb_write_data` | `wb_write_byte` |
| --- | --- | --- |
| `SB` | the low byte repeated 4 times | one bit set by address bits [1:0] (`0001`, `0010`, `0100`, `1000`) |
| `SH` | the low half repeated twice | `0011` or `1100` by address bit 1 |
| `SW` | the whole word | `1111` |

**Loads:** pick the right byte/half from the returned word by `wb_mem_address[1:0]` and either **sign-extend** (`LB`, `LH`) or **zero-extend** (`LBU`, `LHU`); `LW` returns the word.

## 9. Exceptions

```verilog
exception <= illegal_inst || fetch_pc[1:0] != 0 || (bus_rsp_valid && bus_rsp_error);
```

Illegal instruction, misaligned PC, or a bus error sets `exception` (one bit; in this design the output is not connected: the supervisor just keeps running).

## 10. Worked example: `lw t0, 4(s0)`

`s0 = 0x4000_0000` (LOB base). The instruction reaches EX: `ex_mem_address = s0 + 4 = 0x4000_0004` (STATUS). `ex_mem_to_reg = 1`, so `ex_req`. If the bus is free, a read is sent; `bus_state = ST_WAIT_EX`; the pipeline stalls until `bus_rsp_valid`; the word returns through `bus_rdata_reg`; in WB it is `LW`-aligned and written to `t0`; the stall clears.

## 11. "What if"

- **A taken branch?** The two following instructions are discarded (`wb_stall_first/second`): 2-cycle penalty.
- **A load immediately followed by a use of its result?** The consumer waits until the load completes, because the pipeline stalls for the whole bus transaction. Forwarding then takes the load data from WB.
- **A store and an instruction fetch at the same time?** The store wins (higher priority); the fetch is delayed one transaction.
- **A multiply?** `ex_m` starts `rv32m_unit`; `m_stalling` freezes the pipeline until `m_done`.
