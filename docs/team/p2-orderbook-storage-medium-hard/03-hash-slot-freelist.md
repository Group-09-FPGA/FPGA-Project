# `lob_hash_table`, `lob_slot_table`, `lob_free_list`

These three together answer "where is order X, what is in it, and where can I put a new one?".

---

# Part A: `lob_hash_table` (`rtl/lob/lob_hash_table.v`)

## A1. Job

Map a 64-bit order id (the **key**) to an 11-bit **slot number**; tell the sequencer where a new key could be stored; support insert and delete.

## A2. Structure

```
              lookup_key, rd_set
                     │
   ┌─────────────────┼──────────────────────────────────────────┐
   │ way 0 RAM  way 1 RAM  ...  way 7 RAM   (each 1024 × 76 bits)  │  read all 8 in one cycle
   └─────────────────┬──────────────────────────────────────────┘
                     ▼ compare each valid way's key with key_q  (8 comparators in parallel)
   stash[0..7] registers ──► compare in parallel too
                     ▼
       match_hit / match_slot / match_way / match_is_stash / match_stash_idx
       free_way_avail / free_way_idx / free_stash_avail / free_stash_idx / bucket_full
```

### The way RAM (`lob_hash_way_ram`)

```verilog
(* ram_style = "block" *) reg [75:0] mem     [0:1023];   // used by the order logic
(* ram_style = "block" *) reg [75:0] dbg_mem [0:1023];   // identical copy for the display clock
always @(posedge clk) begin
    if (wr_en) begin mem[wr_set] <= wr_data; dbg_mem[wr_set] <= wr_data; end
    if (rd_en) rd_data <= mem[rd_set];                    // registered read: 1-cycle latency
end
always @(posedge dbg_clk) dbg_data <= dbg_mem[dbg_set];
```

Eight instances are created by a `generate` loop (`gen_way_bram`).

## A3. Reading (a lookup)

1. The sequencer asserts `hash_rd_en` with `hash_rd_set = hash_oid(id)` and `hash_lookup_key = id` for one clock.
2. The module registers the key (`key_q <= lookup_key`, `rd_en_q <= rd_en`): the RAM answer arrives one clock later, and the comparison must use *that* key.
3. A combinational block loops over the 8 ways and 8 stash entries:

```verilog
for (w_loop = HASH_WAYS-1; w_loop >= 0; w_loop--) begin
    if (way_rd_data[w_loop][HASH_VALID_BIT]) begin
        if (way_rd_data[w_loop][HASH_KEY_SLICE] == key_q) begin way_hit = 1; way_hit_slot = ...; way_hit_idx = w_loop; end
    end else begin found_free_way = 1; first_free_way = w_loop; end
end
```

The loop runs from way 7 down to 0, so **the lowest-numbered match / free way wins** (later assignments overwrite). The same is done for the stash.

4. Outputs: a **stash hit takes priority** over a way hit (`if (stash_hit) ... else if (way_hit)`); `match_hit` is 1 if either matched. `free_way_*` and `free_stash_*` report where a new key could go; `bucket_full = !found_free_way && !found_free_stash`.

`match_valid = rd_en_q` tells when the answer is meaningful.

## A4. Writing and deleting

The per-way write logic (`always @*` inside the generate loop) chooses what each way's RAM does this cycle, in priority order:

| Priority | Condition | Write |
| --- | --- | --- |
| 1 | `initializing` | address `init_cnt`, data **0** (clear every set, every way, at once) |
| 2 | `wr_way_en && wr_way_idx == this way` | address `wr_set`, data `{1, wr_slot, wr_key}` (insert) |
| 3 | `inv_way_en && inv_way_idx == this way` | address `inv_set`, data **0** (delete: valid bit cleared) |
| otherwise | | no write |

The **stash** is plain registers (`reg [75:0] stash [0:7]`) updated in a clocked block: `wr_stash_en` stores `{1, wr_slot, wr_key}` at `wr_stash_idx`; `inv_stash_en` clears the entry; `initializing` clears all.
Registers rather than RAM because they must all be compared in parallel and there are only 8.

## A5. Initialization

`init_start` begins a 1024-cycle sweep: `init_cnt` counts 0..1023, writing zeros to that row in every way. `init_done` pulses/stays high at the end. The stash is cleared immediately.

## A6. Worked example (collision)

Ids `0x100001`, `0x200002`, ... (the random test) all hash to set 0.

- First 8: each goes into a free **way** of set 0 (lowest free way first).
- 9th: `found_free_way = 0`, `found_free_stash = 1` → the sequencer uses the **stash** (`lat_is_stash = !free_way_avail && free_stash_avail`).
- Lookup of the 9th later: `stash_hit` → `match_is_stash = 1`, `match_stash_idx` set.
- Delete of it: `hash_remove(use_stash=1, ...)` → `inv_stash_en` clears that stash entry.

---

# Part B: `lob_slot_table` (`rtl/lob/lob_slot_table.v`)

## B1. Job

Store the details of each live order at the slot number the hash table gave: `{valid, side, pidx, shares}` (47 bits).

## B2. How it works

```verilog
(* ram_style = "block" *) reg [46:0] mem [0:2047];
assign eff_wr_en   = initializing ? 1 : wr_en;       // the init sweep owns the write port while initializing
assign eff_wr_addr = initializing ? init_cnt : wr_addr;
assign eff_wr_data = initializing ? 47'd0 : wr_data;
always @(posedge clk) if (eff_wr_en) mem[eff_wr_addr] <= eff_wr_data;
always @(posedge clk) if (rd_en) rd_data_reg <= mem[rd_addr];       // 1-cycle read
always @(posedge dbg_clk) dbg_data <= mem[dbg_addr];                // read-only display port
```

- One write port, one read port, one debug port.
- **Delete = write `valid = 0`** (the sequencer writes `{!lat_is_kill, ...}`); the entry is not erased.
- Replace **reuses the same slot** (new price and shares, new hash key), so slot numbers are stable.

## B3. Initialization

`init_cnt` sweeps 0..2047 writing zero (so `valid = 0`). 2048 cycles.

---

# Part C: `lob_free_list` (`rtl/lob/lob_free_list.v`)

## C1. Job

Know which of the 2048 slots are unused. A new order takes one; a dead order returns one.

## C2. A stack

`stack_mem[0..2047]` holds slot numbers; `sp` (stack pointer, 12 bits) is the **number of free slots**.

| State | `sp` | Stack contents |
| --- | --- | --- |
| after init | 2048 | `stack[i] = i`: every slot free; the top is slot **2047** |
| after 1 allocation | 2047 | top is now slot 2046 |
| after freeing slot 2047 | 2048 | slot 2047 pushed back on top |

That is why the first order placed in a fresh book lands in **slot 2047**, and the next in 2046 (you can see this on the Slots page and in the UART readback).

## C3. Pop is split in two (important design point)

```
 rd_top_en     (cycle N)   : top_slot_reg <= stack[sp-1];  top_valid_reg <= (sp > 0)
 ... sequencer checks the hash table, price overflow, etc. ...
 pop_commit    (commit cycle): sp <= sp - 1              // only now is the slot really taken
```

Reading the top does **not** change anything. Only `pop_commit` removes it. So if the sequencer discovers an error (duplicate id, price overflow), it simply never commits, and no slot is lost.

`push_en` writes `push_slot` at `stack[sp]` and increments `sp`.

## C4. Outputs

| Signal | Meaning |
| --- | --- |
| `top_slot`, `top_valid` | the next free slot (registered, 1 cycle after `rd_top_en`) |
| `empty` (`sp == 0`), `full` (`sp == 2048`) | `empty` makes an add fail with `FAIL_NO_SLOT` |
| `free_count` = `sp` | free slots |
| `active_count` = 2048 − `sp` | **live orders**, which becomes `lob_active_orders` everywhere (LEDs, UART `N:`, VGA) |

## C5. The always blocks

| Block | Job |
| --- | --- |
| `always @*` (`eff_wr_*`) | choose the write: init sweep writes `i → stack[i]`; a push writes `push_slot` at `sp`; otherwise none |
| `always @(posedge clk)` memory write | `if (eff_wr_en) stack_mem[eff_wr_addr] <= eff_wr_data;` (no reset, so it maps to block RAM) |
| `always @(posedge clk)` top read | `if (rd_top_en) top_slot_reg <= stack_mem[rd_addr];` |
| `always @(posedge clk or negedge rst_n)` | `top_valid_reg` |
| main FSM | `init_start` → sweep 0..2047 then `sp = 2048`; else pop/push updates of `sp` (pop and push in the same cycle cancel out) |

## C6. "What if"

- **Pop and push on the same cycle?** `sp` is unchanged; the code only decrements for `pop && !push` and increments for `push && !pop`.
- **Push when full?** Ignored (`!full`): the stack cannot overflow.
- **Free list empty and an add arrives?** `free_empty` → the sequencer fails with `FAIL_NO_SLOT` (error code 4).
