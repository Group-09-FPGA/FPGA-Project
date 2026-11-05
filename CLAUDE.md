# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Verilog-2001 market-data pipeline for the Nexys A7-100T: RMII Ethernet → IPv4/UDP → MoldUDP64 → ITCH decode → async event FIFO → hardware limit order book (LOB), supervised by an RV32IM softcore. UART, VGA (a read-only 1280×720 status UI; keyboard only changes pages), LEDs and 7-seg expose status. **The RTL under `rtl/` is the source of truth**; most of `docs/` (architecture.md, reports, slides, `presentation/`) is explicitly historical and may contradict the code. Use `docs/commands.md`, `docs/HARDWARE_VALIDATION.md` and `docs/keyboard_vga_controls.md` for current behavior. Sources must be plain `.v`/`.vh` Verilog-2001 (CI rejects `.sv`/`.svh`).

## Commands

Run from the repo root. Tools: Icarus Verilog, Python 3, Vivado 2026.1 (build/program only).

```bash
./sim/run_ci_tests.sh                      # whole Icarus suite (also rebuilds kitty_ui firmware hex first)
./sim/integration/run_system_top.sh        # Ethernet-to-book integration under XSim
python3 -m unittest discover -s tools/tests      # Python feed/dashboard/readback tests
python3 -m unittest discover -s tools/tests -p test_mixed_input.py # single Python test module

```

There is no per-test flag in `run_ci_tests.sh`; each testbench is a `run_test` entry with its own `iverilog -g2001 -s <tb_top> ... && vvp -N` pair. To run one, copy that entry's command (output goes in `build/ci_sim/`), e.g.:

```bash
iverilog -g2001 -s tb_keyboard_controls -o /tmp/kc.vvp rtl/ui/keyboard_controls.v sim/unit/tb_keyboard_controls.v && vvp -N /tmp/kc.vvp
```

Firmware (committed hex files initialize CPU memories; CI checks `imem.hex` matches source; needs RV32IM GNU toolchain):

```bash
python3 firmware/lob_test/build_firmware.py   # supervisor firmware -> imem.hex/dmem.hex
python3 firmware/kitty_ui/build.py            # VGA presentation firmware -> kitty_ui.hex
python3 firmware/kitty_ui/build_font.py                       # kitty_font.hex
```

FPGA build / program:

```bash
vivado -mode batch -source fpga/build_bitstream.tcl          
FPGA_BUILD_PROFILE=fast vivado -mode batch -source fpga/build_bitstream.tcl
vivado -mode batch -source fpga/program_fpga.tcl [-tclargs path/to/top_system.bit]
```

The bitstream is only written if routed setup/hold pass; check `post_route_timing.rpt` / `post_route_drc.rpt`. `FPGA_MAX_THREADS=1..4` limits Vivado workers on memory-constrained machines. `build*/` dirs and `*.bit` are gitignored; several dated `build_*_20261102/` dirs hold preserved known-good bitstreams (the cold-attach dashboard needs `build_snapshot_20261102`).

Board tools: `python3 tools/order_journey.py --uart-port /dev/ttyUSB1 --interval 5.5 --count 10` . The FPGA is receive-only Ethernet and never answers ARP; the sender broadcasts, so for a direct link pass `--target-ip` with the subnet broadcast address.

## Architecture

Top level is `rtl/top/top_system.v`; it only wires subsystem modules (`net_ingest`, `order_merge`, `cpu_system`, `uart_system`, `display_system`, `book_views`, `status_to_ui`, `board_status`). Clock-crossing instances must keep a `_cdc` suffix and the event FIFO the name `u_event_fifo`: the XDC timing exceptions match on those names. Key structure:

- **Two 50 MHz domains, not one**: Ethernet (`rst_eth_n`, RMII clock) and core (`rst_core_n`), plus a VGA domain (`rst_vga_n`). All crossings go through `rtl/common/async_event_fifo.v` (256-bit canonical events) or `rtl/common/config_cdc.v` (bundled-value CDC for counters/config/diagnostics/readback buses of arbitrary `WIDTH`). Add new cross-domain signals via these, not ad-hoc synchronizers.
- **Ingest path** (`rtl/ethernet`, `rtl/network`, `rtl/itch`): `rmii_rx` → `net_parser` (IP/UDP, checksum and length counters) → `moldudp64_decoder` (gap ⇒ fail-stop) → `itch_decoder` → canonical 256-bit event (layout in `rtl/lob/lob_defines.vh`; mirrored by the Python packer in `tests`/`sim/golden`).
- **Order source**: Ethernet only. The VGA/keyboard (`ps2_keyboard.v` → `keyboard_controls.v`) is read-only page navigation; `order_merge.v` forwards network events and records journal metadata.
- **LOB** (`rtl/lob/`): `lob_core` composes event decoder, slot table, free list, hash table, price RAM, occupancy bitmaps and BBO. With fail-stop enabled, a rejected event (e.g. duplicate order) invalidates the book.
- **CPU** (`rtl/cpu/core/`): 3-stage RV32IM with a bus interconnect, `imem_slave`/`dmem_slave`, and MMIO slaves (`rtl/bus/lob_mmio_slave.v`, `net_mmio_slave.v`). It is out-of-band supervisor/telemetry, not on the order fast path. 
- **Display/telemetry**: `rtl/display/kitty_ui_cpu.v` is a second small CPU running `firmware/kitty_ui` firmware that reads book RAM/history (`lob_display_journal`, `lob_level_order_count`) and feeds `kitty_video.v`. `rtl/telemetry/uart_telemetry.v` and `uart_readback.v` implement the UART protocol (e.g. `B` occupied-set queries, `E` 99-digit journal records) that `tools/fpga_readback.py` and `order_book_dashboard.py` parse — host tools and UART RTL must change together, and a protocol change needs a new bitstream.
- **Verification layers**: unit testbenches in `sim/unit/`; golden vectors in `sim/golden/` (`golden_vectors.json`, generated RTL vector files compared via `tb_lob_golden`/`tb_lob_random`); full-path test in `sim/integration/tb_system_top.v` (compiles every `rtl/**/*.v`).

## Docs

`docs/architecture.md` (overview) and `docs/rtl_reference.md` (modules, event layout, register maps) describe the current design; keep them in sync with RTL changes.

## Gotchas

- `sim/run_ci_tests.sh` hard-codes file lists per testbench; when adding or moving an RTL module, update the matching `run_test` entry. The CI Verilator lint uses `find rtl`, so no list needs editing there.
- Simulation-only code is gated by `` `ifdef SIMULATION `` (`-DSIMULATION` in integration/preview builds).
- Physical-board validation status (what is and isn't verified on hardware) is recorded in `docs/HARDWARE_VALIDATION.md`; update it rather than claiming hardware results elsewhere.
