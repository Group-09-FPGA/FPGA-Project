# Order sources: `order_source_arbiter` and `order_merge`

Files: `rtl/ui/order_source_arbiter.v` (26 lines), `rtl/ui/order_merge.v` (~60 lines).

## 1. The problem

The book has **one input**. There are **two producers**: the network (through owner 1's FIFO) and the keyboard (through its own FIFO). Someone must choose, and the choice must be:

- **fair**: neither source can starve the other;
- **stable**: once a source's event is on offer, it must not change before the book accepts it;
- **traceable**: afterwards we must know **which** source's event just completed, so a keyboard order's result can be shown on the screen.

*Analogy:* a single-lane bridge with a traffic warden. He waves cars from the two sides alternately; once he has waved a car forward he does not change his mind until it has crossed.

## 2. `order_source_arbiter`

```verilog
module order_source_arbiter (
    input clk, rst_n,
    input net_valid,   input [255:0] net_data,   output net_ready,
    input local_valid, input [255:0] local_data, output local_ready,
    output valid,      output [255:0] data,      output chosen_local,
    input ready );

    reg prefer_local, locked, locked_local;
    wire choose_local = locked ? locked_local : local_valid && (!net_valid || prefer_local);
    assign valid        = choose_local ? local_valid : net_valid;
    assign data         = choose_local ? local_data  : net_data;
    assign chosen_local = choose_local;
    assign local_ready  = ready &&  choose_local;
    assign net_ready    = ready && !choose_local;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin prefer_local <= 0; locked <= 0; locked_local <= 0; end
        else if (valid && ready)               begin prefer_local <= !choose_local; locked <= 0; end
        else if (valid && !ready && !locked)   begin locked <= 1; locked_local <= choose_local; end
endmodule
```

### The three state bits

| Bit | Meaning |
| --- | --- |
| `prefer_local` | whose turn it is *when both have an event*; flips after every accepted event |
| `locked` | an event is being **offered but not yet accepted**: freeze the choice |
| `locked_local` | which source the frozen choice was |

### The decision rule

`choose_local = locked ? locked_local : local_valid && (!net_valid || prefer_local)`

- If **locked**: keep the previous choice.
- Otherwise choose **local** when the keyboard has an event **and** (the network has none, **or** it is the keyboard's turn).
- Otherwise choose **network**.

The outputs `valid`/`data` are simply a mux on `choose_local`; `local_ready` / `net_ready` are `ready` gated by the choice, so **only the chosen producer's handshake completes**.

### The sequence

| Situation | What happens |
| --- | --- |
| only the network has events | `choose_local = 0`; events flow |
| both valid, `prefer_local = 0` | network first; when accepted, `prefer_local <= !0 = 1`; next event goes to the keyboard |
| the chosen event is not accepted (`ready = 0`) | `locked <= 1`, remembering the choice, so a newly arrived event from the other source cannot make `data` change under the book's feet |
| accepted (`valid && ready`) | `locked <= 0`; `prefer_local` flips |

## 3. `order_merge`

It wraps the arbiter with the **local FIFO** and the bookkeeping.

```
 keyboard (ui clock) ─► u_local_fifo (4 entries, ui → core) ─┐
                                                              ├─► u_arbiter ─► evt_valid/data ─► lob_core
 net_ingest (core clock) ─────────────────────────────────────┘                    ▲ evt_ready
```

### The local FIFO

An `async_event_fifo` with `ADDR_WIDTH = 2` (4 entries). Write side: the UI clock (`clk_ui`, `rst_ui_n`); read side: the core clock. The keyboard's `event_valid/event_ready` are the write handshake, so the form ignores a second Enter while its previous event is still waiting.

### The bookkeeping `always` block

```verilog
if (evt_valid && evt_ready) begin
    active_local <= chosen_local;                                           // who owns the event now in flight
    event_meta   <= {evt_data[`EVT_SIDE_BIT], evt_data[`EVT_SHARES_SLICE], evt_data[`EVT_PIDX_SLICE]};
end
done_delay <= lob_event_done && active_local;                               // a KEYBOARD event completed (one clock later)
if (done_delay) begin
    local_done_count <= local_done_count + 1;                               // count it
    local_done_valid <= lob_book_valid;                                     // was the book still valid? (accepted vs rejected)
    local_done_error <= lob_error_code;                                     // and the error code
end
```

| Register | Why it exists |
| --- | --- |
| `active_local` | the event in flight came from the keyboard |
| `event_meta` (46 bits) | `{side, shares, price index}` of the last accepted event; the history journal stores it with the storage trace |
| `done_delay` | delays the "keyboard event completed" flag by **one clock** so `lob_book_valid` and `lob_error_code` have settled |
| `local_done_count` | how many keyboard orders have completed |
| `local_done_valid`, `local_done_error` | the outcome of the **last** keyboard order |

**Network events never touch `local_done_*`.** That is why the **network counters remain exact**: they come from `net_ingest`, not from here.

### Where the results go

`local_done_*` crosses to the UI clock (`u_local_done_cdc` in `status_to_ui`), becomes word 50-51 of the display registers, and the display shows **"Last local order accepted by book"** or **"Last local order rejected by book"** (from the valid bit), with the count.

## 4. Worked example

Network event N1 and keyboard event K1 both waiting; the book is idle.

1. `prefer_local = 0` → choose the **network**: `valid = 1`, `net_ready = ready`.
2. Book accepts N1 (`ready = 1`): `prefer_local <= 1`, `active_local <= 0`.
3. N1 executes (ADD takes ~8 clocks). Meanwhile another network event N2 arrives and K1 is still waiting.
4. Book idle again: both valid, `prefer_local = 1` → choose **local** → K1 goes next.
5. K1 completes: `done_delay` → `local_done_count = 1`; `local_done_valid = lob_book_valid`.
6. Next, N2.

## 5. "What if"

- **The book is busy (`ready = 0`) when the arbiter first offers an event?** `locked` is set; the same event stays on `data` until accepted, even if the other source becomes valid.
- **Both sources valid at reset?** `prefer_local = 0` → network first.
- **Could the keyboard starve the network?** No: `prefer_local` flips after each accepted event, so they alternate.
- **Could a keyboard order be lost?** Not once it is in the FIFO: it stays until read. If the FIFO is full, `ui_ready` is low, so the form keeps `event_valid` high and **ignores further Enter presses** until the event is accepted (the Enter handler requires `!event_valid`).
- **How is it tested?** `tb_order_source_arbiter` pushes mixed sources under backpressure and checks that every accepted event appears exactly once with stable data and no source is lost; `tb_system_top` sends a keyboard order between network orders and checks they share one book without changing network sequencing.
