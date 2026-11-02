# FPGA demo commands

## UART dashboard alongside the order sender

The display-only dashboard owns the physical UART and relays the same board
telemetry to the existing sender for its per-order verification. Start the
dashboard in one terminal after connecting the FPGA:

```bash
python3 tools/order_book_dashboard.py --port /dev/ttyUSB1
```

In a second terminal, reset the board to an empty book and run the sender with
the dashboard's displayed socket path:

```bash
python3 tools/order_journey.py --advanced --interactive \
  --uart-socket /tmp/fpga-lob-uart-$(id -u).sock
```

The sender sends MoldUDP64/ITCH packets to the selected IPv4 broadcast LAN and
checks FPGA counters and quotes. The dashboard charts only confirmed board
telemetry. Press `T` to switch the chart axis between event count and local
receipt time, `H` to browse recent quote samples, and `Q` to quit. Keys `1`–`7`
open Market, Orders, Hash, Events, Status, Price Levels, and Slots pages. On
the Hash and Slots pages, arrow keys select a set or slot and `N` jumps to the
next occupied one. Orders, Events, and Price Levels scroll with the up/down
keys. Green means
a rising quote; red means a falling quote. If the book becomes invalid, the
last valid quotes and charts remain visible with an invalid warning. Run
`python3 tools/order_book_dashboard.py --demo` for a clearly marked software
preview of all 13 advanced events without the board. On the new storage-trace
bitstream, Orders, Hash, Levels, and Slots reconstruct state from FPGA RAM
write controls. The sender's independent host prediction is compared with
those records. This telemetry does not read every RAM cell; it needs a reset
and a complete trace from event 1. The dashboard also checks the reconstructed
BBO and active count against the reported FPGA values. The layout expands to fill a
full-screen Kitty terminal. Use a wide window for the Hash, Slots, and Price
Levels pages; narrow windows can clip their details. Keep only one physical
UART reader running.

For the direct USB Ethernet link observed on 2026-11-02, the laptop adapter
was `enx00e099001756` at `192.168.1.5/24`. Confirm its carrier and address
with `ip -br addr show enx00e099001756`, then use this sender command in the
second terminal:

```bash
python3 tools/order_journey.py --advanced --count 13 --interval 5.5 \
  --target-ip 192.168.1.255 \
  --uart-socket /tmp/fpga-lob-uart-$(id -u).sock
```

The FPGA filters ITCH stock locate 1. The sender's required eight-byte stock
field uses neutral `LOBDEMO`; the display labels the tracked book by locate.
The direct-link run and RAM readback results are in
[HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md).

Run from the laptop connected to the Nexys A7 by USB/UART and Ethernet.

```bash
cd /home/ronit/acad/sem-3/hardware/fpga-lob
```

## Program the board

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl
```

This loads the previous known-good `build_system/top_system.bit`. The new
UART readback candidate is separate. When the board is available, program it
explicitly:

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl -tclargs build_readback_20261102/top_system.bit
```

The candidate passed simulation, post-route timing, and bitstream DRC; it
still needs physical board validation. If the candidate is missing, build it:

```bash
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

**Before each new run:** stop the sender, press **CPU RESET** on the board, wait for an empty valid book, then start from sequence 1. You do not need to reprogram every time.

## Run one demo mode

**Recommended: guided interactive demo, choose each event and its fields:**

```bash
python3 tools/order_journey.py --advanced --interactive
```

**Advanced, automatic, at least 5.5 seconds between events:**

```bash
python3 tools/order_journey.py --advanced --count 13 --interval 5.5
```

**Advanced, continuous:**

```bash
python3 tools/order_journey.py --advanced --count 0 --interval 5.5
```

**Simple default live demo (10 events):**

```bash
python3 tools/order_journey.py
```

**Simulated practice; no board traffic:**

```bash
python3 tools/order_journey.py --demo --advanced --interactive
```

`--interactive` shows an action menu after each verified order. Add and attributed add ask for side, shares, and price. Execute, priced execute, cancel, delete, and replace list active orders so you can select one; follow-up prompts ask for the relevant quantity and price. Press Enter on the final summary to send that one event, `b` to choose again, or `q`/`0` to finish. The guided mode continues until you finish unless you set `--count`; it ignores `--interval`. The non-interactive `--advanced` mode retains the fixed 13-event sequence. Use `--uart-port /dev/ttyUSB0` if your UART port differs from the default `/dev/ttyUSB1`. The live script detects the active Wi-Fi broadcast address automatically; keep the FPGA on the same LAN. Use `--target-ip ADDRESS` to override it for a direct Ethernet link or another interface.

With the new candidate, dashboard pages 2, 3, 6, and 7 reconstruct an address
map from FPGA write traces, query touched FPGA RAM entries over UART, and show
returned values with a mismatch marker when they differ. The separate host
prediction remains available for comparison. The old `build_system` bitstream
predates this protocol. See [FPGA storage trace over UART](storage_trace_uart.md)
for the record and query layouts.

For what to say at each advanced event, see [Advanced FPGA order journey demo](order_journey_advanced_demo.md).
