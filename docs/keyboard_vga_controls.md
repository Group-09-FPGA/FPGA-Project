# Keyboard and VGA controls

The Nexys A7 USB Host connector (J5) is the keyboard input. The board's
auxiliary HID controller presents PS/2 clock/data on FPGA pins F4/B2. This
design accepts scan-code set 2 from USB Boot HID keyboards, including
compatible wired keyboards and 2.4 GHz receivers that expose a Boot HID
keyboard. Bluetooth dongles that require a Bluetooth stack are outside scope.
Digilent documents the [HID-to-PS/2 bridge and Boot HID limitation](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf)
and the [F4/B2 pins](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc).

## Physical controls

CPU_RESETN is the system reset. SW14/SW15 select the seven-segment content.
All other switches and the five directional buttons do nothing. The image is
`build/readonly_20261105/top_system.bit` (build outputs are not in Git).

## Keyboard (view only)

The display is read-only. No key can create, change or cancel an order;
orders reach the book only from the laptop over Ethernet.

| Key | Action |
| --- | --- |
| F1–F6 or 1–6 | Market, My Orders, Hash Table, Event Log, Price Levels, Order Slots |
| H | Price history; 1–6 or F1–F6 leave it |
| Tab / Shift+Tab | Market: move focus; Hash Table: pick the way shown in the enlarged set |
| Up/Down, Page Up/Page Down | Scroll lists and history on Market, My Orders and Event Log |
| Hash Table: arrows | Move the selected square on the 32×32 grid of all 1024 sets (Left/Right ±1, Up/Down ±32) |
| Hash Table: Page Up/Page Down | Jump 256 sets |
| Price Levels: arrows | Move the selected square on a 32×32 grid (8 price steps per square); Left/Right ±1, Up/Down ±32, Page Up/Page Down ±256 |
| Order Slots: arrows | Move the selected slot on a 64×32 grid of all 2048 slots; Left/Right ±1, Up/Down ±64, Page Up/Page Down ±512 |

F7, F8, 7 and 8 do nothing. The keyboard path is a PS/2 receiver and a small
page-navigation module only; there is no order form, local FIFO or arbiter.

## Physical test sequence

1. Program the bitstream, select the monitor's VGA input and confirm the
   1280×720 Market page appears. SW2–SW13 and the direction buttons have no UI
   effect.
2. With a wired keyboard in USB Host J5, press F1–F6 and check each page. The
   UART `[BBO]` line ends with `KB:` counters that rise as keys are pressed.
3. Run `tools/order_journey.py` and confirm the Market graph, My Orders list and
   Hash Table update. Press keys such as F7, 7 and Enter and confirm no order
   is created.
