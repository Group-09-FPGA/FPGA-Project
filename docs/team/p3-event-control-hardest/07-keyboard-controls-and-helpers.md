# `keyboard_controls` and its helpers

Files: `rtl/ui/keyboard_controls.v` (~370 lines), `form_parser.v`, `price_divider.v`, `bin_to_decimal.v`. Instantiated inside `display_system` (UI clock, 25 MHz).

## 1. Job

The keyboard **front panel**. It keeps the order form, tracks which page and field have focus, lets the user browse real orders in the book, validates everything, and finally builds a 256-bit canonical event.
It is deliberately **text-backed**: the form holds *characters*, not numbers, so invalid input stays visible and fixable.

## 2. The pages and focus

| Page | Name | Page | Name |
| --- | --- | --- | --- |
| 0 | Market | 5 | Levels |
| 1 | Orders | 6 | Slots |
| 2 | Hash | 7 | **Order Entry** |
| 3 | Events | 8 | Quote history |
| 4 | Status | | |

On the Order Entry page, `focus` runs: **0 action**, **1 side**, **2 price**, **3 quantity**, **4 order id**, **5 new id**, **6 orders list**.

## 3. The keys

| Key | Effect |
| --- | --- |
| `F1`..`F8` or `1`..`8` (outside numeric editing) | pages 0..7 |
| `H` | quote history page |
| `Tab` / `Shift+Tab` | next / previous focus; **blocked if the focused field is invalid** (status "Invalid field") |
| Action field: `Left`/`Right` or `A F E C X D U` | choose the ITCH action |
| Side field: `Left`/`Right` | Buy / Sell (adds only) |
| Numeric fields: digits, `.` (price), `A`-`F` (ids) | edit; the first typed character **replaces** the old text and starts an edit |
| `Left`/`Right`, `Backspace`, `Delete` | move cursor / repair |
| `Esc` while editing | **restore** the text from before the edit; no order sent |
| `Up`/`Down` on Orders (or the list on Order Entry) | **browse** real orders |
| `Enter` on Orders with an order selected | load its stored values into Order Entry |
| `Enter` on Order Entry | submit (once per press) |
| `PageUp`/`PageDown` | scroll long lists/history |

## 4. State registers (what to name in a viva)

| Register | Meaning |
| --- | --- |
| `page`, `focus`, `action`, `side` | the screen state and chosen action |
| `field_text[0..3]` (128 bits each = 16 chars), `field_len[]`, `field_cursor[]` | price, quantity, id, new id |
| `editing`, `saved_text/len/cursor/field` | whether a field is mid-edit and the pre-edit copy that **Esc** restores |
| `status[4:0]` | message code shown on screen |
| `selected_valid`, `selected_id`, `selected_qty`, `selected_price_index`, `selected_side` | the order picked from the book (browsing) |
| `hash_set`, `hash_way`, `stash_selected`, `slot_addr`, `level_addr`, `free_offset`, `history_offset` | list positions on the pages |
| `scan_state`, `scanned`, `scan_reverse`, `ram_wait` | the order-browser state machine |
| `validate_wait` | the Enter-validation sequencer (0 idle, 1..6) |
| `local_sequence` | the sequence number put into the next event; increments per submitted order |
| `pending_event`, `event_valid`, `event_data` | the event under construction / ready |

## 4a. Status codes shown on screen

`0 Ready, 1 Queued, 2 Sent to core, 3 Invalid field, 4 Queue busy, 5 Invalid price or tick, 6 Invalid quantity, 7 Invalid order ID, 8 Order changed: reselect, 9 Disabled, 10 Book invalid, 11 Quantity exceeds stored order`.

## 5. The helpers

### `form_parser`: text → numbers (always converting)

A tiny serial parser cycling through the four fields:

- `index == 0`: load field `field`'s text and length; clear the accumulator `acc`.
- `index 1..16`: one character per clock: `acc <= acc*10 + digit` (decimal) or `acc <= (acc << 4) + hex_value(ch)` (ids). The decimal point is skipped.
- `index == 16`: store `value_r[field]`, `text_r[field]`, `length_r[field]`, compute `ok[field]`, move to the next field.

So each field is re-parsed every **4 × 17 = 68 clocks**. Two outputs per field:

| Output | Meaning |
| --- | --- |
| `ok[i]` | **syntax and range valid** |
| `current[i]` | the parsed value still matches the text now in the form (`text_r[i] == text[...] && length_r[i] == lengths[...]`) |

Syntax rules (`syntax_valid`): price is `digits.dddd` with **exactly four** decimals and at most 11 characters; quantity at most 10 digits; ids accept 0-9, A-F; every field must be non-empty. Range: price ≤ 0xFFFFFFFF; quantity non-zero and ≤ 0xFFFFFFFF; ids non-zero.

Why `current`? Enter must never send a number older than the text on screen. The Enter sequencer waits for `all_parsed_current`.

### `price_divider`: price → price index

`index = (price − base) / tick`. The restoring divider, one quotient bit per clock for 32 clocks:

```verilog
wire [32:0] shifted = {rem[31:0], q[31]};
wire take = shifted >= {1'b0, divisor};
assign remainder = take ? shifted - divisor : shifted;
assign quotient  = {q[30:0], take};
assign finishing = busy && count == 31;
```

On `finishing` the controller checks: **`remainder == 0`** (the price is on a tick) and **`quotient <= 8191`** (inside the window); otherwise status 5 "Invalid price or tick".

### `bin_to_decimal`: binary → decimal digits (double dabble)

To display a browsed order's price and quantity as decimal text, the controller needs decimal digits. Algorithm ("shift and add 3"): for each of the 32 bits, first add 3 to every BCD digit that is ≥ 5, then shift the whole register left bringing in the next bit.

Example, converting 13 (binary `1101`), tracking BCD:
```
start bcd=0000 0000, bin=1101
shift bit1: 0000 0001                       (no digit ≥ 5)
shift bit1: 0000 0011
digit 3 < 5; shift bit0: 0000 0110
digit 6 ≥ 5 → +3 = 9;  shift bit1: 0001 0011   → tens=1, ones=3  → "13"
```
`step` advances one bit; `last` marks the 32nd step; `digits` shows the current result. The controller steps it only when the RAM data is stable (`scan_go`).

## 6. The big always block, step by step

Each clock, in this order (later assignments in the same block win):

| # | What | Notes |
| --- | --- | --- |
| 1 | **Event handshake**: when `event_valid && event_ready`: `event_valid <= 0`, `status <= 2` ("Sent to core"), `local_sequence++`; if it was an Add, put `id + 1` into the id field; if a Replace, put `new id + 1` into the new-id field | so repeated Adds get fresh ids automatically |
| 2 | **Divider result** (`div_finishing`): reject if `remainder != 0` or `quotient > 8191` (status 5); else `event_data <= pending_event | (quotient[12:0] << 67)` and `event_valid <= 1` | the index goes into bits 79:67 |
| 3 | **Order browser** (`scan_state != 0`) | see section 7 |
| 4 | **Validation sequencer** (`validate_wait != 0`) | see section 8 |
| 5 | **Key handling** (`key_valid && validate_wait == 0`): a long `if / else if` chain: page keys, Tab, Esc, action/side fields, numeric editing, list browsing, PageUp/Down | |
| 6 | **Enter on Order Entry**: if `!event_valid && !dividing && scan_state == 0` then `validate_wait <= 1` | this is why a held Enter or a second Enter during a pending event does nothing |
| 7 | **Final checks** when `validate_wait == 6 && !ram_paused` | see section 8 |

Keys are ignored while validation is running (`validate_wait == 0` is required), so the form cannot change mid-check.

## 7. The order browser (`scan_state`)

**Goal:** step through the *real* hash table to find the next live order and load its stored values.

| `scan_state` | Meaning |
| --- | --- |
| 0 | idle |
| 1 | reading a hash cell (way `hash_way` of set `hash_set`, or the stash): after `ram_wait == 3` (RAM settled) check the cell's valid bit: valid → `slot_addr <= cell slot; selected_id <= cell key; scan_state <= 2`; invalid → `advance_hash(direction)` and try the next cell; after 8200 cells with no hit: `status <= 8` |
| 2 | slot read: capture `selected_valid`, `selected_qty`, `selected_price_index`, `selected_side` and start the decimal conversions |
| 3 | converting (32 `fmt_step`s); on `fmt_last` fill the price field (`dddd.dddd` style with the decimal point at position 6), quantity field, id field, `side`, and leave editing |

`advance_hash(backwards)` walks `hash_way` 0..7, then `hash_set` (0..1023), then the stash (8 entries), wrapping around. `ram_paused` (the UART readback is using the RAM ports) pauses the scan (`ram_wait <= 0`).

While scanning, `scan_busy = 1` and `ram_hold = 1`, which tells `ram_ports` the keyboard owns the slot/hash read addresses.

## 8. Validation when Enter is pressed

`validate_wait` sequence:

| Value | What happens |
| --- | --- |
| 1 | wait until the parser is current (`all_parsed_current`), then → 2 (existing-order operations) or 6 (adds) |
| 2..5 | count up each clock; **`ram_hold` is asserted** so the RAM ports stay on the selected order; if the readback steals the RAM (`ram_paused`), restart at 2 |
| 6 | **final checks** (this clock), then back to 0 |

**Final checks, in priority order:**

| # | Condition | Status |
| --- | --- | --- |
| 1 | `!book_valid` | 10 Book invalid |
| 2 | price needed (Add, Replace) and price field not ok | 5 Invalid price or tick |
| 3 | quantity not ok (except Delete) | 6 Invalid quantity |
| 4 | order id not ok | 7 Invalid order ID |
| 5 | Replace and (new id not ok or equal to id) | 7 Invalid order ID |
| 6 | an existing-order op and (`!current_target` or id differs from `selected_id`) | 8 **Order changed: reselect** |
| 7 | Execute/Cancel and quantity > stored shares | 11 Quantity exceeds stored order |
| 8 | price below base or tick 0 | 5 |
| else | build the event |

### `current_target`: the stale-order guard

```verilog
wire current_target = selected_valid && selected_cell[75] &&
    selected_cell[63:0] == selected_id && selected_cell[74:64] == slot_addr &&
    slot_data[46] && slot_data[31:0] == selected_qty &&
    slot_data[44:32] == selected_price_index && slot_data[45] == selected_side;
```

It re-reads the **real** hash cell and slot and compares them with the values captured when you selected the order. If a network order executed, cancelled or replaced it in the meantime, the data differ and the submission is **rejected** (status 8) rather than acting on stale information.

## 9. Building the event

`operation` maps the action: A, F → 1 (add); E, C → 2 (execute); X → 3 (cancel); D → 4 (delete); U → 5 (replace). (`F` and `C` have the same book effect as `A` and `E`: the attribution / execution-price fields are not stored.)

- **Add / Replace** need a price index: `pending_event <= {4'd1, operation, (operation==1 && side), 7'd0, id64, (operation==5 ? new64 : 64'd0), shares, 13'd0, 1'b0, 2'd0, local_sequence, 32'd0}`, then the divider supplies the index (`<< 67`).
- **Execute / Cancel / Delete** need no price: `event_data <= {4'd1, operation, 8'd0, id64, 64'd0, (operation==4 ? 32'd0 : qty), 16'd0, local_sequence, 32'd0}` and `event_valid <= 1` immediately.

`shares` is 0 for Delete. `side` is only set for adds.

## 10. Worked example: add buy 100 @ 90.5000

1. Press `8` to open the Order Entry page (page index 7). Tab to price; type `90.5000`: first character starts an edit (`editing = 1`, `saved_*` holds the old text).
2. Tab (the parser says field valid) → quantity: `100`. Tab → id: `2001`.
3. Parser: `price64 = 905000`, `qty64 = 100`, `id64 = 0x2001`, all `ok` and `current`.
4. Enter: `validate_wait = 1 → 6` (add skips the RAM wait); checks pass; `pending_event` built; divider starts (`div_start`).
5. 32 clocks later `div_finishing`: `905000 − 900000 = 5000`, `5000 / 1000 = 5`, remainder 0 → `event_data` index 5; `event_valid = 1`.
6. `order_merge` pushes it through `u_local_fifo`; the book adds it; the form shows "Sent to core", the id field becomes `2002`, `local_sequence` increments; the screen shows "Last local order accepted by book".

## 11. "What if"

- **Enter is held?** One event only (decoder `held` bitmap); also the Enter handler requires `!event_valid`.
- **A price like `90.50` (two decimals)?** `ok[0] = 0` (needs exactly four decimals) → Tab is blocked and Enter gives status 5.
- **Price off-tick, `90.5500`?** Parses, but the divider leaves a remainder of 500 → status 5.
- **Esc during an edit?** `field_text` etc. restored from `saved_*`; no event.
- **Type a 17th character?** `status <= 3` (Invalid field); the text is unchanged.
- **Unplug during an edit?** The form is untouched; `held` keys are cleared (owner 3's decoder).
- **The book is invalid?** Enter shows status 10 and sends nothing.
- **Cancel more shares than exist?** Status 11 (checked against the real slot). If the book had changed since selection: status 8.
