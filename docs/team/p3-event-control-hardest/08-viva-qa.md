# Viva questions and model answers (owner 3)

Format: say **what → how → what if**. When the question crosses a boundary, name the signals.

## A. The sequencer

**1. What is `lob_core`?** A finite state machine that processes one event at a time. For each operation it follows a fixed schedule of states: read the memories, wait for their fixed latency, check legality, then **commit** all writes in one clock.

**2. Why a fixed schedule?** Memories have fixed latencies (hash 2, slot 1, price RAM 3, search 5). A fixed schedule gives **deterministic timing**: the same number of clocks regardless of how full the book is, with no data-dependent loops.

**3. What are the conditions for `event_ready`?** `state == ST_IDLE`, `init_done`, `book_valid`, `run_enable` (CPU enable) and `!feed_fault`.

**4. How many states does each operation take?** Add 6, execute/cancel/delete 10, replace 12, plus a 6-state search when the best level empties; plus accept, init and fail-stop states.

**5. What is a commit state?** The one state that performs all the writes (`ADD_C5`, `ECD_C9`, `REP_C10` and `C11`). All checks happen before, so a failed event writes nothing.

**6. Why does `ADD_C4` wait in place?** It uses `if (price_rd_valid)`, so it stays until the price RAM's 3-cycle read completes.

**7. What do the tasks do?** Named bundles of assignments, such as `fail`, `price_write`, `hash_insert`. A task call is textual substitution; it takes no extra time and sets registers in the same clock.

**8. Why are the command registers cleared at the top of the always block?** Later non-blocking assignments win, so clearing first and setting in a state makes every command a one-clock pulse automatically.

**9. How does the sequencer know if the BBO needs a search?** In `ECD_C8` / `REP_C8` it puts the level's side and index on `bbo_check_*`; `lob_bbo` answers `triggers_search` combinationally. If the level is the current best and its total becomes zero, a search runs.

## B. "What if" (sequencer)

**10. What if an order id is added twice?** `ADD_C3`: `hash_match_hit` → `fail(FAIL_DUP_OID)`: book invalid, fail-stop, nothing written.

**11. What if we execute an id that does not exist?** `ECD_C3`: no hash hit → `FAIL_MISSING_OID`.

**12. What if the quantity requested is larger than the order?** `ECD_C5` compares with the stored shares → `FAIL_QTY_UF`.

**13. What if all slots are used?** `free_empty` → `FAIL_NO_SLOT`.

**14. What if a price level would overflow 32 bits?** `ADD_C4` detects wrap-around (`sum < operand`) → `FAIL_QTY_OVF`.

**15. What if the network loses a message mid-event?** `feed_fault` overrides the state machine: `ST_FAIL_STOP`, error `0x0A`.

**16. What if the CPU never enables the book?** `run_enable` stays 0, `event_ready` stays 0: the producers wait, and events pile up behind the FIFOs.

**17. What if the event is out of the price window?** The OOW bit (set by the ITCH decoder; keyboard events never set it, they are rejected earlier by the price check) is seen in `ST_IDLE` → `FAIL_PRICE_OOW`, before any command.

**18. Why fail-stop rather than skip the bad event?** A skipped add or delete makes the book permanently different from the exchange's. The design shows an honest invalid book rather than silently wrong prices. The Python reference continues, the RTL stops; the golden test checks that difference explicitly.

**19. What does Replace do that is special?** It touches two price levels and two hash entries; it reuses the same slot; it uses two commit beats; and it handles "same price level" by chaining the arithmetic.

**20. How do you test the sequencer?** `tb_lob_golden` (31 events from a Python model, plus duplicate fail-stop) and `tb_lob_random` (512 random operations x 3 seeds against an independent dictionary after every commit, with 12 colliding ids).

## C. Decoder and trace

**21. Why is the decoder combinational?** It only inspects bits; no memory is needed. All outputs get defaults first, so no latches are created.

**22. Why must execute/cancel/delete have `pidx = 0` and `side = 0`?** They don't carry a price or side. The book already knows them from the slot table.

**23. What is the storage trace for?** To report exactly what the last event wrote (slot, hash insert/invalidate, up to two price levels) in a 316-bit record, used by UART `T:`, the VGA Events page and the history journal.

## D. Sources and merging

**24. Why do you need an arbiter?** One book input, two producers.

**25. How is fairness ensured?** `prefer_local` flips after each accepted event, so sources alternate when both are waiting.

**26. What is `locked` for?** Once an event is offered, the choice is frozen until accepted, so the data cannot change under the book while it waits.

**27. How do you know a keyboard order's result?** `order_merge` remembers `active_local` when the event is accepted and, one clock after `event_done`, records `lob_book_valid` and `lob_error_code` in `local_done_*`; the screen shows "accepted" or "rejected".

**28. Why do network counters stay accurate when typing orders?** Keyboard events don't pass through the network modules; the only shared point is `order_merge`, which doesn't touch the counters.

## E. Keyboard

**29. How does the keyboard connect?** USB keyboard → the board's HID helper chip → PS/2 clock and data on pins F4/B2. Only Boot HID keyboards work.

**30. How are bytes received?** On each falling edge of the (filtered) PS/2 clock the data bit is sampled; 11-bit frame: start, 8 data LSB-first, odd parity, stop. Bad parity or a 2 ms gap → `frame_error`.

**31. How does one press give one event even if the key repeats?** A 512-bit `held` bitmap: a make code is accepted only if its bit is clear; a break code clears it.

**32. What if the keyboard is unplugged and replugged?** `0xAA` or a 4-second idle timeout clears held keys; the form state (text, cursor, focus) is kept, because it lives in `keyboard_controls`.

**33. Why is the form text-based?** So invalid input stays visible and editable; numbers are derived by `form_parser` and checked.

**34. What does Esc do?** While editing a field, it restores the text saved when the edit began (`saved_*`) and sends nothing.

**35. Why can't I Tab away from an invalid field?** `focused_valid` must be true (the parser says `ok` and `current`); otherwise status "Invalid field".

**36. How do you avoid submitting a stale order?** `current_target` re-reads the real hash cell and slot at Enter and compares with the snapshot taken when the order was selected; any difference → "Order changed: reselect".

**37. How is the price turned into an index?** `price_divider`: `(price − base)/tick`, 32 cycles; remainder must be 0 (on tick) and the quotient ≤ 8191.

**38. Which actions exist and what do they map to?** A, F → add; E, C → execute; X → cancel; D → delete; U → replace. F and C have the same book effect as A and E.

**39. Why a double-dabble converter?** To show stored binary values as decimal digits on screen without a divider; it is small and takes 32 clocks.

## F. Cross-over questions

**40. Where do events come from?** Owner 1's `net_ingest` (network) and my keyboard path (through the 4-entry FIFO).

**41. What do you command?** Owner 2's memories, with one-cycle commands, and then wait fixed delays.

**42. Where do your results appear on the monitor?** Order Entry page (form, cursor, status), the book status in the header, the Events page (storage trace) and "Last local order accepted/rejected".

**43. Who unlocks the book?** The CPU (owner 4) by writing `1` to the LOB `CTRL` register.

**44. Who displays your status codes?** Owner 5's display CPU reads `status` (register word 0) and draws the message string.
