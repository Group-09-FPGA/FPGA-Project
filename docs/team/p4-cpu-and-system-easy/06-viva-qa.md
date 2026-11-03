# Viva questions and model answers (owner 4)

## A. The CPU

**1. What CPU do you have?** A 3-stage 32-bit RISC-V, RV32IM (integer base plus multiply/divide), with a simple shared bus.

**2. Name the three stages.** IF/ID (fetch and decode), EX (register read, ALU, branch, multiply/divide start, load request), WB (register write, store request, load/store alignment).

**3. How are data hazards handled?** With **forwarding**: if the instruction in WB writes a register that EX needs, the WB value is used directly instead of waiting for the register file.

**4. How are control hazards handled?** After a taken branch or jump, `hazard_unit` suppresses the next two in-flight instructions (a 2-cycle penalty); there is no branch predictor.

**5. What happens on a load?** The load request goes out on the shared bus from EX; the pipeline stalls until `bus_rsp_valid`; in WB the word is aligned (byte/half/word) and sign- or zero-extended and written to the register.

**6. Why is there a skid buffer (`if_buf`)?** If an instruction returns from memory in the same cycle the pipeline stalls, it must be saved; otherwise it would be lost.

**7. How does the bus decide between a fetch and a load/store at the same time?** Priority: **store > load > instruction fetch**.

**8. How does multiply work, and how long does it take?** A 3-stage pipelined multiplier: register operands, multiply into a 66-bit product, select high or low 32 bits. About 3 cycles, mapped onto the FPGA's DSP blocks. The pipeline stalls while it runs.

**9. How does divide work?** A 32-iteration restoring divider, one quotient bit per cycle; signed operations work on absolute values and fix signs at the end.

**10. What are the divide corner cases?** Divide by zero: `DIV`/`DIVU` return all ones, `REM`/`REMU` return the dividend. Overflow (`0x80000000 / −1`): `DIV` returns `0x80000000`, `REM` returns 0.

## B. The bus and registers

**11. What is MMIO?** Hardware registers accessed by address with normal load/store instructions; the interconnect routes the address to the owner of that range.

**12. What is the address map?** Instruction RAM `0x0000_0000`, data RAM `0x2000_0000`, LOB registers `0x4000_0000`, network counters `0x5000_0000`, UART `0x6000_0000`, system `0x7000_0000`.

**13. What if the CPU accesses an unmapped address?** The interconnect generates its own error response (and `cpu_rsp_error`), so the CPU never hangs. `tb_bus_error` verifies this.

**14. Why is the memory decoded to 4 KiB and not 256 MiB?** So addresses above the real size do not silently alias back into the memory.

**15. What is the atomic snapshot and why is it needed?** Reading bid price, bid quantity, ask price and ask quantity takes four bus transactions; the book could change between them. Reading `SNAP_BID_P` copies all four at once into holding registers, and the following reads return that consistent set.

**16. Why are the price registers write-protected after events start?** Stored price indexes are meaningful only relative to base and tick; changing them under a live book would reinterpret every order. Writes are accepted only while the book is disabled and no event has been counted.

## C. What the CPU does for the system

**17. What does your firmware do?** Waits for `init_done`, waits for `config_ready`, writes 1 to `CTRL`, then loops copying status, error, network counters and a consistent best-bid/ask snapshot into data RAM.

**18. Is the CPU in the order path?** No. Orders go network/keyboard → FIFO → arbiter → `lob_core`. But the CPU is **required**: until it writes `CTRL`, `run_enable` is 0 and no order is accepted.

**19. What if the CPU crashes?** The book continues to run if already enabled. A CPU fault cannot corrupt the book since the CPU has no write access to its memories.

**20. What if the CPU never enables the book?** `event_ready` stays low; the FIFOs fill and the network side will eventually overflow and flag feed-loss.

**21. Why does the firmware wait for `config_ready`?** So the price base and tick have reached the Ethernet clock domain before any event is accepted; otherwise the first event could be converted with stale values.

## D. Board and top level

**22. Which switches are used and why SW14/SW15?** They select the seven-segment source. SW0 and SW1 are not working on this board, so the constraints map `sw[0]`/`sw[1]` to SW14/SW15.

**23. How does a seven-segment display show eight digits with seven wires?** Time multiplexing: one digit at a time for 1 ms each (125 Hz full refresh), each digit's anode enabled in turn.

**24. How is a binary number shown in decimal?** Double dabble: 32 steps of "add 3 to any digit ≥ 5, then shift", producing BCD digits; the display updates only after a full conversion.

**25. What does LED 9 mean? LED 10? LED 11?** An event is waiting for the book; a sequence gap was seen; CRC errors exist.

**26. What is in `top_system`?** No logic: the instantiation and wiring of the subsystems, plus one counter.

**27. How many clock domains and which?** Four: `eth` (50 MHz), `core` (50 MHz), `ui` (25 MHz), `pixel` (74.25 MHz).

**28. What happens on reset?** The button and MMCM lock produce per-domain resets that assert immediately and release synchronously; all memories re-initialise (the price RAM takes 16,384 clocks), then the CPU re-enables the book.

## E. Cross-over

**29. Who consumes your configuration?** Owner 1's ITCH decoder (via `u_cfg_cdc`), owner 2's BBO price calculation, owner 3's keyboard price divider, and the VGA Status page ("Base" and "Tick").

**30. Where do the LEDs get their data?** From owners 1, 2 and 3's signals (`net_diag`, `lob_*` status, `evt_valid`).

**31. How does the monitor relate to your registers?** The display's Status page shows book validity, error code, active orders, completed events, pipeline counters and the price configuration, which are the same quantities your CPU reads, delivered to the display by owner 5's clock-crossing blocks.

## F. Tests

**32. How do you test the CPU?** `tb_cpu_core` runs a program through the pipeline (forwarding, branches, loads/stores, M instructions) and checks results; `tb_rv32m_unit` and `tb_rv32m_pipeline` test the M unit alone and in the pipeline; `tb_bus_error` tests unmapped addresses; `tb_lob_mmio_config` tests the config write protection; `tb_seven_seg_decimal` tests the display.

**33. What does the full-system test prove about your part?** The firmware enables the book, the stored snapshots show the expected bid and ask (`dmem[0]`, `dmem[2]`), the LED word is `0x203d` and the seven-segment output is correct.
