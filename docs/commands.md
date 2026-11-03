# Commands

Run everything from the repository root. You need Icarus Verilog and Python 3
for tests, Vivado 2026.1 for bitstreams,
and an RV32IM GNU toolchain only if you rebuild firmware.

## Tests

```bash
./sim/run_ci_tests.sh                 # all Icarus testbenches (about 2 minutes)
./sim/integration/run_system_top.sh   # same full-system test under Vivado XSim
python3 -m unittest discover -s tools/tests # host tools (dashboard, readback, feed)
```

To run one testbench, copy its `iverilog ... && vvp` line from
`sim/run_ci_tests.sh`. Output goes to `build/ci_sim/` (ignored by Git).

## Firmware

```bash
python3 firmware/lob_test/build_firmware.py   # supervisor CPU -> imem.hex, dmem.hex
python3 firmware/kitty_ui/build.py            # VGA CPU -> kitty_ui.hex
python3 firmware/kitty_ui/build_font.py                       # font -> kitty_font.hex
```

The generated `.hex` files are committed because the FPGA build loads them.

## Bitstream

```bash
vivado -mode batch -source fpga/build_bitstream.tcl
FPGA_BUILD_PROFILE=fast vivado -mode batch -source fpga/build_bitstream.tcl
```

Optional environment variables: `FPGA_BUILD_DIR` (output folder, default
`build_system/`), `FPGA_MAX_THREADS` (1 to 4). The `.bit` file is written only
if routed setup and hold timing pass. Check:

```bash
rg 'WNS\(ns\)|WHS\(ns\)' $FPGA_BUILD_DIR/post_route_timing.rpt
```

## Program and test on the board

```bash
vivado -mode batch -source fpga/program_fpga.tcl -tclargs path/to/top_system.bit
python3 tools/order_journey.py --uart-port /dev/ttyUSB1 --interval 5.5 --count 10

```

The FPGA only receives Ethernet; it never answers ARP. For a direct cable, set
a fixed IP on the laptop's Ethernet port and pass `--target-ip` with that
subnet's broadcast address. The advanced demo is in
[order_journey_advanced_demo.md](order_journey_advanced_demo.md).
