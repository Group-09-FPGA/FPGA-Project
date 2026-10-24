# Physical board validation record

This records the 2026-10-24 physical run. The UART, Ethernet ingest, book
operations, fail-stop, and recovery checks below were observed on the board.
VGA and a deliberately bad Ethernet FCS were not tested. The original raw
UART captures are local `/tmp/fpga-lob-board-uart-*.log` files and are not
tracked by Git; the recorded observations below remain the durable summary.

## Extended telemetry run

An extended UART build was programmed later on 2026-10-24 to expose bid/ask
quantity (`QB`/`QA`), active orders (`N`), and CRC, UDP checksum, and IPv4
checksum counters. Its bitstream SHA-256 was
`67f11e96a924e0414de2034353840dc1c1ad29c3efd12408e40cad417f2d8e9a`.
The routed build had +0.862 ns setup slack, +0.023 ns hold slack, and zero DRC
errors. Board UART observations:

| Check | Observed UART values | Result |
| --- | --- | --- |
| Add pair | Bid 905000 × 500, ask 910000 × 300, `N:002`, all checksum counters zero | Pass |
| Replace pair | Bid 906000 × 450, ask 911000 × 250, `N:002` | Pass |
| Partial execute/cancel | Executing 100 bid shares gave 400; canceling 50 ask shares gave 250; `N:002` | Pass |
| Delete each order | Bid then ask cleared; active count fell to 1 then 0 | Pass for settled values |
| Bad IPv4 checksum | `IP:00000001`, `UDP:00000000`, `CRC:00000000`, `V:0 E:0A` | Pass |
| Bad UDP checksum after reset | `UDP:00000001`, `IP:00000000`, `CRC:00000000`, `V:0 E:0A` | Pass |

Those counters were observed at the source through the UART telemetry path;
the CPU's MMIO readback of them was not checked on the physical board. The
first extended build briefly reported active count before its pipelined BBO
price had settled. A six-cycle telemetry delay was added. The resulting
bitstream SHA-256 is
`bd5f2c2a4f577670a8c02ed726552a8e3c00455b0228f24034673243541c8d9e`;
it routed with +1.317 ns setup slack, +0.012 ns hold slack, and zero DRC
errors. The board disconnected before this revised bitstream could be
programmed. After reconnecting, the revised bitstream was programmed and
retested on the board. Captured `uart-settled-retest.log` contains the expected
Add, partial Execute, partial Cancel, and Delete states with no mismatched
price/quantity/active-count lines. Separate resets followed by bad IPv4 and
UDP checksum packets again produced the respective counter increment from
zero to one and `V:0 E:0A` (`uart-final-ip-counter.log` and
`uart-final-udp-counter.log`). A final reset and sequence-1 replay restored
bid 905000 × 500 and ask 910000 × 300, `N:002 V:1 E:00`, with all checksum
counters zero (`uart-final-valid.log`). The board was left in that valid state.
These final run logs are in the ignored local `build_system/hardware_validation/`
directory.

The RMII unit test transmitted a frame with a deliberately corrupt FCS and
confirmed rejection plus a CRC error count of one (67/67 assertions passed).
The connected USB Ethernet adapter does not allow host control of transmitted
FCS, so the bad-FCS case remains untested on the physical Ethernet link.

## Original build identity

- Git commit and working-tree status before programming: `d092cff`, clean
- Firmware image SHA-256 (`software/baremetal/lob_test/imem.hex`): `9b2d0b0ffb81993e2aced3f5790cc3fc14ee468cb4a723ad2726ca0aaff54a62`
- Original bitstream SHA-256 (then `build_system/top_system.bit`): `25c6c83d46bdbcc336b2e38e74a2e0d28a10fe0498edf00d65afce75735dde5b`
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

## Original run observations

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
