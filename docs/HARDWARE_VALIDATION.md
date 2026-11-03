# Physical board validation record

## 2026-11-02 physical board-control checks

Programmed the controls candidate `build/board_controls_20261102/top_system.bit`
(SHA-256 `f34a30279376709548790484bec4d344cc186266d634123a46d8e3fb50dc90b9`)
onto target `210292AD33B0A`. UART confirmed an empty valid book with runtime
base 900000 and tick 1000. The user reported that VGA was not visible, so
visual page selection is not verified by this run.

| Manual check | FPGA observation | Result |
| --- | --- | --- |
| Entry page, SW13 enabled, Center once | D=1, valid, error 0, Buy 100 at $90.5000; network Mold/ITCH/FIFO counters remain zero | Pass |
| Actual storage of first button order | RAM snapshot: reference `0xB0000000`, slot 2047, hash set 770, way 0, 100 shares at price index 5 | Pass |
| Price/quantity editor, Sell side | User selected price digit 3 and raised it twice, then quantity digit 1 and raised it five times; Center gave D=2, Buy 100 at $90.5000 and Sell 150 at $90.7000, active 2, valid, error 0 | Pass |
| Browse live Buy, decrease shares, Execute | Up browsed the actual Buy slot; digit editing selected 40 shares; Center gave D=3, Buy 60 at $90.5000, Sell 150 at $90.7000, active 2, valid, error 0 | Pass |
| Browse live Sell with Right, action C | Right selected the Sell slot; editing 150 to 50 requested an execution of 50 shares. D=4, Buy 60 at $90.5000, Sell 100 at $90.7000, active 2, valid, error 0 | Pass |
| Browse previous Buy with Down, Cancel | Down selected the Buy slot; editing 60 to 10 requested cancellation of 10 shares. D=5, Buy 50 at $90.5000, Sell 100 at $90.7000, active 2, valid, error 0 | Pass |
| Replace price, shares and new-ID digit editor | D=6 replaced `0xB0000001` with `0xC0000011`, Sell 120 at $90.8000, active 2, valid, error 0. The committed trace preserved slot 2046, invalidated hash set 771, inserted set 18, cleared old price address 8199 and wrote 120 at address 8200 | Pass |

The user ended manual testing after D=6. Final state: Buy 50 at $90.5000,
Sell 120 at $90.8000, two active orders, valid, error zero. Add A, Execute E,
Execute C, Cancel X and Replace U were physically checked. All five buttons,
price/shares/new-ID editing and active-order browsing were exercised.
F, Delete, typed old-order-ID editing, held-Center behavior, disabled submission
and local rejection cases remain simulation-tested rather than physically
checked in this run. VGA output/page appearance remains unverified.
UART observations are recorded locally in the ignored
`build/board_controls_20261102/hardware_validation/` directory.

## 2026-11-02 sender relay backpressure fix

The snapshot dashboard originally forwarded RAM replies as well as BBO lines
to the sender's local socket. During the 5.5-second pause between orders,
the sender did not drain that traffic; the dashboard's 50 ms socket write
timeout could close the sender connection despite healthy UART and Ethernet.
The relay now forwards BBO telemetry without RAM replies. A regression test
queues 1,000 RAM replies for a waiting client and checks that only the BBO
confirmation reaches it. The physical 14-event advanced sequence at 5.5-second
spacing then completed with all 14 `BOARD VERIFIED V=1 E=00` confirmations.
The unchanged snapshot bitstream was used. All 22 Python tests passed.

## 2026-11-02 cold dashboard snapshot on a direct Ethernet link

Programmed `build_snapshot_20261102/top_system.bit` (SHA-256
`97a00c9ebac9275658dffb7e9975f41b361ff0b3c640f073c12df69fc2d38d91`)
onto Digilent target `210292AD33B0A`. The release build routed with
+0.511 ns setup and +0.014 ns hold slack; bitstream generation passed DRC.
The build ran in a user cgroup capped at 10 GiB RAM and 4 GiB swap.

| Check | Physical observation | Result |
| --- | --- | --- |
| Orders before dashboard | Sent two 6-second-spaced Add events via direct USB Ethernet while dashboard was closed; UART confirmed `D=2`, bid 905000 × 100, ask 949000 × 200, active 2 | Pass |
| Cold attach | A new Kitty dashboard read 60 FPGA words and rebuilt both chart points, both orders with slots 2047/2046, all event records, both price levels, hash occupancy, and free-stack top | Pass |
| Live Add refresh | At event 5, the dashboard rebuilt five active orders and their level totals in 1.41 seconds | Pass |
| Live Execute refresh | Event 6 executed 40 shares from order 1003; the FPGA journal page showed `EXECUTE 1003 B 40 $90.7000`, and the order slot fell from 150 to 110 shares in 1.40 seconds | Pass |
| Aggregated level | After event 6, the bid level at $90.7000 showed 160 shares in two orders, directly from FPGA price quantity and level-count RAM | Pass |

The dashboard was left open on its Market page with five active orders after
event 6. This run proves reconstruction without earlier laptop market state
for the tested six-event session. Historical laptop wall-clock receipt times
are not in the FPGA; a cold dashboard uses FPGA event numbers. Dense books
may take longer than the six-second order interval to scan over UART. The
VGA seven-page layout and switch navigation remain untested on a display.

## 2026-11-02 UART RAM-readback candidate on a direct Ethernet link

Programmed `build_readback_20261102/top_system.bit` (SHA-256
`d5d3c6df75e4d9bd4fd775e2d6651844715c9c1c165908cd69ea724b984fec92`)
onto Digilent target `210292AD33B0A`, device `xc7a100t_0`. The laptop's
USB dock exposed FT2232 UART `/dev/ttyUSB1` and USB Ethernet
`enx00e099001756`, configured as `192.168.1.5/24`. After programming, the
Ethernet carrier came up; the sender used `192.168.1.255:10443`, which the
host routed over that adapter. Wi-Fi remained connected on a different subnet.

| Check | Physical observation | Result |
| --- | --- | --- |
| Empty board after programming | UART `D=0 V=1 E=00 N=0`, bid/ask zero; slot `0x07FF` read back zero, free-stack top `0x07FF` | Pass |
| Direct Ethernet, three Add events | Receiver, UDP, Mold, ITCH, FIFO, and completion counters reached 3; BBO and active count matched the sender | Pass |
| Full 13-event advanced sequence at 5.5 s spacing | All 13 sender journeys returned `BOARD VERIFIED V=1 E=00`; counters reached 13 at UDP, Mold, ITCH, FIFO, and book completion | Pass |
| Laptop RAM readback | Final dashboard showed 53 matching reads, zero mismatches, and host prediction matching the FPGA trace | Pass |
| FPGA event journal | Events page showed all 13 events with verified journal records | Pass |
| Cleared price levels | After final deletes, Orders showed 0 active and both bid/ask Levels panes showed no active levels | Pass |
| Invalid slot words | Cleared slot words retained price-index bits with valid=0; the checker now compares the exact FPGA write word | Pass after host checker fix |
| Neutral ITCH stock field | One additional Add using `LOBDEMO` in the required stock field was accepted and verified; sender displays book locate 1 | Pass |

The final reprogram left the board empty and valid (`D=0 V=1 E=00 N=0`),
with slot `0x07FF` reading zero. The dashboard was stopped so `/dev/ttyUSB1`
is free. The VGA seven-page presentation, physical switch navigation, bad
Ethernet FCS, and independent CPU MMIO readback were not checked in this run.
Sender logs are kept locally under the ignored
`build_readback_20261102/hardware_validation/` directory.

The sections below record the earlier 2026-10-24 physical run. The UART, Ethernet ingest, book
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

## Keyboard and 720p image (2026-11-02)

Image: `build/keyboard_vga_720p/top_system.bit` (routed setup +0.564 ns, hold +0.035 ns, 0 DRC errors).

| Check | Result | Status |
| --- | --- | --- |
| Programming, UART `[BBO]` line, empty valid book | Seen | Pass |
| Two Ethernet orders over a direct link | Bid $90.5000 × 100, ask $94.9000 × 200 on UART | Pass |
| USB keyboard in J5 (HP 125 wired, Boot Keyboard on the laptop) | BUSY LED never flashed, no page change; a mouse lit in J5, so the port is powered | Not working: cause unknown |
| VGA picture, unplug/reconnect, wireless receiver, keyboard orders | Not tested | Pending |

Next step: try a second wired keyboard; if BUSY still stays dark, add a debug
LED on `ps2_clk` activity to see whether anything reaches the FPGA.
