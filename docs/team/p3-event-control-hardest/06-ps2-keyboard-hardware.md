# `ps2_receiver` and `ps2_key_decoder`

File: `rtl/ui/ps2_keyboard.v` (two modules, 159 lines). Both run in the **25 MHz UI clock** domain; instantiated in `display_system` as `u_ps2_receiver` and `u_ps2_decoder`.

## 1. How the keyboard reaches the FPGA

The Nexys A7 has a USB host connector (J5) wired to a small helper microcontroller. That chip talks USB to the keyboard and **re-presents the keys as a PS/2 keyboard** on two FPGA pins: `ps2_clk` (pin F4) and `ps2_data` (pin B2). So from the FPGA's point of view this is an old PS/2 keyboard sending **scan codes**.

Only keyboards that speak the **USB Boot HID protocol** work through that helper chip (wired keyboards and most 2.4 GHz receivers; Bluetooth dongles that need a Bluetooth stack do not).

## 2. The PS/2 bit protocol

The **keyboard** generates the clock (about 10-16 kHz). One byte is an 11-bit frame:

```
 start  d0 d1 d2 d3 d4 d5 d6 d7  parity  stop
  0     (LSB first)               odd      1
```

The data line is valid on the **falling edge** of `ps2_clk`. **Odd parity** means the nine bits `d0..d7 + parity` contain an odd number of ones.

# Part A: `ps2_receiver`: bits to bytes

## A1. Input conditioning

```verilog
(* ASYNC_REG="TRUE" *) reg [2:0] clk_sync, data_sync;     // 3-flop synchronizers for the two asynchronous pins
reg [7:0] clk_filter; reg stable_clk;                      // glitch filter
clk_filter <= {clk_filter[6:0], clk_sync[2]};
if (clk_filter == 8'hff) stable_clk <= 1; else if (clk_filter == 8'h00) stable_clk <= 0;
wire falling_edge = stable_clk && clk_filter == 8'h00;
```

The pins are asynchronous to the 25 MHz clock, so each goes through a **synchronizer** (metastability). The clock line is then **filtered**: it must read the same for 8 consecutive samples before `stable_clk` changes, which rejects short noise spikes. A real falling edge is detected when `stable_clk` was 1 and the last 8 samples are all 0.

## A2. The frame decoder

```verilog
if (falling_edge) begin
    gap <= 0;
    case (bit_index)
        0: if (!data_sync[2]) bit_index <= 1; else frame_error <= 1;      // start bit must be 0
        1..8: begin bits[bit_index-1] <= data_sync[2]; bit_index <= bit_index+1; end   // data bits, LSB first
        9:  begin parity_bit <= data_sync[2]; bit_index <= 10; end
        10: begin bit_index <= 0;
                  if (data_sync[2] && (^{bits, parity_bit})) begin byte_data <= bits; byte_valid <= 1; end   // stop = 1 and parity OK
                  else frame_error <= 1; end
    endcase
end
```

`^{bits, parity_bit}` is the XOR-reduction of all nine bits: 1 means an odd number of ones (correct odd parity).

## A3. Timeout

`gap` counts clocks since the last bit while a frame is in progress. After `GAP_LIMIT = CLK_HZ/500` (**2 ms**, much longer than any bit time) the partial frame is abandoned: `bit_index <= 0; frame_error <= 1`. This **resynchronises** after an unplug in the middle of a byte.

## A4. Outputs

| Signal | Meaning |
| --- | --- |
| `byte_valid`, `byte_data[7:0]` | one pulse per good byte |
| `frame_error` | bad start/stop/parity or timeout; **counted** by `u_frame_errors` and shown on the Status page |

# Part B: `ps2_key_decoder`: scan codes to key presses

## B1. Scan code set 2 in 60 seconds

| Event | What the keyboard sends |
| --- | --- |
| press (make) of key `A` | `0x1C` |
| release (break) of `A` | `0xF0 0x1C` |
| press of an **extended** key (arrows, Delete, PageUp/Down, keypad Enter) | `0xE0` then the code |
| release of an extended key | `0xE0 0xF0` then the code |
| keyboard powers up / self-test passed | `0xAA` |
| holding a key | the make code repeats |

## B2. Translation

`translate(ext, scan)` returns the project's own key values:

| Group | Values |
| --- | --- |
| letters / digits / `.` | ASCII (`"A"`, `"5"`, `"."`), including the numeric keypad |
| `F1`..`F8` | `0x81`..`0x88` |
| Tab, Enter, Esc, Backspace, Delete | `0x89`, `0x8A`, `0x8B`, `0x8C`, `0x8D` |
| Left, Right, Up, Down | `0x8E`, `0x8F`, `0x90`, `0x91` |
| PageUp, PageDown | `0x92`, `0x93` |

## B3. "One event per physical press": the `held` bitmap

```verilog
reg [511:0] held;                                  // one bit per (extended, scan code) = 9-bit identity
wire [8:0] identity = {extended, byte_data};
...
else begin                                         // any ordinary code
    extended <= 0; break_pending <= 0;
    if (break_pending) held[identity] <= 0;        // a release clears the bit
    else if (!held[identity]) begin                // a press that was NOT already held
        held[identity] <= 1;
        if (translate(extended, byte_data) != 0) begin key_valid <= 1; key <= translate(...); key_shift <= ...; end
    end                                            // a repeated make code of a held key: ignored
end
```

So **holding Enter produces exactly one `key_valid` pulse**: the keyboard repeats the make code, but `held[identity]` is already 1. Another Enter is only recognised after the break code clears the bit. This is how "a held Enter submits only once" is implemented.

## B4. Shift

`shift_now = held[9'h012] || held[9'h059]`: either shift key is currently held. `key_shift` also includes the key being decoded if it is itself a shift code.

## B5. Unplugging and re-plugging (hot-plug)

Two mechanisms clear "stuck" keys if a release code was lost while the keyboard was unplugged:

| Mechanism | Condition | Effect |
| --- | --- | --- |
| **BAT code** | the keyboard sends `0xAA` on reconnect | `held <= 0; extended <= 0; break_pending <= 0; reconnect <= 1` |
| **inactivity timeout** | no byte for `IDLE_LIMIT = 4 seconds` | clear the held bitmap |

**The order form itself is not reset** by either: it lives in `keyboard_controls`, which keeps its text, cursor and focus (verified by `tb_keyboard_hotplug`: "Reconnect preserves form, cursor/focus and clears held key").

## B6. Worked example

Typing `A` then releasing: bytes `1C`, `F0`, `1C`.

- `1C`: not held → `held[0x01C] <= 1`; `key_valid` pulse with key `"A"`.
- `F0`: `break_pending <= 1`.
- `1C`: `break_pending` → `held[0x01C] <= 0`. No key event.

Holding `A` produces `1C 1C 1C ...`: only the first makes a pulse.

## B7. "What if"

- **Two keys at once?** Both set their `held` bits; each produces its own pulse on its first make code. Shift + a letter works: `key_shift` carries the shift state.
- **A parity error?** `frame_error` pulses, the byte is discarded; the key press is lost (the user presses again). Counted.
- **The keyboard is unplugged mid-byte?** The 2 ms timeout abandons the partial frame (`frame_error`), so the next byte begins cleanly.
- **Why not use the PS/2 clock as a clock?** It is asynchronous and slow; using it as a clock would add another clock domain. Sampling it with the UI clock and detecting edges is simpler and safer.
