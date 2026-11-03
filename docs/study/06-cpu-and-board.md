# Chapter 6: The CPU, the bus, and the board indicators

Files: `rtl/cpu/cpu_system.v`, `rtl/cpu/core/*.v`, `rtl/bus/lob_mmio_slave.v`,
`rtl/bus/net_mmio_slave.v`, `rtl/top/board_status.v`, firmware in
`firmware/lob_test/`.

## Why have a CPU at all?

The order book does all the real work in dedicated hardware. The CPU is a small
**supervisor**. It does three things:

1. waits for initialization and configuration, then **enables** the order book (nothing is accepted
   until it does);
2. keeps copying status and a consistent best-bid/ask snapshot into its own memory;
3. owns the configuration registers (price base, tick, stock locate) that it can change before any
   order arrives.

*Analogy:* a building manager who unlocks the front door in the morning and then walks the floors
writing down readings. The shop (order book) runs without the manager's help once it is open.

## `cpu_system`: the CPU and everything it can talk to

`cpu_system` is instantiated once in `top_system` as `u_cpu_system`. It bundles:

| Instance | Role |
| --- | --- |
| `u_cpu` (`cpu_core`) | the processor |
| `u_interconnect` (`sys_bus_interconnect`) | decodes addresses and routes bus requests |
| `u_imem` (`imem_slave`) | 4 KiB instruction memory |
| `u_dmem` (`dmem_slave`) | 4 KiB data memory (firmware workspace) |
| `u_lob_mmio` (`lob_mmio_slave`) | registers for the order book |
| `u_net_mmio` (`net_mmio_slave`) | read-only network counters |
| (inline `always`) | the tiny "system" register window |
| UART window | passes the UART address range out to `uart_system` |

### Address map

| Base | Device | Notes |
| --- | --- | --- |
| `0x0000_0000` | instruction memory | 4 KiB |
| `0x2000_0000` | data memory | 4 KiB |
| `0x4000_0000` | LOB registers | see below |
| `0x5000_0000` | network counters | read-only |
| `0x6000_0000` | UART | `uart_telemetry` window |
| `0x7000_0000` | system | `0x00` = {SW15, SW14}; `0x04` = clock locked |
| anything else | bus error | `err_rsp_valid` returns an error response |

## `cpu_core`: a 3-stage RV32IM pipeline

RV32IM = 32-bit RISC-V with the multiply/divide extension (**M**).

*Analogy:* an assembly line. While one instruction is being executed, the next one is already being fetched.

| Stage | What happens | Where in the file |
| --- | --- | --- |
| **IF** (fetch) | `fetch_pc` addresses instruction memory; a 1-word buffer (`if_buf`, "skid buffer") holds the result | "FETCH STAGE" |
| **ID** (decode) | `decoder` splits the instruction into register numbers, immediate value, control flags | "DECODE STAGE" |
| **EX** (execute) | register file read + forwarding, ALU, branch decision, multiply/divide | "EXECUTE STAGE" |
| **WB** (write back) | load/store alignment, register write, bus data | "WRITEBACK STAGE" |

### Small units it uses

| Module | Job |
| --- | --- |
| `decoder` | instruction bits → `rs1/rs2/rd`, immediate, `alu`, `branch`, `jal`, `mem_write`, `mem_to_reg`, `m_op`, `illegal_inst` |
| `reg_file` | 31 registers (x0 is always 0); two read ports, one write port |
| `forwarding_unit` | if the instruction before just computed what I need, take it directly instead of waiting for the register write |
| `alu` | add/sub, shifts, compares, xor/or/and |
| `branch_unit` | compares two operands for `BEQ/BNE/BLT/BGE/BLTU/BGEU` |
| `rv32m_unit` | multiply (3-stage pipelined) and divide (iterative FSM `IDLE/MULT/DIV/DONE`); raises `busy`/`done` and stalls the pipeline |
| `hazard_unit` | after a taken branch, throws away the next two instructions (`wb_stall_first/second`) |

### The bus master inside `cpu_core`

The CPU reaches instruction memory, data memory and all peripherals over **one** bus, one transaction
at a time. `bus_state` (`IDLE`, `ST_WAIT_IF`, `ST_WAIT_EX`, `ST_WAIT_WB`) records whose request is in
flight. Priority: stores (WB) first, then loads (EX), then instruction fetch (IF). When a transaction is
pending the pipeline stalls (`stall_pipeline = wb_stalling || ex_stalling || if_stalling || m_stalling`).

### `sys_bus_interconnect`

One `slave_sel` register remembers who received the current request. `sel_*` wires decode the address
bits. A request is accepted when `req_en` (no transaction in flight, or the previous one is responding).
The response mux then forwards the selected slave's `rsp_valid`/`rsp_rdata`. Unmapped addresses
generate a one-cycle error response so the CPU never hangs.

### `imem_slave`, `dmem_slave`, `memory.v`

Wrappers around the instruction/data RAMs (1024 words each). `memory.v` loads `imem.hex` / `dmem.hex`
(`$readmemh`) so the firmware is baked into the bitstream. Instruction memory is read-only.

## `lob_mmio_slave`: the LOB's control panel

**Registers** (offset from `0x4000_0000`):

| Off | Name | Notes |
| --- | --- | --- |
| `00` | CTRL | bit 0 = `accel_enable`; writing bit 2 requests a snapshot |
| `04` | STATUS | bit0 init done, 1 book valid, 2 busy, 3 error latched, 4 bid valid, 5 ask valid, 6 event ready, **7 config ready** |
| `08` | ERROR | error code, bit 16 valid |
| `0C` | ACTIVE_ORD | live order count |
| `10`..`20` | SNAP_* | **atomic snapshot**: reading `SNAP_BID_P` freezes bid/ask price and qty together |
| `24` / `28` / `2C` | PRICE_BASE / TICK / LOCATE | writable only before any event and while disabled |
| `30` | EVT_COUNT | events processed |
| `34`..`40` | LIVE_* | un-frozen live values |
| `44` | SPREAD | ask − bid |

**Why a snapshot?** The CPU reads best bid price, then bid qty, then ask price: three separate bus reads. If an event
changed the book in between, the three would not belong together. Reading the first register latches all four
values at once (`snap_trigger`), so the next three reads are consistent.

**Always blocks:** one counts events; one latches the snapshot; one handles register writes (`accel_enable`, configuration);
one registers the read address and `bus_rsp_valid`; one `always @(*)` is the read multiplexer.

## `net_mmio_slave`: the network counters

Read-only. It exposes `net_diag` words: `00` rx frames, `04` CRC errors, `08` Mold messages, `0C` sequence gaps,
`10` length errors, `14` PHY errors, `18` overflow errors, `1C` Mold truncations, `20` status flags, `24` UDP length
errors, `28` UDP checksum errors. It exists as its own module to keep the big counter multiplexer away from the CPU's
critical timing path.

## The firmware (`firmware/lob_test/firmware_monitor.s`)

```
_start: set up pointers to LOB (0x4000_0000), data RAM, network (0x5000_0000)
wait_init:    loop until STATUS bit0 (init done)
wait_config:  loop until STATUS bit7 (config reached the ethernet clock domain)
              write 1 to CTRL        # enable_accel -> lob_core may now accept events
monitor:      copy STATUS, ERROR, net flags, counters into data RAM
              if book not valid: loop
              read SNAP_BID_P ... SNAP_FLAGS (consistent snapshot) and store; read ACTIVE_ORD; repeat
```

`build_firmware.py` assembles it with the RISC-V toolchain into `imem.hex` and `dmem.hex`.

## `seven_seg_driver` and `board_status`

`board_status` (in `rtl/top/`) is a pure output block: it drives the 16 LEDs and picks the 32-bit value shown on the
8-digit display (`SW14/SW15`: best bid, best ask, orders + events, or frames + CPU program counter).

`seven_seg_driver` does the display mechanics:
- **Multiplexing:** only one digit is lit at a time, cycling at about 1 kHz per digit; your eye sees all eight.
- **Binary → decimal:** a 32-step double-dabble (same idea as `bin_to_decimal`).
- **Formats:** hex, eight decimal digits, or two 4-digit decimal fields; `point_mask` lights chosen decimal points
  (the price modes put a point after four digits: `$XXXX.XXXX`).

### LED meanings (`board_status`)

| LED | Meaning |
| --- | --- |
| 0 | clocks locked |
| 1 | Ethernet PHY released from reset |
| 2 | book initialized |
| 3 | book valid |
| 4 / 5 | bid present / ask present |
| 6 | order book busy |
| 7 | error |
| 8 | Ethernet carrier detected |
| 9 | an event is waiting |
| 10 | sequence gap seen |
| 11 | any CRC errors |
| 15:12 | low 4 bits of the error code, or of the order count |
