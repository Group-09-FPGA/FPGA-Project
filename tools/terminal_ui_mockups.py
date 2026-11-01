#!/usr/bin/env python3
"""Static preview of the UART-first, display-only order-book dashboard.

This file never opens a serial port or sends an order.
"""

PREVIEW = r"""
 FPGA ORDER BOOK                                      UART ●  BOOK VALID ●

 BID $90.7000 × 150       ASK $94.8000 × 75       SPREAD $4.1000

 BID HISTORY                         │ ETHERNET → ORDER BOOK
 90.8 ┤                             │ 01  Ethernet frames        5
 90.7 ┤            ┌──────────────  │             ↓
 90.6 ┤            │                │ 02  UDP packets            5
 90.5 ┤────────────┘                │             ↓
      └─ 1 ── 2 ── 3 ── 4 ── 5 →     │ 03  Mold messages          5
                                    │             ↓
 ASK HISTORY                        │ 04  ITCH events            5
 95.0 ┤                             │             ↓
 94.9 ┤────────────┐                │ 05  Event FIFO             5
 94.8 ┤            └──────────────  │             ↓
 94.7 ┤                             │ 06  Book completed         5
      └─ 1 ── 2 ── 3 ── 4 ── 5 →     │
                                    │ BOOK STATUS  Active 4 · Error 0x00
                                    │ QUOTE UPDATES
                                    │ #5 BID rose  $90.50 → $90.70
                                    │ #4 ASK fell  $94.90 → $94.80

 Green = rising · Red = falling · Grey = unchanged
 [T] Time / event axis      [H] Quote history      [Q] Quit

 STATIC PREVIEW · sample values · no FPGA connection
"""


if __name__ == "__main__":
    print(PREVIEW.strip("\n"))
