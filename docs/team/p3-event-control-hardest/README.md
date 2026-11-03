# Owner 3: Event control: the sequencer, legality, keyboard orders and source merging  (difficulty: hardest)

## Your 30-second pitch

> "I own the brain of the order book. Every event, whether it came from Ethernet or the keyboard, passes through my blocks.
> `order_merge` and its arbiter pick one source at a time. `lob_event_decoder` checks the event is legal. `lob_core` is a state machine that runs a
> fixed, cycle-by-cycle script for each of the five operations (add, execute, cancel, delete, replace) by issuing one-cycle commands to the memories, and it stops
> the book (fail-stop) the moment anything is impossible. I also own the **keyboard order path**: the PS/2 receiver and key decoder, the order form with its validation,
> and the helper blocks that parse numbers, divide the price into an index, and convert numbers to decimal text."

## Your modules

| Module | File | Lines | One-line job |
| --- | --- | --- | --- |
| `lob_core` | `rtl/lob/lob_core.v` | ~870 | the sequencer: the per-operation state machine |
| `lob_event_decoder` | `rtl/lob/lob_event_decoder.v` | 131 | combinational legality check of a 256-bit event |
| `lob_storage_trace` | `rtl/lob/lob_storage_trace.v` | 87 | records what the last event wrote (316-bit trace) |
| `order_source_arbiter` | `rtl/ui/order_source_arbiter.v` | 26 | network vs keyboard: one at a time, fairly |
| `order_merge` | `rtl/ui/order_merge.v` | ~60 | local FIFO + arbiter + result bookkeeping for keyboard orders |
| `ps2_receiver`, `ps2_key_decoder` | `rtl/ui/ps2_keyboard.v` | 159 | PS/2 bits → bytes → key presses |
| `keyboard_controls` | `rtl/ui/keyboard_controls.v` | ~370 | order form, navigation, order browser, validation, event builder |
| `form_parser` | `rtl/ui/form_parser.v` | ~100 | text fields → numbers, with syntax checks |
| `price_divider` | `rtl/ui/price_divider.v` | ~40 | 32-cycle divider: price → index |
| `bin_to_decimal` | `rtl/ui/bin_to_decimal.v` | ~45 | double-dabble converter for the order browser |

You use (but do not own) the memories (owner 2) and the display (owner 5).

## Tests you can run live

```bash
tb_lob_golden               # 31 golden events + duplicate fail-stop
tb_lob_random               # 512 random ops x 3 seeds vs an independent book
tb_lob_event_decoder        # every legality rule
tb_order_source_arbiter     # mixed sources under backpressure
tb_ps2_keyboard             # framing, parity, make/break, extended codes
tb_keyboard_controls        # editing, Esc restore, validation, Add submission
tb_keyboard_actions         # all seven actions, stale-order rejection
tb_keyboard_hotplug         # unplug/replug keeps the form, clears held keys
```

## Reading order

1. [00-system-in-10-minutes](../00-system-in-10-minutes.md)
2. [01-the-system-from-my-seat](01-the-system-from-my-seat.md)
3. [02-event-decoder-and-trace](02-event-decoder-and-trace.md)
4. [03-lob-core-part1-structure-and-add](03-lob-core-part1-structure-and-add.md)
5. [04-lob-core-part2-execute-replace-search](04-lob-core-part2-execute-replace-search.md)
6. [05-order-sources](05-order-sources.md)
7. [06-ps2-keyboard-hardware](06-ps2-keyboard-hardware.md)
8. [07-keyboard-controls-and-helpers](07-keyboard-controls-and-helpers.md)
9. [08-viva-qa](08-viva-qa.md)

## The facts you must be able to state without looking

1. `event_ready = (state == ST_IDLE) && init_done && book_valid && run_enable && !feed_fault`.
2. **Every error in fail-stop mode** sets `error_valid`/`error_code`, clears `book_valid`, and parks in `ST_FAIL_STOP` until reset.
3. Add = 6 states, Execute/Cancel/Delete = 10, Replace = 12, plus a 6-state best-price search; all fixed schedules.
4. Waiting states exist because the memories have fixed latencies (hash 2, slot 1, price RAM **3**, search 5).
5. The **commit** states (`ADD_C5`, `ECD_C9`, `REP_C10`/`C11`) are the only ones that write.
6. The arbiter **alternates** sources and **holds its choice** while an event waits (`locked`).
7. Keyboard: one event per physical press (`held` bitmap); invalid fields **block Tab**; Esc restores the pre-edit text; a selected order is **re-verified** at Enter.
