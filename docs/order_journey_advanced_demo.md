# Advanced FPGA order journey demo

This is a guided, one-message-at-a-time demonstration of the Nexys A7 limit order book. Every row uses AAPL and one ITCH message in one MoldUDP64/UDP packet. The 13-event sequence exercises all seven order-message types accepted by the current ITCH decoder: `A`, `F`, `E`, `C`, `X`, `U`, and `D`. It finishes with an empty book, so the sequence can repeat in continuous mode.

## Start the live demo

1. Stop any other feed sender or serial reader. Press the board's **CPU RESET** button, then wait for clock lock, LOB initialization, and a valid empty book.
2. For the fixed 13-event sequence described below, run:

   ```bash
   python3 tools/order_journey.py --advanced --count 13 --interval 10
   ```

3. For a guided demonstration where you choose each action and its order, run `python3 tools/order_journey.py --advanced --interactive` instead. The menu offers all seven ITCH types. It lists active orders for execute, priced execute, cancel, delete, and replace, then asks for the required fields. Press **Enter** on the final event summary to send it; `b` goes back and `q` finishes. You can explain the current result and switch between bid and ask displays before choosing the next action.

For a clearly labelled simulation without Ethernet or UART, add `--demo`. Use `--count 0` for continuous fixed 13-event cycles; in automatic mode, the interval remains the minimum time between event starts. Guided interactive mode defaults to no event limit and ignores `--interval`.

The live script requires an empty, valid FPGA book at startup. Reset the board before starting again from sequence 1; reprogramming is only necessary if the configured bitstream is lost or changed.

## What the fixed 13-event sequence demonstrates

Prices are shown in dollars; quantities are shares at the best price. A dash means that side has no orders. `Active` counts stored orders, not shares.

| # | ITCH | Action and point to explain | Best bid × qty | Best ask × qty | Active |
|---:|:---:|---|---:|---:|---:|
| 1 | A | Add buy ID 1000, 100 shares at $90.50. First bid appears. | $90.50 × 100 | — | 1 |
| 2 | F | Add attributed sell ID 1001, 200 at $94.90. First ask appears; the four-byte attribution is part of the ITCH message. | $90.50 × 100 | $94.90 × 200 | 2 |
| 3 | A | Add buy ID 1003, 150 at $90.70. Higher buy price becomes the best bid. | $90.70 × 150 | $94.90 × 200 | 3 |
| 4 | A | Add buy ID 1004, 50 at the same $90.70. Best-bid quantity aggregates to 200. | $90.70 × 200 | $94.90 × 200 | 4 |
| 5 | A | Add sell ID 1005, 75 at $94.80. Lower sell price becomes the best ask. | $90.70 × 200 | $94.80 × 75 | 5 |
| 6 | E | Execute 40 shares from buy ID 1003. Its remaining 110 shares plus ID 1004's 50 leave 160 at the best bid; the order stays active. | $90.70 × 160 | $94.80 × 75 | 5 |
| 7 | C | Execute all 75 shares of sell ID 1005, with an execution price field. That order disappears and the ask falls back to $94.90. | $90.70 × 160 | $94.90 × 200 | 4 |
| 8 | X | Cancel 20 shares from buy ID 1004. Best-bid quantity drops to 140 without changing price. | $90.70 × 140 | $94.90 × 200 | 4 |
| 9 | U | Replace sell ID 1001 with new ID 1002, 180 shares at $94.70. The new lower ask appears. | $90.70 × 140 | $94.70 × 180 | 4 |
| 10 | D | Delete buy ID 1003. ID 1004 still holds 30 shares at $90.70. | $90.70 × 30 | $94.70 × 180 | 3 |
| 11 | X | Cancel the remaining 30 shares of buy ID 1004. The bid falls back to ID 1000 at $90.50. | $90.50 × 100 | $94.70 × 180 | 2 |
| 12 | D | Delete sell ID 1002. There is now no ask. | $90.50 × 100 | — | 1 |
| 13 | D | Delete buy ID 1000. The book is empty again. | — | — | 0 |

`A` and `F` both become add events inside the FPGA. `E` and `C` both become execute events; `C` carries additional execution-price data. `X` reduces an order without a trade. `U` removes the old order ID and inserts a new ID, quantity, and price. `D` removes the entire referenced order.

## What is measured on the board

The **Expected BBO** line is calculated by the host before sending. The script then reads FPGA telemetry through UART and only prints **BOARD VERIFIED** when the reported bid, ask, quantities, active count, `V=1`, `E=00`, and all six pipeline counters meet the expected result. It stops on missing or invalid confirmation.

The counters are `R` accepted Ethernet frames, `U` accepted UDP packets, `M` Mold messages, `I` decoded ITCH order events, `F` events accepted into the clock-crossing FIFO, and `D` completed LOB events. Ethernet `R` may increase by more than one because other network frames can arrive; the demo checks that it advances, not that it equals the order number.

The numbered terminal stage labels are a narrated explanation of the path. Their counters and final BBO are sourced from the FPGA telemetry, but the labels are **not** a cycle-by-cycle waveform or proof of an individual signal at each stage. The printed hash set is computed by the host from the order ID.

## Board interaction while paused

- Set the display to **bid** (`SW15=0, SW14=0`) and **ask** (`SW15=0, SW14=1`) to show the changing best prices. The slide switches are physical SW15 and SW14; the code sees them as `sw[1:0]`.
- Watch `LD3` for book-valid, `LD4` and `LD5` for bid/ask-valid. The UART quantities give more detail than the seven-segment price display.
- After event 4, point out that two separate orders at the same bid price produce an aggregate quantity of 200. After event 11, point out that removing the better bid reveals the older $90.50 bid.

The advanced packet format and host book calculations can be exercised with `--demo`, but the full advanced sequence should be tried on the physical board before presenting it as a verified hardware result.
