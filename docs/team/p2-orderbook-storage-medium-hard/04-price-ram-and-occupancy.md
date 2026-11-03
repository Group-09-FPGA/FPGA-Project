# `lob_price_ram` and `lob_occupancy`

These two answer "how many shares are at price P?" and "which price is the best?".

---

# Part A: `lob_price_ram` (`rtl/lob/lob_price_ram.v`)

## A1. Job

One 32-bit **total share count** per price level, for both sides: 16,384 entries addressed by `{side, pidx}`
(`side = 0` bid: addresses 0..8191; `side = 1` ask: 8192..16383).

*Analogy:* a tally board with one counter per price; when shares are added or removed at a price, you change that price's counter.
The tally is why the book never has to add up individual orders.

## A2. Code walkthrough

```verilog
(* ram_style = "block" *) reg [31:0] price_mem [0:16383];

assign eff_wr_en   = initializing ? 1'b1 : wr_en;
assign eff_wr_addr = initializing ? init_cnt[13:0] : wr_addr;
assign eff_wr_data = initializing ? 32'd0 : wr_data;
always @(posedge clk) if (eff_wr_en) price_mem[eff_wr_addr] <= eff_wr_data;     // write: immediate

always @(posedge dbg_clk) dbg_data <= price_mem[dbg_addr];                      // display / UART port

reg [31:0] stage1_data, stage2_data, stage3_data;
always @(posedge clk) if (rd_en) stage1_data <= price_mem[rd_addr];             // stage 1: the RAM read
always @(posedge clk) stage2_data <= stage1_data;                               // stage 2: delay
always @(posedge clk) stage3_data <= stage2_data;                               // stage 3: delay

reg stage1_valid, stage2_valid, stage3_valid;                                   // a matching valid shift register
always @(posedge clk or negedge rst_n) ... stage1_valid <= rd_en; stage2_valid <= stage1_valid; stage3_valid <= stage2_valid;

assign rd_data  = stage3_data;
assign rd_valid = stage3_valid;
```

### Why a three-stage read?

A large block RAM (16K × 32) has a slow output. Putting two extra register stages after it lets the design run at 50 MHz with comfortable timing margin.
The **price you pay is latency: the data arrives 3 clocks after `rd_en`**, signalled by `rd_valid`. The sequencer (owner 3) simply has wait states
(`ADD_C2..C4`, `ECD_C6..C8`) and checks `price_rd_valid`.

### Timing

```
 clock:     1        2         3         4
 rd_en      ─┐
 stage1     │  data(A)
 stage2                 data(A)
 stage3                           data(A)   rd_valid = 1 → sequencer uses rd_data here
```

## A3. Writes are immediate; reads and writes are independent

The sequencer reads the old level, computes the new total (old ± shares), and writes it back during the commit state. Because a write takes one clock and
the read pipeline is separate, the sequencer never reads a level while a write to it is still in flight.

## A4. Initialization

`init_start` sweeps `init_cnt` over all 16,384 addresses writing 0 (16,384 clocks ≈ 0.33 ms at 50 MHz). This is **the slowest init** and therefore sets how long the book is "not ready" after a reset.

## A5. The debug port

`dbg_*` is a second, read-only access on the 25 MHz UI clock. It feeds the **Levels** page (totals at each price) and the UART `?P` query. It cannot disturb the order logic.

## A6. "What if"

- **A level would overflow 32 bits?** The sequencer checks `(price_rd_data + shares) < price_rd_data` (wrap-around) and fails with `FAIL_QTY_OVF`; the RAM itself does not check.
- **Underflow?** Removing more than the level holds is caught by the sequencer: `FAIL_QTY_UF`.

---

# Part B: `lob_occupancy` (`rtl/lob/lob_occupancy.v`)

## B1. The problem it solves

When the best bid level becomes empty (its last order was cancelled), the book needs the **next best bid**: the highest price level that still has orders. Scanning up to 8192 levels would take thousands of clocks. A **bitmap tree** finds it in 5 clocks regardless of the book.

## B2. The tree (per side)

```
 level 0 :  l0[7:0]            8 bits      bit g = "any bit set in group g"
              │ each bit covers 32 words
 level 1 :  l1[255:0]          256 bits    bit w = "word w has any bit set"
              │ each bit covers one 32-bit leaf word
 leaves  :  leaf_mem[0:255]    256 words × 32 bits = 8192 bits   bit = "this price level has orders"
```

A price index splits into three fields:

```
 pidx[12:0] =  [12:10]  [9:5]   [4:0]
                  g       j       m
 group (0..7)  word within group (0..31)  bit within word (0..31)
 leaf word address = {g, j} = pidx[12:5]
```

*Analogy:* finding the first lit window in a skyscraper: look at the lobby board for the tower (level 0), then the floor board for that tower (level 1), then the room panel (leaf).
Three small lookups, no walking down every corridor.

Separate trees for bids (`leaf_mem_bid`, `l1_bid`, `l0_bid`) and asks (`..._ask`).

## B3. Updating (set or clear one bit)

Inputs: `leaf_upd_en`, `leaf_upd_side`, `leaf_upd_pidx`, `leaf_upd_bit_val` (1 = this level now has orders; 0 = it is now empty).

```verilog
wire [7:0] upd_word_addr = leaf_upd_pidx[12:5];
wire [4:0] upd_bit_pos   = leaf_upd_pidx[4:0];
upd_new_word_bid = leaf_mem_bid[upd_word_addr];          // read the old word (asynchronous read)
upd_new_word_bid[upd_bit_pos] = leaf_upd_bit_val;        // change one bit
// then in the clocked block:
leaf_mem_bid[upd_word_addr] <= upd_new_word_bid;         // write it back
l1_bid[upd_word_addr]       <= (upd_new_word_bid != 0);  // level 1 bit = does this word still have any bit?
l0_bid[g] <= (that group's 32 level-1 bits != 0);        // level 0 bit for each group, recomputed
```

This read-modify-write in a single clock is why the leaves are **distributed (LUT) RAM**: they have an asynchronous read. Level 1 and level 0 stay consistent automatically: clearing the last bit of a word clears its level-1 bit, and clearing the last level-1 bit of a group clears its level-0 bit.

## B4. Searching (the `SRCH_*` state machine)

`search_start` with `search_side` (0 = find the **highest** bid index, 1 = find the **lowest** ask index).

| State | What it does |
| --- | --- |
| `SRCH_IDLE` | on `search_start` (and not initializing), remember the side → `SRCH_S0` |
| `SRCH_S0` | look at `l0`. If zero: **side empty**: `search_done`, `search_valid = 0`. Else `srch_g` = highest (bid) / lowest (ask) set bit of `l0` |
| `SRCH_S1` | `srch_j` = highest/lowest set bit of that group's 32 level-1 bits (`l1[srch_g*32 +: 32]`) |
| `SRCH_S2` | issue the leaf read of word `{srch_g, srch_j}` (the module overrides its read port during this state) |
| `SRCH_S3` | `srch_m` = highest/lowest set bit of the leaf word that came back |
| `SRCH_S4` | `search_done`, `search_valid = 1`, `search_pidx = {srch_g, srch_j, srch_m}` → `SRCH_IDLE` |

The "highest/lowest set bit" are **priority encoders**, coded as `for` loops in functions (`prio_enc_high_8`, `prio_enc_high_32`, `prio_enc_low_8`, `prio_enc_low_32`). A `for` loop in a function *unrolls* into a fixed circuit; it is not a runtime loop.

```verilog
function [4:0] prio_enc_high_32;                 // highest set bit: the last assignment wins
    input [31:0] in; integer i;
    begin prio_enc_high_32 = 0; for (i = 0; i < 32; i = i + 1) if (in[i]) prio_enc_high_32 = i[4:0]; end
endfunction
```

## B5. Worked example

Bid levels with orders at index **5** and index **3000**.

- 5 = `{g=0, j=0, m=5}`; 3000 = `{g=2, j=29, m=24}` (2×1024 + 29×32 + 24 = 3000).
- State: `l0_bid` has bits 0 and 2 set; `l1_bid[0]` and `l1_bid[2*32+29 = 93]` set; leaf word 0 has bit 5; leaf word 93 has bit 24.
- **Search highest bid:** `S0`: highest set bit of `l0_bid` = **2**; `S1`: highest set bit of `l1_bid` group 2 = **29**; `S2/S3`: leaf word 93's highest bit = **24**; `S4`: `search_pidx = {2, 29, 24} = 3000` ✓.
- The sequencer then cancels the last order at 3000: it clears that bit (`leaf_upd_bit_val = 0`); leaf word 93 becomes 0 → `l1_bid[93] = 0` → group 2 has no words → `l0_bid[2] = 0`. Next search: `l0_bid` highest = 0, group 0 word 0, bit 5 → index **5**.

## B6. Other outputs

`bid_has_orders = (l0_bid != 0)` and `ask_has_orders = (l0_ask != 0)`: whether each side has any order at all (not used by the sequencer in the current design, but cheap and useful for debugging).

## B7. Initialization

256 clocks write zero to every leaf word in both leaf RAMs; `l1` and `l0` are cleared at `init_start`.

## B8. "What if"

- **The side is empty when a search is requested?** `S0` sees `l0 == 0`, returns `search_valid = 0`; the sequencer tells the BBO "this side is empty" (`bbo_search_valid = 0`, quantity 0).
- **Two orders at the same price, one cancelled?** The price RAM total drops but is not zero, so the sequencer does **not** clear the occupancy bit; only a level that reaches zero clears it.
- **Why not one big 8192-bit priority encoder?** It would be a huge, slow circuit. Three small encoders (8, 32, 32 bits) in sequence are tiny and fast.
- **How much memory is that?** Per side: 256 × 32 leaf bits + 256 + 8 = under 8.5 K bits, a small fraction of the chip.
