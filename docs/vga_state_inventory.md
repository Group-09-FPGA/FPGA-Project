# Data needed for the VGA dashboard

The laptop dashboard is a useful design preview, but the final VGA renderer
must get its live data from the FPGA. The table separates data the book already
stores from state currently added by Python.

| View or behavior | Current source | FPGA requirement |
| --- | --- | --- |
| Current bid, ask, spread, quantities, active count, validity | FPGA BBO/status, already sent over UART | Already in FPGA; route every field to VGA |
| Price base and tick for price indexes | Python assumed 900000/1000 | **Added:** FPGA config in UART `BASE`/`TICK`; dashboard now uses those values. VGA price formatting still needs them |
| Dollar formatting and chart scale | Python converts raw 1/10000-dollar units to decimal and chooses dynamic chart range | Implement decimal conversion and chart scaling in VGA renderer; current VGA text still prints hexadecimal after `$` |
| Bid/ask chart and quote-history page | Python keeps 128 UART quote samples and 100 change descriptions | **Added:** 128-entry FPGA quote ring with event number, both prices, quantities and valid flag. VGA can read samples; chart drawing and UART history replay remain |
| Ethernet→book pipeline | FPGA counters in UART; VGA previously had only some | **Added:** RX, UDP, Mold, ITCH, FIFO, completed, and error values reach VGA; the full pipeline page layout remains |
| Active orders and slot map | FPGA has a 2,048-entry slot RAM, but ID is in hash RAM; Python reconstructs an ID→slot view from write traces | **Added:** VGA-clock read-only ports for slot and hash RAM. Orders/Slots renderer still needs to combine them |
| Hash sets, ways, stash | FPGA already has 1,024×8 entries and 8 stash entries | **Added:** read-only way and stash ports; full set paging remains |
| Price-level quantities and order counts | FPGA already has a 16,384-entry quantity RAM; Python derived order counts | **Added:** read-only quantity port and a separate FPGA 16,384-entry order-count index updated by add, full removal, and price-changing replace. Full nonzero-level paging remains |
| Free-stack contents and next slot | FPGA has a 2,048-entry LIFO free-list RAM | **Added:** read-only free-list port; full stack browsing remains |
| Event list | Python keeps every received/confirmed event for the session | **Added:** 256-entry FPGA ring of event number and committed storage trace, with a saturating count and wrapping pointer. Full paged renderer and UART replay remain |
| Page, selection, scroll | Python curses state, keyboard and mouse | **Partial:** SW2/SW3 browse four recent board history records. Seven-page navigation and selected set/slot/level registers still need the remaining available switches and buttons; physical SW0/1 are broken and SW14/15 are reserved for seven-segment |
| Clock receipt time | Laptop wall clock | Keep only on laptop as agreed; VGA uses FPGA event numbers |
| Event/time axis toggle | Laptop UI state | Keep time mode on laptop as agreed; VGA chart will use event numbers |
| Host prediction comparison | Independent Python model | Keep on laptop; duplicating the prediction inside the FPGA would remove the independent check |
| Simulated demo data | Python `--demo` | Keep on laptop as a clearly labelled practice mode |

## UART RAM readback

The laptop can now request selected slot, hash set, stash, price quantity,
price order count, free-stack, quote-journal, and event-journal addresses using
the read-only `?TYPEADDR` UART protocol. The FPGA shares its VGA memory read
ports for these requests and returns the current RAM contents. After every
confirmed event, the terminal requests the addresses named by the FPGA write
trace and marks values as verified only when the returned RAM value matches.
The independent host prediction remains a second comparison. See
[storage_trace_uart.md](storage_trace_uart.md) for field widths and limits.

The storage trace in [storage_trace_uart.md](storage_trace_uart.md) is based on
actual FPGA write controls. It lets the laptop reconstruct a live view from
reset. The new read ports let VGA inspect the actual RAM at arbitrary
addresses. The current VGA code shows the latest four quote/event records
selected by physical SW2/SW3 and a compact current RAM readout for the
selected event, including its current price-level order count. It does not yet
draw the Kitty-style charts or seven pages.
A timing-checked candidate bitstream has been built in
`build_readback_20261102/top_system.bit`; physical board verification is pending.
