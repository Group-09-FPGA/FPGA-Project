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
`build/ui_redesign_20261105/top_system.bit` (build outputs are not in Git).

## Keyboard

| Key | Action |
| --- | --- |
| F1–F7 or 1–7 outside numeric editing | Market, My Orders, Hash Table, Event Log, Price Levels, Order Slots, Place Order |
| H | Quote History; 1–7 or F1–F7 leave History |
| Tab / Shift+Tab | Move among controls on the current page; invalid form fields block Tab |
| Action field: Left/Right or A/F/E/C/X/D/U | Select an ITCH-style action |
| Side field: Left/Right | Buy/Sell for Add actions |
| Numeric field: digits, decimal point, A–F for IDs | Replace existing value on first typed character; later characters insert at cursor |
| Numeric field: Left/Right, Backspace/Delete | Move cursor or repair text |
| Order list: Up/Down | Browse real active orders; Enter opens Order Entry with selected FPGA-stored values |
| Page Up/Page Down | Move a visible page through list/history data |
| Order Entry: Enter | Submit once per key press when valid; release before the next submission |
| Numeric field: Escape | Restore the value from before the first typed edit; no order is sent |

On Order Entry, Tab order is Action, Side, Price, Quantity, Order ID, New ID,
Orders list. Price requires four fractional digits; a decimal point may appear
while typing. IDs accept 1–16 hexadecimal digits with implied leading zeros.
The form starts blank and contains no sample order.
Invalid or overflowed text remains visible with an error so Backspace/Delete
can repair it. The renderer shows focus, cursor, status, shortcuts, and the
last completed local submission result.

Keyboard Enter is **always enabled on Order Entry**. There is no switch-based
submission enable and no Center submission. This removes the former
simultaneous Enter/Center conflict. A local FIFO holds a keyboard event until
the existing arbiter and LOB accept it; network orders use the other arbiter
input. Keyboard events bypass the Ethernet parser, and Ethernet pipeline
counters remain network-only.

Actions A/F add an order; E/C execute shares; X cancels shares; D deletes; U
replaces the selected reference, price, and total quantity. F and C retain the
same canonical book effects as A and E because attribution and execution-print
price are not stored book fields. For E/C/X/D/U, browse a live order first.
Browsing loads its ID, stored price, remaining shares, and side. A changed or
deleted selected order is rejected at Enter and must be reselected.

The 1280×720 VGA renderer reads the FPGA's live hash, stash, slot, price, and
history memories. The Market graph uses actual FPGA quote journal samples.
The T time-axis shortcut is omitted because the FPGA has event numbers but no
host wall-clock timestamp. Static labels and font glyphs are compiled into
the image; order values and graph points are not.

## Verification state

Simulation covers PS/2 framing, parity rejection, make/break, Shift, extended
codes, held Enter, form editing and Escape, all seven actions, stale-order
rejection, keyboard/Ethernet coexistence, and actual VGA pixel rendering from
presentation firmware. Simulation fixtures are under `sim/` only. These checks
passed in all 25 Icarus testbenches and in the Vivado xsim full-system run.
The completed Vivado build reports 48,281/63,400 LUTs, +0.564 ns post-route
setup slack, +0.035 ns hold slack, and zero DRC errors during bitstream
generation. Its routed checkpoint and reports are in `build/keyboard_vga_720p/`.

These checks do **not** establish that a particular wired keyboard or wireless receiver
works with the Nexys A7 PIC, or that a physical unplug/reconnect produces the
expected reset sequence. Physical compatibility and hot-plug behavior still
require the tests below. On 2026-11-02 the image was programmed: UART and
Ethernet order processing passed, but the HP 125 keyboard in J5 was not
detected (the board's BUSY LED never flashed), so the keyboard path is still
unverified on hardware. See [HARDWARE_VALIDATION.md](HARDWARE_VALIDATION.md).

## Physical test sequence

1. Program the new bitstream and select the monitor's VGA input. Confirm the
   1280×720 Market page appears with F1 and Place Order with F7. SW2–SW13 and
   the five direction/Center buttons must have no UI effect.
2. With a wired keyboard in USB Host J5, use Tab to edit an Add order, press
   Enter once, and verify the local completion result and actual Orders row.
   Hold Enter; confirm no duplicate. Press H; confirm the new quote appears in
   History and its Market chart after returning with 1.
3. Select the order on Orders, press Enter to load it into Order Entry, then
   exercise Execute, Cancel, Delete, and Replace with actual remaining values.
4. Begin an edit, unplug and reconnect the keyboard, and confirm text, cursor,
   focus, and book state remain. Test a key held during unplug and confirm no
   stuck key after reconnect. Repeat with the wireless receiver.
5. Send a laptop Ethernet order during keyboard use. Confirm both appear in the
   book and Ethernet counters reflect only network traffic.
