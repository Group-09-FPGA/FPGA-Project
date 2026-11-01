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

The sender still sends MoldUDP64/ITCH packets over the active Wi-Fi LAN and
checks FPGA counters and quotes. The dashboard charts only confirmed board
telemetry. Press `T` to switch the chart axis between event count and local
receipt time, `H` to browse recent quote samples, and `Q` to quit. Green means
a rising quote; red means a falling quote. If the book becomes invalid, the
last valid quotes and charts remain visible with an invalid warning. Run
`python3 tools/order_book_dashboard.py --demo` for a clearly marked software
preview without the board. The layout expands to fill a full-screen Kitty
terminal and also works from 70 columns × 27 rows upward. Keep only one
physical UART reader running.

Run from the laptop connected to the Nexys A7 by USB/UART and Ethernet.

```bash
cd /home/ronit/acad/sem-3/hardware/fpga-lob
```

## Program the board

```bash
vivado -mode batch -source vivado/scripts/program_fpga.tcl
```

This loads `build_system/top_system.bit`. If that file is missing, build it first:

```bash
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

**Before each new run:** stop the sender, press **CPU RESET** on the board, wait for an empty valid book, then start from sequence 1. You do not need to reprogram every time.

## Run one demo mode

**Recommended: guided interactive demo, choose each event and its fields:**

```bash
python3 tools/order_journey.py --advanced --interactive
```

**Advanced, automatic, at least 10 seconds between events:**

```bash
python3 tools/order_journey.py --advanced --count 13 --interval 10
```

**Advanced, continuous:**

```bash
python3 tools/order_journey.py --advanced --count 0 --interval 10
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

For what to say at each advanced event, see [Advanced FPGA order journey demo](order_journey_advanced_demo.md).
