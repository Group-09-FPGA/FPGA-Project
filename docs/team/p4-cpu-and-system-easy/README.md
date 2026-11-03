# Owner 4: CPU, bus, registers, board indicators and the top level  (difficulty: easy to explain)

## Why this is the easiest part to defend

Almost all of it is **standard RISC-V** (the 3-stage RV32IM pipeline is the course design extended with multiply/divide and a bus), plus a few simple register blocks.
Examiners can ask about processor concepts you already know from lectures (pipeline, hazards, forwarding, MMIO), and you can reason from first principles.

## Your 30-second pitch

> "I own the RISC-V supervisor and everything around it: the 3-stage RV32IM CPU, the bus that connects it to memories and peripherals, the register interfaces
> to the order book and the network counters, the firmware that enables the book, and the board indicators: the LEDs and the seven-segment display.
> I also own the top-level wiring file, which only connects the other owners' blocks together.
> The CPU is not in the order data path, but it is required: until its firmware writes `1` to the control register, the order book accepts nothing."

## Your modules

| Module | File | Lines | One-line job |
| --- | --- | --- | --- |
| `cpu_core` | `rtl/cpu/core/cpu_core.v` | 404 | the 3-stage RV32IM pipeline and its bus master |
| `decoder`, `alu`, `branch_unit`, `reg_file` | `rtl/cpu/core/` | 73 / 28 / 25 / 34 | instruction decode, arithmetic, branch compare, 31 registers |
| `forwarding_unit`, `hazard_unit` | `rtl/cpu/core/` | 34 / 29 | data forwarding; flush after a taken branch |
| `rv32m_unit` | `rtl/cpu/core/rv32m_unit.v` | 204 | multiply (pipelined) and divide (iterative) |
| `sys_bus_interconnect` | `rtl/cpu/core/sys_bus_interconnect.v` | 180 | address decode and routing |
| `imem_slave`, `dmem_slave`, `memory.v` | `rtl/cpu/core/` | 36 / 72 / 89 | the 4 KiB instruction and data memories |
| `lob_mmio_slave` | `rtl/bus/lob_mmio_slave.v` | 233 | the order book's register window |
| `net_mmio_slave` | `rtl/bus/net_mmio_slave.v` | 137 | the network counters' register window |
| `cpu_system` | `rtl/cpu/cpu_system.v` | ~150 | wraps all of the above, plus the system register window |
| `seven_seg_driver` | `rtl/cpu/core/seven_seg_driver.v` | 174 | 8-digit multiplexed display |
| `board_status` | `rtl/top/board_status.v` | 66 | LED meanings and seven-segment source selection |
| `top_system` | `rtl/top/top_system.v` | 265 | only wires the subsystems together |
| firmware | `firmware/lob_test/firmware_monitor.s` | ~60 | the supervisor program |

## Tests you can run live

```bash
tb_cpu_core          # full pipeline, forwarding, branch flush, multiply/divide, memory bus
tb_rv32m_unit        # multiplier/divider corner cases (divide by zero, overflow, signed/unsigned)
tb_rv32m_pipeline    # stalls and forwarding around M instructions
tb_bus_error         # unmapped bus access gives an error response
tb_lob_mmio_config   # configuration registers: writable only before any event
tb_seven_seg_decimal # decimal rendering on the 7-segment display
tb_system_top        # the whole chip: Ethernet + keyboard orders; LEDs 0x203d, 7-segment checked
```

## Reading order

1. [00-system-in-10-minutes](../00-system-in-10-minutes.md)
2. [01-the-system-from-my-seat](01-the-system-from-my-seat.md)
3. [02-cpu-core-and-pipeline](02-cpu-core-and-pipeline.md)
4. [03-cpu-units](03-cpu-units.md)
5. [04-bus-memories-and-mmio](04-bus-memories-and-mmio.md)
6. [05-firmware-board-and-top-level](05-firmware-board-and-top-level.md)
7. [06-viva-qa](06-viva-qa.md)

## The facts you must be able to state without looking

1. **3-stage pipeline**: fetch/decode (IF/ID), execute (EX), write-back (WB). 32-bit RISC-V, **I + M** extensions.
2. **One bus**, one transaction at a time, priority **store > load > instruction fetch**; the pipeline stalls while a transaction is pending.
3. **Address map**: instruction RAM `0x0000_0000`, data RAM `0x2000_0000`, LOB `0x4000_0000`, network `0x5000_0000`, UART `0x6000_0000`, system `0x7000_0000`; anything else gives a **bus error**.
4. Memories are **1024 words = 4 KiB** each, loaded from `imem.hex` / `dmem.hex` at configuration time.
5. The firmware does three things: wait for init, wait for config, then **write `1` to `CTRL`** and loop publishing a **coherent snapshot**.
6. Reading `SNAP_BID_P` **freezes** the four best bid/ask values together (atomic snapshot).
7. Config registers (price base, tick, locate) are writable **only before the first event** and while the book is disabled.
