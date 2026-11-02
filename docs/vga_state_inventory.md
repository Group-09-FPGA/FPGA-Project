# Data needed for the VGA dashboard

The laptop dashboard is a useful design preview, but the final VGA renderer
must get its live data from the FPGA. The table separates data the book already
stores from state currently added by Python.

| View or behavior | Current source | FPGA requirement |
| --- | --- | --- |
| Current bid, ask, spread, quantities, active count, validity | FPGA BBO/status, already sent over UART | Already in FPGA; route every field to VGA |
| Price base and tick for price indexes | FPGA UART `BASE`/`TICK` | The dashboard requires both values; VGA price formatting still needs them |
| Dollar formatting and chart scale | Python converts raw 1/10000-dollar units to decimal and chooses dynamic chart range | Implement decimal conversion and chart scaling in VGA renderer; current VGA text still prints hexadecimal after `$` |
| Bid/ask chart and quote-history page | 128-entry FPGA quote ring | VGA can read samples; VGA chart drawing remains |
| Ethernet→book pipeline | FPGA counters in UART; VGA previously had only some | **Added:** RX, UDP, Mold, ITCH, FIFO, completed, and error values reach VGA; the full pipeline page layout remains |
| Active orders and slot map | FPGA slot RAM and hash RAM, fetched after each event | VGA Orders/Slots renderer still needs to combine them |
| Hash sets, ways, stash | FPGA already has 1,024×8 entries and 8 stash entries | **Added:** read-only way and stash ports; full set paging remains |
| Price-level quantities and order counts | FPGA already has a 16,384-entry quantity RAM; Python derived order counts | **Added:** read-only quantity port and a separate FPGA 16,384-entry order-count index updated by add, full removal, and price-changing replace. Full nonzero-level paging remains |
| Free-stack contents and next slot | FPGA has a 2,048-entry LIFO free-list RAM | **Added:** read-only free-list port; full stack browsing remains |
| Event list | FPGA journal read back over UART | **Added:** 256-entry FPGA ring of event number, canonical side/shares/price index, and committed storage trace. Older records wrap after 256 events |
| Page, selection, scroll | Python curses state, keyboard and mouse | **Partial:** SW2/SW3 browse four recent board history records. Seven-page navigation and selected set/slot/level registers still need the remaining available switches and buttons; physical SW0/1 are broken and SW14/15 are reserved for seven-segment |
| Clock receipt time | Laptop wall clock | Keep only on laptop as agreed; VGA uses FPGA event numbers |
| Event/time axis toggle | Laptop UI state | Keep time mode on laptop as agreed; VGA chart will use event numbers |
| Host prediction comparison | Independent Python model | Keep on laptop; duplicating the prediction inside the FPGA would remove the independent check |
| Simulated demo data | Python `--demo` | Keep on laptop as a clearly labelled practice mode |

## UART RAM readback

The laptop requests slot, hash set, stash, price quantity, price order count,
free-stack, quote-journal, and event-journal addresses with the read-only
`?TYPEADDR` UART protocol. `B` returns a 32-bit occupied-set bitmap for one
group of 32 hash sets. A new dashboard starts with zero book state: after a
board completion counter arrives, it reads all 32 bitmaps, occupied hash sets,
all stash entries, referenced slots, active price levels, the top eight free
stack entries, and all retained quote/event records. It publishes those values
as one snapshot only if the board completion counter is still the same. The
independent host prediction remains a separate check when the sender has been
observed from event 1. See [storage_trace_uart.md](storage_trace_uart.md) for
field widths and limits.

The dashboard now rebuilds both charts, orders, levels, hash map, slot map,
events, and status from FPGA readback after every event. It can attach after
earlier orders without replaying the sender log. Laptop receipt times from
before attachment are inherently unavailable; historical chart points use
FPGA event numbers. The FPGA retains 128 quotes and 256 event records. The
dashboard reads the top eight free-stack entries because only those appear on
the current page; the rest remain queryable individually. The readback scan
cost grows with the number of active hash sets and orders, so sustained or
dense books can take longer than the six-second demo interval.

The storage trace in [storage_trace_uart.md](storage_trace_uart.md) is based on
actual FPGA write controls. It lets the laptop reconstruct a live view from
reset. The new read ports let VGA inspect the actual RAM at arbitrary
addresses. The current VGA code shows the latest four quote/event records
selected by physical SW2/SW3 and a compact current RAM readout for the
selected event, including its current price-level order count. It does not yet
draw the Kitty-style charts or seven pages.
The earlier RAM-readback bitstream was physically verified on 2026-11-02.
The occupied-set bitmap and enriched journal require a new bitstream; the
current source has passed RTL simulation but has not yet been tested on board.
