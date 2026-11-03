# The bus, the memories and the MMIO windows

Files: `rtl/cpu/core/sys_bus_interconnect.v`, `imem_slave.v`, `dmem_slave.v`, `memory.v`, `rtl/bus/lob_mmio_slave.v`, `rtl/bus/net_mmio_slave.v`, `rtl/cpu/cpu_system.v`.

## 1. What MMIO means

**Memory-mapped I/O**: the CPU talks to hardware by reading and writing **addresses**. `lw t0, 4(s0)` with `s0 = 0x4000_0000` does not read RAM; it reads the order book's STATUS register. Each peripheral claims a range of addresses; the interconnect routes the access to it.

*Analogy:* a building where every office has a street address. The CPU is a courier with a package; the front desk (interconnect) looks at the address and sends it to the right office.

## 2. The bus protocol (simple, one transaction at a time)

A request: `req_valid`, `req_write`, `req_addr`, `req_wdata`, `req_wstrb[3:0]` (byte strobes). A response: `rsp_valid`, `rsp_rdata` (and an error flag at the master). The CPU waits for `rsp_valid` before issuing another request (**single outstanding transaction**).

## 3. `sys_bus_interconnect`

```verilog
wire sel_imem = (cpu_req_addr[31:12] == 20'h00000);   // 0x0000_0000 .. 0x0000_0FFF
wire sel_dmem = (cpu_req_addr[31:12] == 20'h20000);   // 0x2000_0000 .. 0x2000_0FFF
wire sel_lob  = (cpu_req_addr[31:8]  == 24'h400000);  // 0x4000_0000 .. 0x4000_00FF
wire sel_net  = (cpu_req_addr[31:8]  == 24'h500000);  // 0x5000_0000 .. 0x5000_00FF
wire sel_uart = (cpu_req_addr[31:8]  == 24'h600000);  // 0x6000_0000 .. 0x6000_00FF
wire sel_sys  = (cpu_req_addr[31:8]  == 24'h700000);  // 0x7000_0000 .. 0x7000_00FF
```

Each memory is decoded to its **actual** 4 KiB range (not a whole 256 MiB region, so accesses beyond it do not silently alias); peripherals each get a 256-byte window.

### Request routing

```verilog
wire active_transaction = (slave_sel != SEL_NONE);
wire req_en = cpu_req_valid && (!active_transaction || cpu_rsp_valid);
assign lob_req_valid = req_en && sel_lob;     // ... one `*_req_valid` per slave; the address/data/strobes are broadcast
```

`slave_sel` (a register) records which slave got the request, so the **response** can be taken from the right place later. `req_en` allows a new request when nothing is in flight or the previous one is just responding.

### Response routing

`cpu_rsp_valid` / `cpu_rsp_rdata` are multiplexers on `slave_sel`. For an **unmapped address** (`SEL_ERR`), the interconnect generates its own one-cycle response `err_rsp_valid` and drives `cpu_rsp_error`, so the CPU never waits forever. (`tb_bus_error` tests this.)

## 4. Instruction and data memory

| | `imem_slave` | `dmem_slave` |
| --- | --- | --- |
| Size | 1024 × 32 bits = 4 KiB (`instr_mem`, block RAM) | 1024 × 32 bits = 4 KiB (`data_mem`, block RAM) |
| Access | read-only; synchronous, 1-cycle latency | read/write with **byte strobes** |
| Initial contents | `$readmemh("imem.hex")` | `$readmemh("dmem.hex")` |
| Response | `rsp_valid` = request delayed one clock | `rsp_valid` one clock after `fire_mem` (+ optional extra delay parameter `DELAY_CYCLES`, 0 here) |

`imem.hex` is the compiled firmware: `build_firmware.py` assembles `firmware_monitor.s` with the RISC-V toolchain, pads it to 4 KiB and writes the hex file; Vivado bakes it into the bitstream's block RAM initial values.

`data_mem` write path: `if (wstrb[k]) dmem[word][byte k] <= wdata[byte k]` for each of the four bytes, so byte and half-word stores work. Read data includes a same-cycle write-through so a read of the word just written returns the new bytes.

## 5. `lob_mmio_slave`: the order book's control panel (base `0x4000_0000`)

### Registers

| Off | Name | R/W | Contents |
| --- | --- | --- | --- |
| `00` | CTRL | R/W | bit 0 = **`accel_enable`**; writing bit 2 requests a snapshot |
| `04` | STATUS | R | bit 0 `init_done`, 1 `book_valid`, 2 `busy`, 3 error latched, 4 bid valid, 5 ask valid, 6 `event_ready`, **7 `config_ready`** |
| `08` | ERROR | R | `[7:0]` last error code, bit 16 valid |
| `0C` | ACTIVE_ORD | R | `[11:0]` live orders |
| `10` | SNAP_BID_P | R | snapshot best bid price (**reading latches the snapshot**) |
| `14` | SNAP_BID_Q | R | snapshot best bid quantity |
| `18` | SNAP_ASK_P | R | snapshot best ask price |
| `1C` | SNAP_ASK_Q | R | snapshot best ask quantity |
| `20` | SNAP_FLAGS | R | `{snap_gen[15:0], ..., ask_valid, bid_valid}` |
| `24` | PRICE_BASE | R/W | default 900000 |
| `28` | TICK | R/W | default 1000 (zero writes ignored) |
| `2C` | LOCATE | R/W | stock locate filter, default 1 |
| `30` | EVT_COUNT | R | events processed |
| `34`..`40` | LIVE_BID_P/Q, LIVE_ASK_P/Q | R | live (unfrozen) values |
| `44` | SPREAD | R | ask − bid when both valid |

### The coherent snapshot (important design point)

Reading best bid price, then bid quantity, then ask price... takes several separate bus transactions. If an event changed the book in between, the numbers would not belong together.

```verilog
assign snap_trigger = (write to CTRL with bit 2) || (read of SNAP_BID_P);
always @(posedge clk ...) if (snap_trigger) begin
    snap_bid_price_reg <= best_bid_price; snap_bid_qty_reg <= best_bid_qty;
    snap_ask_price_reg <= best_ask_price; snap_ask_qty_reg <= best_ask_qty;
    snap_gen_reg <= snap_gen_reg + 1; ...
end
```

All four values are copied **at the same instant**; the next reads return the frozen copies. `snap_gen` increments per snapshot so software can tell snapshots apart.

### Write protection

```verilog
REG_LOB_PRICE_BASE: if (!accel_enable && event_counter == 0 && active_order_count == 0) ... write
```

Price base, tick and stock locate can only be changed **before the book is enabled and before any event**, because changing them under a live book would silently re-interpret every stored price index. Writes with `wstrb` support partial updates (byte lanes).

### Other blocks inside

- `event_counter`: counts `event_done` pulses (reads at `0x30`).
- Read path: the **read address is registered** (`latched_read_addr`) and an `always @(*)` mux selects the data. Registering the address first improves timing.
- `bus_rsp_valid` is `bus_req_valid` delayed one clock (fixed 1-cycle response).

## 6. `net_mmio_slave`: the network counters (base `0x5000_0000`, read-only)

| Off | Counter | Off | Counter |
| --- | --- | --- | --- |
| `00` | received frames | `18` | RMII overflow errors |
| `04` | CRC errors | `1C` | Mold truncations |
| `08` | Mold messages | `20` | status flags (feed loss, sequence gap, decode error) |
| `0C` | sequence gaps | `24` | UDP length errors |
| `10` | length errors | `28` | UDP checksum errors |
| `14` | PHY errors | | |

**Three-stage timing design:** stage 0 copies every slice of the 352-bit `net_diag_snapshot` into registers each clock (so the wide bundle lands near its source); stage 1 registers the request address; stage 2 muxes from the `snap_*` registers into `bus_rsp_rdata`. It exists as its own module so this large multiplexer is kept away from the CPU's critical timing path. (`net_diag` already crossed clock domains in owner 1's `config_cdc`.)

## 7. `cpu_system`: putting it together

One instance (`u_cpu_system`) bundles `u_cpu`, `u_interconnect`, `u_imem`, `u_dmem`, `u_lob_mmio`, `u_net_mmio` and an inline "system" register block:

```verilog
// System window at 0x7000_0000: 0x00 = {SW15, SW14}, 0x04 = clock locked
case (sys_addr[7:0]) 8'h00: sys_rdata <= {30'd0, sw}; 8'h04: sys_rdata <= {31'd0, mmcm_locked}; default: 0; endcase
```

The UART slave lives outside (`uart_telemetry`); `cpu_system` passes the UART request/response signals through (`uart_req_*`, `uart_rsp_*`). Outputs: the configuration (`cfg_price_base`, `cfg_tick`, `cfg_stock_locate`), `accel_enable`, and the CPU program counter `pc`.

## 8. "What if"

- **The CPU reads an address nobody owns?** The interconnect makes its own error response; `cpu_rsp_error` flows to the core's `exception` logic.
- **The CPU writes to `SNAP_BID_P`?** It is read-only; the write decodes to nothing (`default: ;`).
- **The CPU changes the tick after orders exist?** The write is ignored (`event_counter != 0`), protecting stored price indexes.
- **Two reads of the best bid and ask while a trade happens?** Use the snapshot registers; the four values stay mutually consistent.
