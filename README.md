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

On 2026-11-02, the UART RAM-readback candidate was programmed and exercised
through a direct USB Ethernet link. All 13 advanced events were verified by
board UART; the dashboard reported 53 matching RAM reads and zero mismatches.
A later snapshot build was also programmed: a dashboard started after two
orders rebuilt the book and retained charts from FPGA readback, then refreshed
after subsequent Add and Execute events in about 1.4 seconds. Details are in
the same validation record.

## Verify

The board-control RTL adds eight switch-selected VGA pages and a five-button
order form. See [board_controls.md](docs/board_controls.md) for physical switch
assignments, digit editing, local submission, and the laptop `--mixed-input`
mode. SW0/SW1 remain unused; SW14/SW15 retain seven-segment selection.
These controls have passed simulation; physical verification is pending.
The built candidate is `build/board_controls_20261102/top_system.bit`
(routed setup +0.499 ns, hold +0.016 ns). It retains the UART snapshot protocol.

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

The release build writes `top_system.bit`, routed timing, utilization, DRC,
and methodology reports to `build_system/`. For an isolated development build:

```bash
FPGA_BUILD_PROFILE=fast vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

The fast profile uses `build_dev/`, skips the pre-route exploratory physical
optimization pass and optional reports, and retains the post-route setup/hold
timing gate and DRC report. If setup timing is negative, it still tries the
existing post-route recovery pass. Benchmark the profile before relying on a
speedup; it may have different timing results. Both build directories are
ignored by Git. The programming script still uses the known-good release
bitstream in `build_system/`.

The UART RAM-readback candidate was built separately at
`build_readback_20261102/top_system.bit`. It passed post-route timing
(setup +0.708 ns, hold +0.019 ns), bitstream DRC, and the physical 13-event
test. It is the previous protocol: the current snapshot dashboard requires a
new bitstream with `B` occupied-set queries and 99-digit `E` journal records.
On this 14 GiB laptop, the build used the performance
power profile and a user scope with `MemoryHigh=8G`, `MemoryMax=10G`, and
`MemorySwapMax=4G` to avoid exhausting system RAM. The build script accepts
`FPGA_MAX_THREADS=1..4` if a later memory-limited run needs fewer workers.
Program the previous candidate explicitly if needed:

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl -tclargs build_readback_20261102/top_system.bit
```

The current cold-attach dashboard requires `build_snapshot_20261102/top_system.bit`.
It passed routed timing (setup +0.511 ns, hold +0.014 ns), bitstream DRC,
and the direct-link board test. Program it with:

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl -tclargs build_snapshot_20261102/top_system.bit
```

## Board bringup when hardware is available

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl
python3 tools/order_journey.py --uart-port /dev/ttyUSB1 --interval 5.5 --count 10
```

Program or reset the current trace-enabled bitstream to start with an empty
book. Use `--interval 1` for one order per second, or `--demo` for a clearly labelled
software walkthrough without hardware. Each UDP datagram contains one ITCH
message. The terminal displays the message bytes and waits for UART counters
from the RMII receiver, UDP parser, Mold decoder, ITCH decoder, event FIFO,
and LOB completion, then verifies the returned BBO, quantities, and order count.
This is also available from `python3 control_center.py` as menu item 3.

The FPGA does not answer ARP. The sender detects the active Wi-Fi interface's
broadcast address; the FPGA must be on that same router's LAN. For a direct
Ethernet link, use `--target-ip` with the Ethernet subnet's broadcast address.
Record physical results using [HARDWARE_VALIDATION.md](docs/HARDWARE_VALIDATION.md).

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
