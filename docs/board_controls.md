# Board switches and five-button controls

This build adds switch-selected VGA inspection pages, board order entry, and
arbitration between local and network orders. The laptop remains the way to
exercise the Ethernet/IP/UDP/Mold/ITCH pipeline; button orders enter a separate
canonical-event FIFO after the network parser. Both queues feed the same LOB.
The network feed keeps its own Mold sequence; local events do not consume it.

Physical SW0/SW1 are unused. Physical SW14/SW15 retain their seven-segment
selection. The RTL still names those two pins `sw[0]`/`sw[1]`; all new controls
below use the physical numbers SW2–SW13.

## Switch assignment

| Physical switches | Function |
| --- | --- |
| SW4:SW2 | Page number; SW4 is the most significant bit |
| SW7:SW5 | Order action; SW7 is the most significant bit |
| SW9:SW8 | Editable field: 00 price, 01 shares, 10 order ID, 11 replacement ID |
| SW10 | Add side: 0 buy, 1 sell; other actions inherit the selected order side |
| SW11 | 1 enables digit editing on Order Entry; 0 leaves fields unchanged |
| SW12 | 1 browses active orders on Order Entry; takes priority over digit editing. On Hash, chooses stash inspection |
| SW13 | 1 enables Center submission on Order Entry; navigation works when 0 |
| SW14/SW15 | Existing seven-segment controls |

| SW4:SW2 | VGA page | Arrow controls |
| --- | --- | --- |
| 000 | Market | Up/Left older history; Down/Right newer |
| 001 | Orders | Up/Right next live order; Down/Left previous; searches real hash RAM and stash |
| 010 | Hash | Up/Down set; Left/Right way or stash index |
| 011 | Events | Up/Left older record; Down/Right newer; up to 256 records |
| 100 | Status | Live pipeline counters and book/error state |
| 101 | Levels | Up/Down price index; Left/Right switches bid/ask side |
| 110 | Slots | Up/Down slot; Left/Right depth in the actual free stack; depth 0 is next allocation |
| 111 | Order Entry | With SW12=1 browse orders; otherwise SW11=1 edits digits |

| SW7:SW5 | Action | Canonical operation |
| --- | --- | --- |
| 000 | A: Add | ADD |
| 001 | F: Add with attribution semantics | ADD |
| 010 | E: Execute | EXECUTE |
| 011 | C: Execute with price semantics | EXECUTE |
| 100 | X: Cancel shares | CANCEL |
| 101 | D: Delete entire order | DELETE |
| 110 | U: Replace reference, price and quantity | REPLACE |
| 111 | Reserved | Locally rejected; no event emitted |

F/A and C/E have the same book effects. Board entry creates canonical events;
it does not build an ITCH Ethernet packet. Attribution and execution-print price
are not order-book fields, so there are no dummy controls for them.

## Enter an Add

1. Select page 111, action 000 or 001, and SW10 for buy/sell.
2. Set SW12=0 and SW11=1. Choose the field with SW9:SW8.
3. Left selects the next larger digit; Right selects the next smaller digit.
   Up adds one at that digit; Down subtracts one. Price and quantity use decimal
   digits. IDs use hexadecimal digits. A caret marks the selected digit.
4. Price is displayed in dollars with four fractional digits. Digit 0 is the
   last fractional digit. With the default $0.1000 tick, digit 3 adjusts one tick.
5. Set SW13=1 and press Center once. This starts submission immediately;
   there is no second confirmation. A held or bouncing Center cannot repeat it.

Default Add IDs start at `00000000B0000000` and advance after enqueue. Default
replacement IDs start at `00000000C0000000` and also advance. Check the visible
ID before submission if mixing manually assigned and generated references.
Price, shares and both IDs remain on the form between submissions.

## Execute, cancel, delete or replace

1. On page 111, set SW12=1 and use an arrow to find the live target order.
   This loads its reference, current price and remaining quantity from RAM.
2. Set SW12=0. Choose the action. Set SW11=1 to edit shares, replacement
   price or new ID as needed. Existing-order actions require the reference
   selected through RAM browsing; typing an unselected reference is rejected.
3. Press Center with SW13=1. Delete ignores the shares field. Replace inherits
   side and uses the new ID, new resting price and new total quantity.

The interface rejects zero shares, over-reductions, invalid price ticks/ranges,
missing selected orders, invalid IDs, disabled submission, and an invalid book.
The LOB remains authoritative for duplicate IDs, hash/slot capacity and races
with network edits. An order rejected by the fail-stop core requires reset and
replay, as in the network demo. The Status page shows the FPGA error code.

`QUEUED` / `SENT TO CORE` report transport into the local FIFO. The global book
completion count, actual RAM state and book validity show processing results.

## Laptop and board in one session

Use the sender's `--mixed-input` option while board controls are in use:

```bash
python3 tools/order_journey.py --advanced --count 14 --interval 5.5 --mixed-input --target-ip 192.168.1.255 --uart-socket /tmp/fpga-lob-uart-1000.sock
```

This mode can start on a valid nonempty book. It confirms network stage
counters and the FPGA trace for the submitted reference, rather than asserting
that the host's order subset equals the whole book. It uses the next network
message number from telemetry. This assumes this demo's one-message packets
and no separate network sender. The scripted sequence still owns its references;
avoid deleting or replacing those references from the board while the script
plans later actions on them. The interactive laptop menu knows orders created
in its own process; browse other active references on the board.

## Electrical mapping and verification

Pin assignments follow the [Digilent Nexys A7-100T Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc).
SW8/SW9 use LVCMOS18; the other chosen switches and all five buttons use
LVCMOS33. Buttons have two-flop synchronizers and 10 ms debounce at 25 MHz.

The simulation suite covers seven action choices, decimal editing, tick
validation, over-reductions, collision-stash browsing, UART RAM-port preemption,
held Center, queue backpressure, mixed-source ordering, and VGA text feedback.
The full-system test sends two network orders, a board-button order, then two
more network orders without resetting network sequencing. Simulation previews
of the new text inspection pages are under `build/ui_preview/`.
Run `python3 tools/render_board_controls_preview.py` to regenerate them from
the actual RTL character selector and font. Fixtures live only in simulation.
The board path is also tested with 64 randomized runtime price bases, ticks,
price indices (including 0 and 8191), share quantities and sides, entered
through the public switches/buttons. The editable starting form values are
defaults; the book algorithm does not select behavior from a demo sequence.
Three additional random seeds exercise 512 book operations each (1,536 total)
against a separate dictionary-book oracle after every commit. They include
64-bit references, hash collisions/stash entries, both sides, arbitrary price
indices, partial/full reductions, deletion and replacement. This test uses
base 123456 and tick 37 instead of the demo configuration.
These pages are a 40-column VGA control/inspection interface; the complete
Kitty chart and table presentation remains separate renderer work. Physical
button, switch and VGA validation requires reconnecting the board.

The previous physically verified image is preserved at
`build/known_good/uart_snapshot_20261102/top_system.bit`, SHA-256
`97a00c9ebac9275658dffb7e9975f41b361ff0b3c640f073c12df69fc2d38d91`.

## Built candidate, 2026-11-02

The new image is `build/board_controls_20261102/top_system.bit`, SHA-256
`f34a30279376709548790484bec4d344cc186266d634123a46d8e3fb50dc90b9`.
Release implementation took 10 minutes 41 seconds with three workers.
Routed setup slack is +0.499 ns, hold slack +0.016 ns, and pulse-width slack
+3.000 ns. All timing constraints passed; bitstream-generation DRC passed.
The build used `MemoryHigh=8G`, `MemoryMax=10G`, `MemorySwapMax=4G`, performance
mode, and a sleep inhibitor. The observed scope memory peak was about 7 GiB.
The previous power profile and battery-aware behavior were restored afterward.

Validation: 23/23 RTL testbenches and 24/24 Python tests passed, plus the
full-system test in Vivado xsim. The board was disconnected: physical button,
switch and VGA validation is pending. Set SW13=0 before the first board test,
then enable it when ready to submit from Order Entry.

After reconnecting, explicitly program this candidate:

```bash
vivado -mode batch -nolog -nojournal -source vivado/scripts/program_fpga.tcl -tclargs build/board_controls_20261102/top_system.bit
```

To return to the preserved, physically verified UART snapshot image:

```bash
vivado -mode batch -nolog -nojournal -source vivado/scripts/program_fpga.tcl -tclargs build/known_good/uart_snapshot_20261102/top_system.bit
```
