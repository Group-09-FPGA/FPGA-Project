# FPGA Limit Order Book

A hardware limit order book on the Nexys A7-100T. Market-data packets come in
over Ethernet, are decoded in hardware (Ethernet → IPv4/UDP → MoldUDP64 →
ITCH) and update an on-chip order book. A small RV32IM CPU supervises. Results
show on a 1280×720 VGA screen and over UART, and orders can also be typed on
a USB keyboard. All RTL is Verilog-2001.

```
Ethernet → parse → ITCH decode → event FIFO ┐
USB keyboard → order form → local FIFO ─────┴→ arbiter → order book → VGA / UART
```

## Quick start

```bash
./sim/run_ci_tests.sh                    # RTL simulation suite
python3 -m unittest discover -s tests    # host-tool tests
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl   # bitstream
```

Needs Icarus Verilog, Python 3, and Vivado 2026.1 (bitstream only).
More commands: [docs/commands.md](docs/commands.md).

## Repository map

| Path | What is there |
| --- | --- |
| `rtl/` | All synthesizable Verilog (network, order book, CPU, keyboard, VGA, UART) |
| `sim/` | Unit tests, golden-vector tests, full-system integration test |
| `software/baremetal/` | Firmware for the supervisor CPU (`lob_test`) and the VGA CPU (`kitty_ui`) |
| `tools/`, `tests/` | Host tools: order sender, UART dashboard, RAM readback, and their tests |
| `constraints/`, `vivado/` | Pin/timing constraints, build and programming scripts |
| `docs/` | Documentation (start at [docs/README.md](docs/README.md)) |

Build outputs (`build*/`, bitstreams, Vivado logs) are ignored by Git.

## Status

* Simulation: all RTL testbenches and the host-tool tests pass.
* Board (checked 2026-10-24 and 2026-11-02): Ethernet ingest, order book
  operations, fail-stop, UART readback and the cold-attach dashboard work.
* Keyboard/720p image: builds and meets timing; UART and Ethernet work on the
  board, but the keyboard was not detected in the first hardware try, so
  keyboard input and the VGA picture are **not yet verified on hardware**.

Details and evidence: [docs/HARDWARE_VALIDATION.md](docs/HARDWARE_VALIDATION.md).

## Where to read next

* How it works: [docs/architecture.md](docs/architecture.md)
* Modules and register maps: [docs/rtl_reference.md](docs/rtl_reference.md)
* Keys and screens: [docs/keyboard_vga_controls.md](docs/keyboard_vga_controls.md)
