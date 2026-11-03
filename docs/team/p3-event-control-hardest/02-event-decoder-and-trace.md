# `lob_event_decoder` and `lob_storage_trace`

---

# Part A: `lob_event_decoder` (`rtl/lob/lob_event_decoder.v`, 131 lines)

## A1. Job

A purely **combinational** checker. Given the raw 256-bit event, it says: is it well formed (`evt_valid` / `evt_error` + `error_code`), and which operation is it (`is_add`, `is_exec`, `is_cancel`, `is_delete`, `is_replace`)? It also passes through the out-of-window flag as `price_oow`.

It is instantiated once inside `lob_core` as `u_decoder`. `lob_core` captures the decoder's outputs in `ST_IDLE` the moment an event is accepted.

## A2. The rules

Slicing (via `lob_defines.vh`): `evt_ver`, `evt_op`, `evt_side`, `evt_rsvd1`, `evt_oid`, `evt_noid`, `evt_shares`, `evt_pidx`, `evt_oow`, `evt_rsvd2`, `evt_seq`, `evt_rsvd3`.

**Global rules (checked first):**

| Rule | Failure |
| --- | --- |
| `evt_ver == 1` | `FAIL_EVT_FORMAT` |
| all reserved fields are zero (`rsvd1` 7 bits, `rsvd2` 2 bits, `rsvd3` 32 bits) | `FAIL_EVT_FORMAT` |
| opcode is 1..5 | `FAIL_INVALID_OP` |

**Per-operation rules:**

| Op | Requires | Must be zero |
| --- | --- | --- |
| **Add** | `oid != 0`, `shares >= 1` | `noid == 0`; if `oow` then `pidx == 0` |
| **Execute / Cancel** | `oid != 0`, `shares >= 1` | `noid == 0`, `pidx == 0`, `side == 0`, `oow == 0` |
| **Delete** | `oid != 0` | `shares == 0`, `noid == 0`, `pidx == 0`, `side == 0`, `oow == 0` |
| **Replace** | `oid != 0`, `noid != 0`, `shares >= 1` | `side == 0`; if `oow` then `pidx == 0` |

Note that execute, cancel and delete **do not carry a price or side**: the book already knows them from the slot table (that is why `pidx` and `side` must be 0 in those events). Replace carries a new price (`pidx`) but the **side** is taken from the stored order.

## A3. The one `always` block

```verilog
always @* begin
    evt_valid = 0; evt_error = 0; error_code = FAIL_NONE;     // defaults for every path (no latches)
    if (!ver_ok || !rsvd_ok)       begin evt_error = 1; error_code = FAIL_EVT_FORMAT; end
    else if (!op_legal)            begin evt_error = 1; error_code = FAIL_INVALID_OP;  end
    else case (evt_op)
        OP_ADD:     if (evt_oid == 0 || evt_shares == 0 || evt_noid != 0 || (evt_oow && evt_pidx != 0)) ... error ... else evt_valid = 1;
        OP_EXECUTE, OP_CANCEL: ...
        OP_DELETE:  ...
        OP_REPLACE: ...
    endcase
end
```

**Why is every output assigned at the top?** In a combinational block, any signal that is *not* assigned on some path becomes a **latch** (memory) in hardware, an unintended circuit. Assigning defaults first guarantees every path drives every output.

## A4. Worked examples

| Event | Result |
| --- | --- |
| Add, id 0x2001, 300 shares, side buy, pidx 5 | `evt_valid = 1` |
| Add with 0 shares | `evt_error`, `FAIL_EVT_FORMAT` |
| Execute with `pidx = 7` | `evt_error`: executes must not carry a price |
| Opcode 9 | `FAIL_INVALID_OP` |
| Version 2 | `FAIL_EVT_FORMAT` |

## A5. "What if"

- **Why check legality in hardware if the ITCH decoder already builds events correctly?** Because **keyboard** events come from a different builder, and defensive checking costs only gates. An illegal event must never reach the memories.
- **How is this tested?** `tb_lob_event_decoder` exercises every rule above (the log shows `[PASS] version triggers FAIL_EVT_FORMAT`, etc.).

---

# Part B: `lob_storage_trace` (`rtl/lob/lob_storage_trace.v`, 87 lines)

## B1. Job

Watch the memory write enables during **one** event and package what was written into a single **316-bit** record, published when the event completes. Others use it:
- UART: the `T:` field of the status line (so a laptop can see exactly which RAM entries changed),
- VGA: the **Events** page,
- `lob_display_journal`: stores one per event in its 256-entry ring.

It is instantiated once in `lob_core` as `u_trace`.

## B2. What one event can write (so the record has fixed size)

At most: **one** slot-table write, **one** hash insertion, **one** hash invalidation, and **two** price-level writes (replace with a price change touches the old and the new level).

## B3. The record (most significant first)

| Field | Bits | Meaning |
| --- | --- | --- |
| valid | 1 | a completed event |
| op | 4 | opcode |
| oid, noid | 64 + 64 | the ids |
| slot write: valid, address, data | 1 + 11 + 47 | the slot-table write |
| hash invalidation: valid, set, index, is-stash | 1 + 10 + 3 + 1 | the entry removed |
| hash insertion: valid, set, index, is-stash | 1 + 10 + 3 + 1 | the entry written |
| price write 0: valid, address, quantity | 1 + 14 + 32 | first level written |
| price write 1: valid, address, quantity | 1 + 14 + 32 | second level written |
| **total** | **316** | |

## B4. How it collects

Per-event collector registers (`slot_v`, `inv_v`, `ins_v`, `p0_v`, `p1_v`, plus address/data registers) are cleared when a new event starts and filled when write enables pulse:

```verilog
if (event_done) trace <= {1'b1, op, oid, noid, slot_v, slot_addr, slot_data, inv_v, ..., p1_v, p1_addr, p1_qty};
if (event_accept) clear the collectors;
else begin
    if (slot_wr_en)               begin slot_v <= 1; slot_addr <= slot_wr_addr; slot_data <= slot_wr_data; end
    if (inv_way_en || inv_stash_en) begin inv_v <= 1; ...; end
    if (ins_way_en || ins_stash_en) begin ins_v <= 1; ...; end
    if (price_wr_en) if (!p0_v) {first} else {second}
end
```

- The first price write goes into `p0`, the second into `p1`.
- For a **stash** entry, the "set" recorded is the hash of the id (`hash_oid`), since stash entries have no set of their own; `lob_core` computes it and passes it in (`inv_set`, `ins_set`).
- `event_done` and `event_accept` can occur on the same clock (back-to-back events): the module **publishes the old record before clearing**, which is why `trace <= ...` is above the clearing code.

## B5. Why it matters

It reports **committed** writes straight from the real write enables, not a second copy of the algorithm: the laptop dashboard and VGA compare the trace against the actual RAM contents, so a bug would show up as a mismatch.

## B6. Example (Add: id 0x2001, buy 300 @ index 5, first order in a fresh book)

| Field | Value |
| --- | --- |
| slot write | valid, address **2047** (first free slot), data `{1, 0, 5, 300}` |
| hash insertion | valid, set **9** (`0x2001`: low 10 bits = 1, next 10 bits = 8, 1 XOR 8 = 9), way 0, not stash |
| hash invalidation | not valid |
| price write 0 | valid, address `{0, 5} = 5`, quantity 300 |
| price write 1 | not valid |
