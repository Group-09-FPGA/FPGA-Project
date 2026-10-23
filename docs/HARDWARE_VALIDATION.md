# Physical board validation record

This records the 2026-10-24 physical run. The UART, Ethernet ingest, book
operations, fail-stop, and recovery checks below were observed on the board.
VGA and a deliberately bad Ethernet FCS were not tested. The local raw UART
and programming logs are in `build_system/hardware_validation/` beside the
tested bitstream; this directory is intentionally ignored by Git.

## Build identity

- Git commit and working-tree status before programming: `d092cff`, clean
- Firmware image SHA-256 (`software/baremetal/lob_test/imem.hex`): `9b2d0b0ffb81993e2aced3f5790cc3fc14ee468cb4a723ad2726ca0aaff54a62`
- Bitstream SHA-256 (`build_system/top_system.bit`): `25c6c83d46bdbcc336b2e38e74a2e0d28a10fe0498edf00d65afce75735dde5b`
- Vivado version and device: 2026.1, `xc7a100tcsg324-1`
- Routed WNS, WHS, and DRC error count: +0.817 ns, +0.030 ns, 0 errors
- Board and host: Digilent JTAG target `210292AD33B0A`, `xc7a100t_0`;
  `/dev/ttyUSB1` at 115200 8-N-1; USB Ethernet `enx00e099001756` at
  `192.168.1.5/24`; 2026-10-24

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

| Test | Observation and captured evidence | Result |
| --- | --- | --- |
| Sequence 1 Add bid and ask | UART moved from empty `V:1 E:00` to bid 905000 (`000DCF28`) and ask 910000 (`000DE2B0`), still `V:1 E:00`. User saw best bid/sell on the display. Quantity and MMIO values were not directly read externally. | Pass for price and validity; quantity/MMIO unverified |
| Replace | Sequence 3–4 replaced both orders. UART moved to bid 906000 (`000DD310`) and ask 911000 (`000DE698`), `V:1 E:00`. | Pass |
| Execute, cancel, delete | Full execute cleared bid; full cancel cleared ask; a new bid at 907000 appeared and delete cleared it. `V:1 E:00` throughout. | Pass for visible book effects; active count not directly read |
| Header-only heartbeat before an order | Heartbeat at sequence 9 did not consume the number; an order at sequence 9 produced ask 912000 (`000DEA80`), `V:1 E:00`. | Pass |
| Wrong UDP port | Order pair sent to 10444 left the valid book empty. Sending the same sequence to 10443 produced the expected bid/ask. | Pass |
| Bad Ethernet FCS | This USB Ethernet adapter generates the transmitted FCS and offers no transmit-FCS control. No intentionally bad FCS was put on the wire. | Not tested |
| Bad IPv4 checksum | A valid raw Ethernet order was accepted as a control. An otherwise valid order with a wrong IPv4 header checksum changed UART to `V:0 E:0A`; the new quote was not published. The internal checksum counter was not read. | Pass for fail-stop; counter unverified |
| Bad UDP checksum | A raw order with correct IPv4 checksum and nonzero incorrect UDP checksum changed UART to `V:0 E:0A`; the ask stayed absent. The UDP MMIO counter was not read. | Pass for fail-stop; counter unverified |
| Mold sequence gap | After expected sequence 10, an order at 11 changed UART to `V:0 E:0A` and held it. | Pass |
| Duplicate order ID | Reusing order reference 1001 at the next sequence changed UART to `V:0 E:02` and held it. | Pass |
| Sustained stream and FIFO ring wrap | 130 sequential Add packets at 10 ms spacing (more than two 64-entry FIFO cycles) ended at the expected higher bid 906000, `V:1 E:00`. Individual FIFO counts were not externally read. | Pass for end-to-end continuity |
| Reset and full replay from sequence 1 | Reprogramming cleared `V:0` and quotes; a sequence-1 order pair restored bid 905000 and ask 910000 with `V:1 E:00`. This was repeated after the fault tests; the board was left in this valid state. | Pass |
| CPU RESETN pushbutton | User pressed the red button. UART then showed an empty valid book, `B:00000000 A:00000000 V:1 E:00`. A fresh sequence-1 pair restored bid 905000 and ask 910000, `V:1 E:00`; see local `uart-button-reset.log`. | Pass |
| UART | Readable periodic `115200 8-N-1` BBO telemetry was captured throughout. | Pass |
| LEDs and seven-segment display | User saw the rightmost four LEDs lit, best bid/sell values, and changing numeric values after moving a switch. Exact mapping and quantity values were not captured. | Basic visual check passed; exact values unverified |
| VGA | No display was available for this run. | Not tested |

Do not publish a valid quote after any `V:0` or feed error. Stop the stream,
reset the board, and replay from sequence 1 before recording a recovered book.
