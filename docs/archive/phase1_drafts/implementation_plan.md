# Phase 3: Standard CPU System Bus Interface

This plan introduces a simple custom synchronous single-outstanding-transaction bus to replace the CPU's direct memory connections, preserving all RV32I behavior.

## Proposed Changes

### Bus Protocol & State Machine
The bus will have the following signals:
`bus_req_valid`, `bus_req_write`, `bus_req_addr`, `bus_req_wdata`, `bus_req_wstrb`
`bus_rsp_valid`, `bus_rsp_rdata`, `bus_rsp_error`

The CPU will act as the single bus master, multiplexing Instruction Fetch (IF) and Data Memory (MEM) requests. A state machine in `cpu_core.v` will arbitrate:
- **Priority**: MEM requests (Loads/Stores from EX stage) take priority over IF requests.
- **States**: `ST_IDLE`, `ST_WAIT_IF`, `ST_WAIT_MEM`.
- **Stalls**: The pipeline stalls if a MEM request is pending (until `bus_rsp_valid` arrives), or if an IF request is delayed.
- **Buffering**: If an IF response arrives exactly when a MEM request stalls the pipeline, the fetched instruction is saved in a 1-entry `inst_buffer` so it is not lost.

### `rtl/cpu/core/cpu_core.v`
- [MODIFY] Remove direct memory ports (`inst_mem_address`, `dmem_read_address`, etc.) and replace with the unified bus interface.
- [MODIFY] Add the bus state machine and arbitration logic.
- [MODIFY] Move STORE alignment logic from WB stage to EX stage to drive `bus_req_wdata` directly.
- [MODIFY] Move LOAD alignment logic from WB stage to EX stage. The aligned data will be latched into a new `wb_load_data` pipeline register when the MEM response arrives, simplifying WB stage.

### `rtl/cpu/core/sys_bus_interconnect.v`
- [NEW] Create an interconnect that takes the CPU's bus request and routes it to either `imem_slave` (address `0x00000000`) or `dmem_slave` (address `0x20000000`).
- Return `bus_rsp_error = 1` for unmapped addresses.

### `rtl/cpu/core/imem_slave.v`
- [NEW] Wrapper around the existing `instr_mem.v` that implements the bus slave protocol (1-cycle latency).

### `rtl/cpu/core/dmem_slave.v`
- [NEW] Wrapper around the existing `data_mem.v` that implements the bus slave protocol.
- Includes a parameter to artificially delay responses for verification.

### `rtl/cpu/core/top_fpga.v`
- [MODIFY] Instantiate `sys_bus_interconnect.v`, `imem_slave.v`, and `dmem_slave.v` instead of direct memory instantiations.

## Verification Plan
1. **Differential Testing**: Run all 5 test programs against `phase2-refactored` and compare results (PC, registers, memory writes).
2. **Artificial Delay**: Test with a delayed `dmem_slave` to ensure the CPU stalls correctly and handles multi-cycle transactions safely.
