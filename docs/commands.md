# Commands

Run from the repository root unless a command changes directory. Vivado 2026.1,
Icarus Verilog, Python, and `uv` are needed for the corresponding steps.

## Tests

```bash
./sim/run_ci_tests.sh
./sim/integration/run_system_top.sh
python3 -m unittest discover -s tests
cd software_lob && uv sync --extra dev && uv run pytest
```

The Icarus and XSim scripts create ignored, disposable simulation output.
The Python model continues after rejected events; the hardware with fail-stop
enabled invalidates the book.

## Firmware

```bash
python3 software/baremetal/lob_test/build_firmware.py
```

The committed `imem.hex` and `dmem.hex` initialize the CPU memories. The
firmware builder keeps ELF and binary intermediates in a temporary directory.

## Final system build

```bash
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

The only retained full-system build is `build_system/`. Review:

```bash
rg 'WNS\(ns\)|WHS\(ns\)|All user specified timing constraints' build_system/post_route_timing.rpt
sed -n '20,45p' build_system/post_route_drc.rpt
```

`build_system/top_system.bit` is generated only when routed setup and hold
checks pass. A timing pass does not establish operation on a physical board.

## Physical run

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl
python3 tools/order_journey.py --uart-port /dev/ttyUSB1 --interval 10 --count 10
```

The FPGA has a receive-only Ethernet interface and does not answer ARP. The
script detects the active Wi-Fi broadcast by default. The FPGA must be on the
same LAN; for a direct link, configure the host Ethernet interface and pass
its broadcast address with `--target-ip`. Follow
[HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md) when a board is available.
