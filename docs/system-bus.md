# Phase 3: Standard CPU System Bus Interface Specification

## 1. Overview & Architectural Goals

Phase 3 introduces a standard, synchronous, single-outstanding-transaction internal system bus for the RV32I processor while strictly preserving existing RV32I architectural behavior and 3-stage pipeline semantics (`IF+ID` -> `EX` -> `MEM+WB`).

Direct dual-port memory wiring between the CPU and memory modules has been decoupled into a structured bus topology consisting of:
- **Bus Master**: `cpu_core.v`
- **Bus Interconnect**: `sys_bus_interconnect.v` (Address decoder, request router, response multiplexer, default error responder)
- **Slave 0**: `imem_slave.v` (Instruction memory wrapper with 1-cycle read latency)
- **Slave 1**: `dmem_slave.v` (Data memory wrapper with parameterized multi-cycle latency `DELAY_CYCLES`)

---

## 2. Bus Signal Definitions

The system bus utilizes a fixed 32-bit data and byte-address width with active-high handshaking.

### 2.1 Request Channel (Master -> Slave)

| Signal | Width | Direction | Description |
|---|:---:|:---:|---|
| `req_valid` | 1 | Master -> Slave | Asserted by master to initiate a bus transaction. |
| `req_write` | 1 | Master -> Slave | `0` for read transaction, `1` for write transaction. |
| `req_addr` | 32 | Master -> Slave | 32-bit byte address for the transaction. |
| `req_wdata` | 32 | Master -> Slave | 32-bit write data payload (for writes). |
| `req_wstrb` | 4 | Master -> Slave | 4-bit byte write strobes (`wstrb[0]` = byte 0 ... `wstrb[3]` = byte 3). |

### 2.2 Response Channel (Slave -> Master)

| Signal | Width | Direction | Description |
|---|:---:|:---:|---|
| `rsp_valid` | 1 | Slave -> Master | Asserted for 1 cycle by slave to acknowledge transaction completion. |
| `rsp_rdata` | 32 | Slave -> Master | 32-bit read data payload (for reads). |
| `rsp_error` | 1 | Interconnect -> Master | Asserted when an unmapped address is accessed or an error occurs. |

---

## 3. Bus Protocol & Master Arbitration

### 3.1 Single-Outstanding-Transaction Rule
At most **one** bus transaction is active across the system interconnect at any time. The CPU does not issue a new transaction until the previous transaction completes (`rsp_valid == 1`).

### 3.2 Master Arbiter Priority
Inside `cpu_core.v`, memory operations originating from different pipeline stages are arbitrated with strict non-preemptive priority:
1. **WB Stage (Stores)**: Oldest instruction in the pipeline. Writes to data memory (`sw`, `sh`, `sb`). Highest priority.
2. **EX Stage (Loads)**: Middle instruction in the pipeline. Reads from data memory (`lw`, `lh`, `lb`, `lhu`, `lbu`).
3. **IF Stage (Instruction Fetch)**: Fetches the next instruction at `fetch_pc`.

### 3.3 Arbiter State Machine
The bus master controller transitions between 4 states:
- `ST_IDLE (2'b00)`: Bus is idle. Ready to launch the highest priority pending request.
- `ST_WAIT_IF (2'b01)`: Waiting for instruction fetch response from `imem_slave`.
- `ST_WAIT_EX (2'b10)`: Waiting for data memory read response from `dmem_slave`.
- `ST_WAIT_WB (2'b11)`: Waiting for data memory write acknowledgment from `dmem_slave`.

While in `ST_WAIT_EX` or `ST_WAIT_WB`, the pipeline stall signal (`stall_pipeline`) is asserted, freezing all pipeline registers and keeping request address and store data completely stable until completion.

---

## 4. 1-Word Instruction Skid Buffer

When an instruction fetch (`IF`) response completes at the exact same cycle that a downstream instruction in `EX` or `WB` requires data memory access, the CPU must stall the pipeline to service the data memory request.

To avoid dropping the fetched instruction or adding an unnecessary multi-word FIFO:
- A single 1-word holding register (`if_buf`) and valid bit (`if_buf_valid`) captures the incoming instruction if `stall_pipeline` is active.
- While `if_buf_valid` is asserted:
  - The decoder samples `if_buf`.
  - `fetch_pc` is held without incrementing.
  - No new `IF` transaction is launched on the bus.
- Once the pipeline stall releases, the buffered instruction advances cleanly into `ID/EX`, clearing `if_buf_valid` and resuming normal sequential fetches without any lost cycles or dropped instructions.
- If a branch or jump is taken (`branch_taken == 1`), `if_buf_valid` is immediately cleared to flush speculative instructions from the wrong execution path.

---

## 5. Bus Address Map

The 32-bit physical address space is partitioned as specified:

| Address Range | Destination | Size | Function |
|---|---|:---:|---|
| `0x0000_0000 - 0x0000_3FFF` | `imem_slave` | 16 KB | Instruction Memory (BRAM, Read-Only) |
| `0x2000_0000 - 0x2000_3FFF` | `dmem_slave` | 16 KB | Data Memory (BRAM, Read/Write Data & Stack) |
| `0xFFFF_0000 - 0xFFFF_FFFF` | `dmem_slave` (Alias) | 64 KB | Negative stack alias for standard uninitialized GCC stack frames |
| `0x4000_0000` | Reserved | - | LOB Hardware Accelerator (Phase 4+) |
| `0x5000_0000` | Reserved | - | Ethernet / ITCH Receiver |
| `0x6000_0000` | Reserved | - | UART Peripheral |
| `0x7000_0000` | Reserved | - | Timers & Board I/O |
| *All Other Addresses* | Error (`SEL_ERR`) | - | Returns `rsp_error = 1`, triggers CPU exception |

---

## 6. Transaction Timing Diagrams

### 6.1 Instruction Fetch (1-Cycle Read Latency)
```
Cycle:          0      1      2      3
clk:         __|--|__|--|__|--|__|--|__|
req_valid:   _______|------|____________
req_addr:    xxxxxxx|<PC>  |xxxxxxxxxxxx
rsp_valid:   ______________|------|_____
rsp_rdata:   xxxxxxxxxxxxxx|<INST>|xxxxx
bus_state:   [ IDLE ][ WAIT_IF ][ IDLE ]
```

### 6.2 Data Memory Store (1-Cycle Latency)
```
Cycle:          0      1      2      3
clk:         __|--|__|--|__|--|__|--|__|
req_valid:   _______|------|____________
req_write:   _______|------|____________
req_addr:    xxxxxxx|<ADDR>|xxxxxxxxxxxx
req_wdata:   xxxxxxx|<DATA>|xxxxxxxxxxxx
req_wstrb:   xxxxxxx|<STRB>|xxxxxxxxxxxx
rsp_valid:   ______________|------|_____
bus_state:   [ IDLE ][ WAIT_WB ][ IDLE ]
stall_pipe:  _______|------|____________
```

### 6.3 Multi-Cycle Delayed Read (DMEM_DELAY_CYCLES = 3)
```
Cycle:          0      1      2      3      4      5
clk:         __|--|__|--|__|--|__|--|__|--|__|--|__|
req_valid:   _______|------|________________________
req_addr:    xxxxxxx|<ADDR>|xxxxxxxxxxxxxxxxxxxxxxxx
rsp_valid:   ____________________________|------|___
rsp_rdata:   xxxxxxxxxxxxxxxxxxxxxxxxxxxx|<DATA>|xxx
bus_state:   [ IDLE ][ --------- WAIT_EX ------- ][IDLE]
stall_pipe:  _______|---------------------------|___
```

### 6.4 Unmapped Address Access (Error Response)
```
Cycle:          0      1      2      3
clk:         __|--|__|--|__|--|__|--|__|
req_valid:   _______|------|____________
req_addr:    xxxxxxx|0x3000|xxxxxxxxxxxx
rsp_valid:   ______________|------|_____
rsp_error:   ______________|------|_____
exception:   _____________________|------|__
```

---

## 7. Verification & Test Results

### 7.1 Benchmark Program Suite
Differential verification was executed against the Phase 2 baseline across all 5 benchmark workloads:

| Program | Architectural Results | Result | Notes |
|---|:---:|:---:|---|
| `addition` | `100, 2, 102` | **PASS** | 100% match on all register writes. |
| `fibo` | `10, 1, 2, 1, 3, 2, 4, 3, 5, 5, 6, 8, 7, 13, 8, 21, 9, 34, 10` | **PASS** | 100% match on all 19 loop writebacks. |
| `negative` | `4, 50, -46` | **PASS** | 100% match on signed ALU operations. |
| `sort` | Exactly 52 writeback operations | **PASS** | Perfectly sorts `{6, 3, 9}` into `{3, 6, 9}`. |
| `xor` | `170, 85, 255` | **PASS** | 100% match on bitwise operations. |

### 7.2 Delayed Slave Verification
The parameterized delay mechanism in `dmem_slave.v` was tested with artificial wait states:
- **`DELAY_CYCLES = 0`**: Passed all tests.
- **`DELAY_CYCLES = 1`**: Passed `addition` (`100, 2, 102`).
- **`DELAY_CYCLES = 3`**: Passed `addition` (`100, 2, 102`) and `fibo` (all 19 values).
- **Result**: Exactly one request and response per transaction, zero dropped loads, zero duplicated stores.

### 7.3 Unmapped Address Error Verification
A dedicated testbench (`tb_bus_error.v`) was simulated with an unmapped address access (`0x30000000`):
- `sys_bus_interconnect` cleanly routed to `SEL_ERR`.
- `cpu_rsp_error` asserted at cycle completion.
- `cpu_core` asserted `exception = 1` without pipeline deadlock.
- **Result**: PASS.

---

## 8. FPGA Synthesis & Resource Comparison

Both baseline and Phase 3 architectures were synthesized targeting the **Xilinx Artix-7 XC7A100T-1CSG324C** FPGA at **100 MHz** using Vivado 2026.1:

| Metric | Phase 2 Refactored | Phase 3 (System Bus) | Delta |
|---|:---:|:---:|:---:|
| **Slice LUTs** | 2537 | **2238** | **-299 (-11.8%)** |
| **Slice Registers (FF)** | 1298 | **1399** | +101 (+7.8%) |
| **Block RAM Tile** | 1 | **1** | 0 |
| **DSPs** | 0 | **0** | 0 |
| **Worst Negative Slack (WNS)** | +5.959 ns | **+5.959 ns** | 0.000 ns (Met) |
| **Worst Hold Slack (WHS)** | +0.140 ns | **+0.140 ns** | 0.000 ns (Met) |
| **Timing Violations** | 0 | **0** | All Met |

The bus interconnect and state controllers reduced overall combinational routing complexity, reducing Slice LUT utilization by **11.8%** while maintaining identical positive timing margins (+5.959 ns WNS at 100 MHz).
