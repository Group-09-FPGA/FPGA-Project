# FPGA demo commands

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

**Recommended: advanced demo, one event per Enter (13 events, then empty book):**

```bash
python3 tools/order_journey.py --advanced --interactive --count 13
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
python3 tools/order_journey.py --demo --advanced --interactive --count 13
```

`--interactive` waits for Enter before each event and ignores `--interval`. Press `Ctrl+C` to stop. Use `--uart-port /dev/ttyUSB0` if your UART port differs from the default `/dev/ttyUSB1`. Use `--target-ip ADDRESS` if the board-facing network broadcast address differs from `192.168.1.255`.

For what to say at each advanced event, see [Advanced FPGA order journey demo](order_journey_advanced_demo.md).
