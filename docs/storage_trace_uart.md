# FPGA storage trace over UART

The FPGA order book stores 2,048 order slots, 1,024 hash sets with
8 ways plus an 8-entry stash, and 16,384 price quantities. The UART `T`
field reports the write controls consumed by those memories for the most
recent completed event. The readback commands below return the current
contents of a selected RAM address.

The existing `[BBO]` line includes `| T:` followed by 79 hexadecimal digits,
then `| BASE:` and `| TICK:` with eight hexadecimal digits each. These are the
FPGA's configured price base and tick, so the terminal need not assume the
demo defaults.
The trace is 316 bits, most significant field first:

| Field | Bits | Meaning |
| --- | ---: | --- |
| valid, op | 1, 4 | Completed event and canonical operation (1 add, 2 execute, 3 cancel, 4 delete, 5 replace) |
| old ID, new ID | 64, 64 | Canonical order references |
| slot write valid, address, data | 1, 11, 47 | Actual slot write control; data is valid, side, 13-bit price index, 32-bit shares |
| hash invalidation valid, set, index, stash | 1, 10, 3, 1 | Removed hash way or stash entry |
| hash insertion valid, set, index, stash | 1, 10, 3, 1 | Written hash way or stash entry |
| price write 0 valid, address, quantity | 1, 14, 32 | First aggregate level write |
| price write 1 valid, address, quantity | 1, 14, 32 | Second aggregate level write, used by replacements that change price |

The dashboard reconstructs the address map from FPGA write traces, requests
the touched RAM addresses, and displays readback values when verified. It
independently runs the host prediction and compares active-order locations and
level totals. A RAM/trace mismatch appears prominently on the storage pages.
The quote graph uses the FPGA quote-ring sample after its readback arrives.

## Read-only UART query protocol

At 115200 baud, send ASCII `?S07FF\n` to read slot `0x07FF`. The board replies
`@S07FF=<12 uppercase hex digits>\r\n`. Four address digits are always
hexadecimal; the reply echoes type and address. One query is outstanding at a
time. Automatic BBO and readback lines do not interleave.

| Type | Address | Response payload |
| --- | --- | --- |
| `S` | 0–2047 | 47-bit slot record, 12 hex digits |
| `H` | 0–1023 | Eight 76-bit hash ways, low way first, 152 hex digits |
| `X` | 0–7 | 76-bit collision stash entry, 19 hex digits |
| `P` | 0–16383 | 32-bit aggregate price quantity, 8 hex digits |
| `L` | 0–16383 | 12-bit number of orders at price, 3 hex digits |
| `F` | 0–2047 | 11-bit free-stack entry, 3 hex digits |
| `Q` | 0–127 | 175-bit quote journal record, 44 hex digits |
| `E` | 0–255 | 32-bit event number plus 316-bit write trace, 87 hex digits |

Start with a reset board and keep the dashboard connected so it knows which
addresses to query. A readback is a current RAM observation. If another order
changes that address while a query is in flight, the dashboard compares only
the reply associated with the latest completed event.

Start with an empty board and keep the dashboard connected for the whole
session. The UART formatter currently retains only its latest pending update;
events arriving faster than a trace line can be transmitted may coalesce. The
dashboard detects a gap in the board event count and stops applying further
storage records until reset. This demo's one-order-per-packet, 5.5-second
pacing leaves ample time for a 320-byte UART line at 115200 baud. VGA now has
read-only ports into the actual slot, hash, price, and free-list RAMs plus
board-owned quote and event rings. The remaining work is the full page
renderer, navigation, and coherent frame-level
presentation. A timing-checked candidate bitstream is available in
`build_readback_20261102/top_system.bit`; it has not been tested on the
physical board.
