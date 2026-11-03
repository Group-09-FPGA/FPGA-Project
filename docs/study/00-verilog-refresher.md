# Chapter 0: Verilog refresher

You do not need to be a Verilog expert, but ten ideas explain nearly every
line in this project.

## 1. A module is a chip you can place

```verilog
module event_counter (input clk, input rst_n, input inc, output reg [31:0] count);
```

A **module** has input and output ports. You **instantiate** it (place a copy)
inside another module and wire its ports. The hierarchy is a tree: `top_system`
contains `net_ingest`, which contains `rmii_rx`, and so on.

*Analogy:* a module is a LEGO brick. `top_system` is the finished model; it
only snaps bricks together.

## 2. `wire` vs `reg`

- `wire`: just a metal wire. Its value is always whatever drives it
  (`assign x = a & b;`).
- `reg`: a value that is **assigned inside an `always` block**. It is *not*
  always a flip-flop; it becomes a flip-flop only if the block is clocked.

## 3. Two kinds of `always` block

**Clocked (sequential)**: runs on a clock edge; creates flip-flops (memory).

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) count <= 0;          // reset branch
    else if (inc) count <= count + 1; // normal behaviour
end
```

**Combinational**: `always @(*)` (or `always @*`); creates pure logic with no
memory. Every output must be assigned on every path, or you accidentally build
a latch.

*Analogy:* a clocked block is a camera taking a photo on every clock tick;
a combinational block is a pocket calculator that always shows the current answer.

## 4. `<=` vs `=`

- `<=` (non-blocking): used in clocked blocks. All right-hand sides are read
  first, then all registers update together, exactly like real flip-flops.
- `=` (blocking): used in combinational blocks and functions; executes in order.

If you see `x <= y; y <= x;` in a clocked block, the two *swap*. That is the
point of non-blocking assignment.

## 5. Asynchronous reset

`always @(posedge clk or negedge rst_n)` means "do the clocked thing on each
rising clock edge, **or** immediately if `rst_n` falls". Almost every module
here uses an active-low asynchronous reset: when `rst_n` is 0, registers go to
their starting values.

## 6. Parameters

`parameter WIDTH = 80` is a build-time constant. `config_cdc #(.WIDTH(175))`
makes a 175-bit-wide copy of the same module. Think of it as a template.

## 7. `generate` and `genvar`

A loop that **creates hardware copies** at build time, not at run time.
`lob_hash_table` uses one to make 8 RAM instances (one per hash "way").

## 8. Functions and tasks

- `function`: returns one value, no timing; used for helpers such as `hash_oid`.
- `task`: can drive several registers. In `lob_core` the tasks (`fail`,
  `price_write`, ...) each set a handful of control registers in one clock cycle.
  A task call is *not* a software call; the compiler pastes its assignments in place.

## 9. Valid/ready handshake

Used wherever one block hands data to another:

- sender raises `valid` when `data` is meaningful,
- receiver raises `ready` when it can accept,
- a transfer happens on a clock edge where **both are 1**.

*Analogy:* handing a parcel over a counter. You hold it out (valid); the clerk
reaches (ready); the parcel changes hands only when both are true. If the clerk
is busy, you keep holding it out unchanged: that is **backpressure**.

## 10. Clock-domain crossing (CDC)

When a signal changes in one clock domain and is read in another, the reader
can catch it mid-change and get garbage (metastability). Rules this project
follows:

- a **single bit** crosses through two flip-flops in a row (a 2-flop synchronizer);
- a **multi-bit value** crosses either through `config_cdc` (hold + handshake)
  or through an asynchronous FIFO with Gray-coded pointers.

You will see `(* ASYNC_REG = "TRUE" *)` on the synchronizer flops; it tells
Vivado to keep them next to each other.

## Small glossary

| Term | Meaning |
| --- | --- |
| BRAM | Block RAM: the FPGA's built-in memory blocks (this chip has 135 tiles) |
| LUT | Lookup table: the FPGA's basic logic cell (this chip has 63,400) |
| FSM | Finite state machine: a `state` register plus a `case(state)` |
| MMIO | Memory-mapped I/O: the CPU reads/writes registers as if they were memory addresses |
| ITCH / MoldUDP64 | The stock-exchange message formats the network input uses |
| Slot | One storage cell for one live order |
| BBO | Best Bid and Offer: the highest buy price and the lowest sell price |
