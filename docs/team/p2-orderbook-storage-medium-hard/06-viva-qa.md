# Viva questions and model answers (owner 2)

## A. Basics

**1. Why does the book need a hash table?** To find an order by its 64-bit id in constant time. Scanning all 2048 slots would take up to 2048 clocks.

**2. Why a separate slot table?** The hash table only maps *id → slot number*. The slot table holds the actual order details (side, price index, shares) at that slot number, so details can be updated without moving hash entries.

**3. What is in a hash entry and a slot entry?** Hash: 76 bits `{valid, slot[10:0], key[63:0]}`. Slot: 47 bits `{valid, side, pidx[12:0], shares[31:0]}`.

**4. What is the hash function?** The 64-bit id is split into 10-bit chunks and XOR-ed together (seven chunks; the top has 4 bits) giving a 10-bit set number.

**5. Why store the full key in the hash entry?** Because different ids can hash to the same set; the full key is how a lookup tells them apart.

**6. Why a free list?** To hand out an empty slot in constant time. A stack: the top is always a free slot.

**7. Why is pop split into read and commit?** So the sequencer can check the other conditions first. If something fails, no slot is consumed.

**8. What is the price RAM for?** One total quantity per price level, so the best-level quantity never requires adding up individual orders.

**9. What is the price index?** `(price − base)/tick`: a small integer. Base and tick come from the CPU. 8192 levels per side.

**10. What does the occupancy tree do?** It finds the next-best occupied price level in 5 clocks when the best level empties.

## B. "What if" questions

**11. What if two ids hash to the same set?** They go into different ways of that set (8 ways). If all 8 ways are used, the id goes into the shared 8-entry stash.

**12. What if the ways and the stash are both full?** `hash_bucket_full` → the add fails with `FAIL_HASH_FULL` and the book fail-stops.

**13. What if an id is added twice?** The lookup hits (`hash_match_hit`), so the sequencer fails with `FAIL_DUP_OID` before writing anything.

**14. What if I cancel more shares than the order has?** The slot data shows fewer shares than requested: `FAIL_QTY_UF`.

**15. What if all 2048 slots are used?** `free_empty` → `FAIL_NO_SLOT`.

**16. What if the best bid level is emptied?** `triggers_search` is 1, so the sequencer starts an occupancy search for the next best, reads that level's quantity from the price RAM, and writes it into the BBO. If no bids remain, `bbo_search_valid = 0` and the bid side reads 0.

**17. What if the best level is only partly executed?** The fast path updates the BBO quantity (`pidx == best`, `qty > 0`).

**18. What if an order is added at a worse price than the best?** It is stored and counted in the price RAM, but the BBO ignores it.

**19. What if a price level exceeds 32 bits?** The sequencer detects wrap-around when adding and raises `FAIL_QTY_OVF`; the RAM does not check.

**20. What if we replaced the price RAM with a counter array in flops?** 16,384 × 32 flops is far too large; block RAM is the efficient choice, at the price of a 3-cycle read.

**21. Why is the price RAM read 3 cycles late?** The large RAM output is slow; two extra pipeline registers let the design meet timing at 50 MHz.

**22. Why are the occupancy leaves in distributed RAM and not block RAM?** The update does a read-modify-write of one word in a single clock. That needs an asynchronous read, which distributed RAM provides.

**23. Why is there a second read port on every memory?** So the VGA, UART readback and the keyboard order browser can read the real data without interfering with the sequencer; it runs on the 25 MHz display clock.

**24. What are the risks of the second port?** Reading an address in the same cycle it is written is not a coherent snapshot. The display tolerates that; the keyboard's order browser re-verifies the order before it submits anything.

## C. Numbers and capacity

**25. How many orders can the book hold?** 2048 (the slot table / free list size).

**26. How many price levels?** 8192 per side, 16,384 total.

**27. What price range does that cover?** 8192 × tick; with the default tick of $0.1000, a window of $819.20 above the base price.

**28. How long is initialization?** The price RAM sweep dominates: 16,384 clocks ≈ 0.33 ms at 50 MHz.

**29. Why does the first order land in slot 2047?** The free-list stack is initialized with `stack[i] = i` and `sp = 2048`, so the top is 2047.

**30. How is the best price turned into a price?** `price = base + pidx × tick` through a two-stage pipeline (multiply, then add), so the published price lags the index by 2 clocks.

## D. Cross-over questions

**31. Who tells you when to read and write?** Owner 3's `lob_core` sequencer, with one-cycle commands. I only answer after fixed delays.

**32. Who tells you the base and tick?** The CPU (owner 4) writes them into the LOB MMIO registers before the book is enabled; they reach `lob_bbo` through `lob_core`.

**33. Where do your outputs end up on the screen?** The Orders, Hash, Slots and Levels pages read my memories directly through the second port; the Market page header and chart use the best bid/ask and the history journal built from the BBO.

**34. Where does the network come in?** Owner 1's events arrive as 256-bit canonical events; owner 3's sequencer turns them into commands to me.

**35. What happens to your memories on a fail-stop?** Nothing is erased; the sequencer simply stops accepting events. `book_valid` goes to 0, so the displays show the book as invalid until a reset (which re-initializes all memories).

## E. Tests

**36. How do you prove the book is right?** `tb_lob_golden` replays 31 events generated by a Python model and compares the BBO, quantities and order count after every commit; it also checks that a duplicate order fail-stops. `tb_lob_random` runs 512 random operations for each of three seeds, with 12 ids deliberately forced into hash set 0 so the collision and stash paths are exercised, and compares against an independent dictionary book after every commit.

**37. Why test with colliding ids?** The collision and stash paths are rare in normal traffic, so they would otherwise stay untested.
