# Physical board validation record

Simulation and routed timing do not establish that the Nexys A7 Ethernet,
UART, and VGA interfaces work on a board. Fill this record during a physical
run. Keep the captured console output, UART log, and Vivado reports alongside
the bitstream used for the test.

## Build identity

- Git commit and working-tree status: record immediately before programming
- Firmware image SHA-256 (`software/baremetal/lob_test/imem.hex`): `9b2d0b0ffb81993e2aced3f5790cc3fc14ee468cb4a723ad2726ca0aaff54a62`
- Bitstream SHA-256 (`build_system/top_system.bit`): `25c6c83d46bdbcc336b2e38e74a2e0d28a10fe0498edf00d65afce75735dde5b`
- Vivado version and device: 2026.1, `xc7a100tcsg324-1`
- Routed WNS, WHS, and DRC error count: +0.817 ns, +0.030 ns, 0 errors
- Board revision, host, and date:

## Direct-link setup

1. Connect the host Ethernet interface directly to the board or through an
   isolated switch. Give the host interface an address such as
   `192.168.1.1/24`; send to `192.168.1.255:10443`. The FPGA does not answer
   ARP, so unicast to an assumed board IP is not a valid default test.
2. Connect JTAG/UART and, if available, a VGA display. Program the recorded
   bitstream. Check clock lock and PHY reset release LEDs.
3. Start the UART monitor before transmitting. Reset the board and wait for
   initialization and firmware configuration acknowledgement.

## Tests to record

| Test | Observation and captured evidence | Pass/fail |
| --- | --- | --- |
| Sequence 1 Add bid and ask | Valid BBO price and quantity on UART, display, and MMIO | |
| Replace, execute, cancel, delete | Each expected BBO and active count; no unexpected error | |
| Header-only heartbeat before an order | Following order is received and committed | |
| Bad Ethernet FCS | CRC count rises; book becomes invalid | |
| Bad IPv4 or UDP checksum | Book becomes invalid; record the UDP MMIO counter when applicable, or capture the internal IPv4 counter with a debug probe | |
| Mold sequence gap | Error `0x0A`, book invalid, `V:0` telemetry | |
| Sustained stream and ring wrap | No unexpected frame, FIFO, or book error | |
| Reset and full replay from sequence 1 | Book becomes valid with expected BBO | |
| VGA and UART | Legible image, stable sync, correctly decoded 115200 8-N-1 text | |

Do not publish a valid quote after any `V:0` or feed error. Stop the stream,
reset the board, and replay from sequence 1 before recording a recovered book.
