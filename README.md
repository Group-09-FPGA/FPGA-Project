# FPGA Limit Order Book

Verilog-2001 market-data pipeline for the Nexys A7-100T: RMII Ethernet,
IPv4/UDP, MoldUDP64 and ITCH decoding, a clock-crossing event FIFO, a hardware
limit order book, and an RV32IM supervisor. UART, VGA, LEDs, and a seven-segment
display expose status. The Ethernet and core domains both run at 50 MHz.

The implementation is the code under `rtl/`. Older design reports and slides
are historical material; they do not define the current behavior. Ethernet
ingest, book operations, fail-stop, recovery by reprogramming, UART, and basic
LED/display behavior were checked on a physical board on 2026-10-24. Exact
book quantities, active counts, and IP/UDP checksum counters were also checked
with an extended UART build. VGA, a deliberately bad FCS on the physical link,
and CPU MMIO counter readback remain unverified on the physical board;
see [HARDWARE_VALIDATION.md](docs/HARDWARE_VALIDATION.md).

## Verify

From the repository root:

```bash
./sim/run_ci_tests.sh
./sim/integration/run_system_top.sh
python3 -m unittest discover -s tests
software_lob/.venv/bin/pytest software_lob/tests -q
```

The RTL suite checks protocol parsing, the FIFO, CPU corner cases, LOB
operations, and the Ethernet-to-book path. The accepted events in
`sim/golden/golden_vectors.json` are compared against the RTL; its rejected
duplicate order is checked for hardware fail-stop separately.

## Build

With Vivado 2026.1 available:

```bash
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

The sole full-system build location is `build_system/`. The script writes
`top_system.bit`, routed timing, utilization, DRC, and methodology reports there. It refuses
to generate a bitstream when setup or hold timing fails. This directory is
ignored by Git; run the script to reproduce it.

## Board bringup when hardware is available

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl
python3 tools/order_journey.py --target-ip 192.168.1.255 --uart-port /dev/ttyUSB1 --interval 10 --count 10
```

Program or reset the current trace-enabled bitstream to start with an empty
book. Use `--interval 1` for one order per second, or `--demo` for a clearly labelled
software walkthrough without hardware. Each UDP datagram contains one ITCH
message. The terminal displays the message bytes and waits for UART counters
from the RMII receiver, UDP parser, Mold decoder, ITCH decoder, event FIFO,
and LOB completion, then verifies the returned BBO, quantities, and order count.
This is also available from `python3 control_center.py` as menu item 3.

The FPGA does not answer ARP. Configure the host Ethernet interface on
`192.168.1.0/24` and use the subnet broadcast address for injection. Record
physical results using [HARDWARE_VALIDATION.md](docs/HARDWARE_VALIDATION.md).

## Layout

- `rtl/`: synthesizable system and CPU source.
- `sim/`: unit, integration, and golden-vector tests.
- `software/baremetal/lob_test/`: firmware source and memory initialization hex.
- `software_lob/`: Python reference model and tests.
- `vivado/scripts/`: full-system build and programming scripts.
- `docs/`: commands, validation record, and clearly marked historical material.
- `presentation/`: historical presentation source.

See [commands.md](docs/commands.md) for the short command reference and
[AUDIT_FOLLOWUP.md](docs/AUDIT_FOLLOWUP.md) for work that still needs evidence.
