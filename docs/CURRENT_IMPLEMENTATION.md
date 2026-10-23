# Current FPGA implementation and demo contract

This document describes the implemented Verilog design. Older architecture
proposals and audit reports in `docs/` are historical references.

## Data path and correctness

The RMII receiver checks Ethernet FCS and queues complete frames. The IPv4/UDP
parser validates the IPv4 header checksum, rejects fragmentation and inconsistent
IP/UDP lengths, checks a nonzero UDP checksum before releasing the buffered UDP
payload, and filters UDP port 10443. Destination MAC and IP filters are top-level
parameters; zero selects the passive broadcast/port-filtered demo mode.

MoldUDP64 starts with expected sequence 1 after board reset. It never joins an
arbitrary later sequence with an empty book. A missing sequence, changed session,
truncated packet, Ethernet error, FIFO overflow, failed UDP checksum, or malformed
ITCH order message latches feed loss. The LOB then enters fail-stop with error code
`0x0A` and `book_valid=0`; it cannot publish a valid quote until reset and a
complete replay. Duplicated older MoldUDP64 packets are discarded.

ITCH Add/Replace prices use a 32-cycle restoring divider with the configured tick
size. The decoder buffers one message and holds its canonical event until the
dual-clock FIFO accepts it. Unsupported administrative messages are ignored;
malformed supported order messages invalidate the feed.

## Configuration and clock crossings

LOB price base, tick, and stock locate are writable only while the accelerator is
disabled and no event has been committed. The core-domain values cross to the
Ethernet clock through an acknowledged bundled-data bridge. MMIO status bit 7
means the Ethernet domain has received the latest configuration. The monitor
firmware waits for this bit before enabling event consumption. A configuration
change after live messages have arrived invalidates the book.

The Ethernet-to-core event FIFO uses Gray-code pointers. Coherent diagnostic and
book snapshots cross to the VGA domain through acknowledged bundled-data bridges.
The network MMIO counters also cross through a bridge. UART telemetry includes
`V:0/1` book validity and `E:xx` error code with each BBO frame.

## Memory map and firmware

IMEM is `0x00000000..0x00000FFF` (4 KiB). DMEM is
`0x20000000..0x20000FFF` (4 KiB). Addresses outside implemented windows return a
bus error instead of aliasing memory. Peripheral blocks occupy 256-byte windows
at `0x40000000` (LOB), `0x50000000` (network), `0x60000000` (UART), and
`0x70000000` (system).

The RV32IM monitor firmware continuously copies coherent BBO snapshots and status
to DMEM. Build it reproducibly with
`python3 software/baremetal/lob_test/build_firmware.py` before synthesis.

Network diagnostic MMIO offsets: `0x00` received frames, `0x04` CRC errors,
`0x08` Mold messages, `0x0C` gaps, `0x10` frame-length errors, `0x14` PHY errors,
`0x18` receive overflow, `0x1C` truncated Mold packets, `0x20` fault flags,
`0x24` UDP length errors, and `0x28` UDP checksum errors. Fault flag bits are:
bit 0 feed loss, bit 1 Mold sequence/session gap, bit 2 ITCH decode error.

LOB control bit 0 enables event consumption; bit 2 requests a coherent snapshot.
The design always uses fail-stop for book errors. Board reset is the supported
clear-and-replay operation. CPU event injection is not implemented.

## Recovery and demo procedure

1. Stop the host stream before resetting the board.
2. Press the board reset button. Wait for clock lock, LOB initialization, and the
   firmware configuration-ready/enable sequence.
3. Start a **complete** host feed from MoldUDP64 sequence 1. The supplied
   `tools/hardware_test_helper.py --stream` does this when started fresh.
4. Check `book_valid`, both BBO sides, the UART `V:1` field, and zero fault/error
   counters. A `V:0` frame means the quote must not be used; repeat from step 1.

## Verification gates

Run `./sim/run_ci_tests.sh`, `./sim/integration/run_system_top.sh`,
`python3 -m unittest discover -s tests`, and
`cd software_lob && uv run --extra dev pytest -q`. The Vivado build script exits
without writing a candidate bitstream unless post-route setup and hold slack are
nonnegative. It accepts `FPGA_BUILD_DIR` to keep a candidate separate from the
previous known-good bitstream. The GitHub routed-build job requires a self-hosted
runner with Vivado 2026.1 and the RV32IM toolchain.
