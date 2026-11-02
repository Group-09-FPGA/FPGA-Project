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

The dashboard uses this trace for the latest event and the FPGA event journal.
After any completed event, including a cold attach, it rebuilds its displayed
book from current FPGA RAM and the retained journals. An independent host
prediction is compared only when the sender has been observed since event 1.

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
| `E` | 0–255 | 32-bit event number, 46-bit canonical event metadata, 316-bit write trace, 99 hex digits |
| `B` | 0–31 | One 32-bit bitmap of occupied hash sets, 8 hex digits; bit 0 is the first set in that group |

Canonical metadata is `{side[0], requested_shares[31:0], price_index[12:0]}`.
For execute and cancel, `requested_shares` is the actual incoming amount;
for delete it is zero. The FPGA retains up to 128 quotes and 256 events. The
dashboard first reads all 32 `B` groups, then only occupied hash sets and
their referenced slots. It also reads the stash, active level RAM, top eight
free-stack entries, and all retained journal records. A completed scan is
shown only while its event count still matches the latest UART BBO.

Historical laptop receipt times are not in the FPGA, so the time-axis toggle
uses event numbers for pre-attach samples. A dense book can take longer than
the demo's six-second order interval to scan over 115200-baud UART; a new
completion aborts the prior scan and starts again. The VGA page renderer and
board navigation are separate unfinished work. The new bitmap and metadata
require the snapshot bitstream; the earlier RAM-readback bitstream does not
understand `B` and uses the older `E` width.
