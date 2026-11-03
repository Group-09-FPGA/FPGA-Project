# Chapter 5: Order sources and the keyboard

Files: `rtl/ui/ps2_keyboard.v`, `rtl/ui/keyboard_controls.v`, `rtl/ui/form_parser.v`,
`rtl/ui/price_divider.v`, `rtl/ui/bin_to_decimal.v`, `rtl/ui/order_source_arbiter.v`,
`rtl/ui/order_merge.v`.

The book can be fed from two places: the network (chapters 2-3) and the keyboard.
This chapter covers the keyboard side and how the two sources are merged. All
keyboard logic runs in the 25 MHz `ui` clock domain.

## The path of a keystroke

```
USB keyboard ─► board's USB-HID chip ─► PS/2 clock+data pins
   ─► ps2_receiver (bits → bytes) ─► ps2_key_decoder (scan codes → keys)
   ─► keyboard_controls (order form, pages, validation) ─► 256-bit event
   ─► local FIFO (order_merge) ─► order_source_arbiter ─► lob_core
```

## `ps2_receiver`: bits to bytes

**Job:** decode PS/2's 11-bit frames: 1 start bit (0), 8 data bits (LSB first), 1 odd-parity bit, 1 stop bit (1).

**Why:** the Nexys A7's USB host chip pretends to be an old PS/2 keyboard. The keyboard supplies the PS/2 clock.

**Analogy:** reading Morse code: every time the clock line drops, read the data line, count the bits.

**Key signals**

| Signal | Meaning |
| --- | --- |
| `clk_sync`, `data_sync` | 3-flop synchronizers for the asynchronous pins (`ASYNC_REG`) |
| `clk_filter` | 8-sample filter; `stable_clk` flips only when 8 samples agree (rejects glitches) |
| `falling_edge` | `stable_clk` was 1 and the filter just reached all-zero |
| `bit_index` | 0 = waiting for start, 1-8 data, 9 parity, 10 stop |
| `gap` | counts cycles since the last bit; at `GAP_LIMIT` (2 ms) a half-received frame is abandoned |
| `byte_valid`, `byte_data`, `frame_error` | outputs |

**The always block:** every cycle, sample inputs; on a falling PS/2 clock edge, a `case (bit_index)` shifts in
the right bit. At bit 10 it checks stop = 1 and parity (`^{bits,parity_bit}` must be 1, i.e. odd parity);
good frame: `byte_valid` pulses; bad frame: `frame_error` pulses (counted for the display).

## `ps2_key_decoder`: scan codes to keys

**Job:** turn the PS/2 "scan code set 2" byte stream into one `key_valid` pulse per physical key press.

**Scan code rules**

- Press sends the key's code. Release sends `F0` then the code (**break**). Extended keys (arrows, Delete, Page Up/Down,
  keypad Enter) send `E0` first.
- `translate(ext, scan)` maps codes to the project's own key values: letters/digits as ASCII (`"A"`, `"5"`...),
  special keys as `K_F1` (0x81) .. `K_PGDN` (0x93).

**Why a `held` bitmap (512 bits)?** Keyboards **repeat** a held key by resending its make code. The decoder only
fires when the key was *not* already held, so holding Enter submits **once**. A break code clears the bit.

**Hot-plug protection**

- `AA` (the keyboard's self-test pass) clears everything and pulses `reconnect`.
- If no byte arrives for 4 seconds (`IDLE_LIMIT`) the held-key map is cleared, so a key released while unplugged
  cannot stay "stuck".

**Shift:** `shift_now` looks at the held bits of the two shift scan codes (`0x12`, `0x59`).

## `keyboard_controls`: the order form and the pages

**Job:** the front panel. It tracks which **page** is showing (0-7, 8 = quote history), which **field** has
focus, edits text in the form, validates it, and builds an order event when Enter is pressed.

**Keys** (also see `docs/keyboard_vga_controls.md`): F1-F8 or 1-8 pick pages; `H` history; `Tab`/`Shift+Tab` move
focus; arrows and PageUp/Down navigate lists; digits, `.`, A-F edit numeric fields; `Esc` cancels an edit;
`Enter` submits on the Order Entry page.

**Why text-backed fields?** The form stores *characters* (`field_text[0..3]`, each 16 chars with a length and a
cursor). Invalid input stays visible so the user can fix it with Backspace.

### Key registers

| Register | Meaning |
| --- | --- |
| `page`, `focus` | current page; focused control (0 action, 1 side, 2 price, 3 qty, 4 id, 5 new id, 6 list) |
| `action` | 0..6 = `A F E C X D U` |
| `field_text/len/cursor[0..3]` | the four text fields: price, quantity, order id, new id |
| `editing`, `saved_*` | whether a field is mid-edit, and the pre-edit copy that **Esc** restores |
| `selected_valid`, `selected_id`, `selected_qty`, ... | the order highlighted from the book (browsing) |
| `scan_state`, `scanned`, `hash_set`, `hash_way`, `stash_selected` | the **order browser**: walks the real hash table to find the next live order |
| `validate_wait` | the 6-step check sequence that runs when Enter is pressed |
| `event_valid`, `event_data`, `event_ready` | the outgoing event |
| `status` | result code shown on the screen (OK, bad price, bad id, stale order, ...) |
| `ram_hold` | tells `ram_ports` that the keyboard is using the slot/hash read ports |

### What the big always block does

It is one clocked block that does several jobs each cycle, in this order:

1. **Event handshake:** when the event is accepted (`event_valid && event_ready`), set status "sent" and auto-increment
   the order id field (so repeated Adds get new ids).
2. **Divider result:** when `div_finishing`, check the price index is a clean tick in range; if so, finish the event
   (`event_data <= pending_event | index << 67`) and raise `event_valid`.
3. **Order browser (`scan_state`):** step 1 reads a hash cell, 2 reads the slot, 3 converts price/qty to decimal
   digits (`bin_to_decimal`), then fills the form with the real stored values.
4. **Validation sequencer (`validate_wait`):** after Enter, waits for the parser to be current, waits for RAM to be stable, then runs the checks.
5. **Key handling:** a long `if / else if` chain on `key`: page keys, Tab, Esc, action/side fields, text editing,
   list browsing, PageUp/Down.
6. **Enter:** on page 7, starts validation (`validate_wait <= 1`).
7. **Final checks (`validate_wait == 6`):** book valid? price/qty/ids parsed OK? for execute/cancel/delete/replace: is the
   selected order **still the same** live order (`current_target`)? quantity not larger than the stored shares?
   If all pass, build `pending_event`; if a price is needed, start the divider.

### Helper modules (split out for clarity)

**`form_parser`**: continuously converts the four text fields to numbers. Every 17 cycles it parses one field
(`field` cycles 0..3), accumulating `acc = acc*10 + digit` (decimal) or `acc = acc*16 + hex` (ids). It also checks
syntax: price must be `digits.dddd` (exactly four decimals, at most 11 chars), quantity at most 10 digits, ids
non-zero. `ok[i]` says the field is valid; `current[i]` says the parsed value still matches the text now on screen.
So Enter cannot send a number that is older than the text.

**`price_divider`**: price index = `(price − base) / tick`. A 32-cycle restoring divider: each cycle shifts one bit of
the numerator into `rem`; if `rem >= divisor`, subtract and output a 1. `finishing` is high on the last cycle with
`quotient`/`remainder` ready. A non-zero remainder means the price is not on a tick, and the order is rejected.

**`bin_to_decimal`**: the "double-dabble" algorithm: shift a binary number into a BCD register one bit at a time,
adding 3 to any digit ≥ 5 first. After 32 steps `digits` holds 10 decimal digits. Used to show a browsed order's price
and quantity.

### Example: typing "Add buy 100 @ 90.5000"

Type `8` (page 7), Tab to price, type `90.5000` (field text becomes `"90.5000"`, `editing`=1), Tab, type `100`, Tab, type id
`2001`. The parser makes `price = 905000`, `qty = 100`, `id = 0x2001`, all `ok`. Press Enter: validation passes;
divider computes `(905000 − 900000)/1000 = 5` remainder 0; event built: opcode 1, side buy, id 0x2001, shares 100,
index 5, sequence from `local_sequence`. `event_valid` rises; `order_merge` takes it; `lob_core` adds it. Status "sent";
the id field becomes `2002`.

## `order_source_arbiter`: one at a time, fairly

**Job:** choose between the network event and the local (keyboard) event and present exactly one to `lob_core`.

**Rules** (all combinational, plus three state bits)

- `choose_local` = local has one AND (network has none OR it is local's turn).
- `prefer_local` flips after each accepted event so the sources **alternate** when both are waiting.
- `locked`/`locked_local`: if the chosen event is not accepted yet, remember the choice and **do not change it**
  (the data must stay stable under backpressure).
- `net_ready`/`local_ready` are `ready && choose...` so only the chosen source sees its handshake complete.

## `order_merge`: the glue

Combines: the local FIFO (`u_local_fifo`, `ui` → `core` crossing), the arbiter, and bookkeeping for
keyboard results.

- `active_local`: remembers whether the event in flight came from the keyboard.
- `event_meta`: remembers `{side, shares, price index}` of the last accepted event; the history journal stores it.
- `local_done_count/valid/error`: after a *keyboard* event completes (`done_delay`, one cycle after `event_done`),
  count it and record whether the book was still valid and the error code. The display shows this as "last submission result".

Network events do not touch these registers, so the network counters stay accurate.
