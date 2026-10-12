// =============================================================================
// File: lob_mmio_slave.sv
// Description: MMIO slave peripheral for LOB accelerator on CPU system bus
// Base Address: 0x4000_0000
// =============================================================================

`timescale 1ns / 1ps

module lob_mmio_slave #(
    parameter bit [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter bit [31:0] DEFAULT_TICK       = 32'd1000,
    parameter bit [15:0] DEFAULT_LOCATE     = 16'd1
) (
    input  wire        clk,
    input  wire        reset, // active-low

    // System Bus Slave Interface
    input  wire        bus_req_valid,
    input  wire        bus_req_write,
    input  wire [31:0] bus_req_addr,
    input  wire [31:0] bus_req_wdata,
    input  wire [ 3:0] bus_req_wstrb,

    output reg         bus_rsp_valid,
    output wire [31:0] bus_rsp_rdata,

    // LOB Core Control Outputs
    output reg         cfg_clear_strobe,
    output reg         cfg_fail_stop_en,
    output reg  [31:0] cfg_price_base,
    output reg  [31:0] cfg_tick,
    output reg  [15:0] cfg_stock_locate,
    output reg         accel_enable,

    // LOB Core State Inputs
    input  wire        book_valid,
    input  wire        init_done,
    input  wire        busy,
    input  wire        error_valid,
    input  wire [ 7:0] error_code,
    input  wire [11:0] active_order_count,
    input  wire        event_done,
    input  wire        event_ready,

    // Live BBO Inputs
    input  wire        best_bid_valid,
    input  wire [31:0] best_bid_price,
    input  wire [31:0] best_bid_qty,
    input  wire        best_ask_valid,
    input  wire [31:0] best_ask_price,
    input  wire [31:0] best_ask_qty,

    // CPU Event Injection Interface (optional debug)
    output reg         inject_valid,
    output reg  [255:0] inject_event_data,
    input  wire        inject_ready
);

    // Register Offsets
    localparam [7:0] REG_LOB_CTRL        = 8'h00; // R/W: [0]=enable, [1]=clear(W1P), [2]=snap_req(W1P), [3]=fail_stop_en
    localparam [7:0] REG_LOB_STATUS      = 8'h04; // RO:  [0]=init_done, [1]=book_valid, [2]=busy, [3]=fail_stop, [4]=bid_valid, [5]=ask_valid, [6]=event_ready
    localparam [7:0] REG_LOB_ERROR_CODE  = 8'h08; // RO/W1C: [7:0]=error_code, [16]=error_valid
    localparam [7:0] REG_LOB_ACTIVE_ORD  = 8'h0C; // RO:  [11:0]=active_order_count
    localparam [7:0] REG_LOB_SNAP_BID_P  = 8'h10; // RO:  Atomic snapshot Best Bid Price (auto-latches snapshot)
    localparam [7:0] REG_LOB_SNAP_BID_Q  = 8'h14; // RO:  Atomic snapshot Best Bid Qty
    localparam [7:0] REG_LOB_SNAP_ASK_P  = 8'h18; // RO:  Atomic snapshot Best Ask Price
    localparam [7:0] REG_LOB_SNAP_ASK_Q  = 8'h1C; // RO:  Atomic snapshot Best Ask Qty
    localparam [7:0] REG_LOB_SNAP_FLAGS  = 8'h20; // RO:  [0]=bid_v, [1]=ask_v, [31:16]=snap_gen
    localparam [7:0] REG_LOB_PRICE_BASE  = 8'h24; // R/W: Price Base
    localparam [7:0] REG_LOB_TICK        = 8'h28; // R/W: Tick Size
    localparam [7:0] REG_LOB_LOCATE      = 8'h2C; // R/W: Stock Locate ID
    localparam [7:0] REG_LOB_EVT_COUNT   = 8'h30; // RO:  Total events processed counter
    localparam [7:0] REG_LOB_LIVE_BID_P  = 8'h34; // RO:  Live Best Bid Price
    localparam [7:0] REG_LOB_LIVE_BID_Q  = 8'h38; // RO:  Live Best Bid Qty
    localparam [7:0] REG_LOB_LIVE_ASK_P  = 8'h3C; // RO:  Live Best Ask Price
    localparam [7:0] REG_LOB_LIVE_ASK_Q  = 8'h40; // RO:  Live Best Ask Qty
    localparam [7:0] REG_LOB_SPREAD      = 8'h44; // RO:  Spread = Ask - Bid (if both valid)

    // Event counter
    reg [31:0] event_counter;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            event_counter <= 32'd0;
        end else begin
            if (cfg_clear_strobe) begin
                event_counter <= 32'd0;
            end else if (event_done) begin
                event_counter <= event_counter + 32'd1;
            end
        end
    end

    // Coherent Atomic Snapshot Registers
    reg [31:0] snap_bid_price_reg;
    reg [31:0] snap_bid_qty_reg;
    reg [31:0] snap_ask_price_reg;
    reg [31:0] snap_ask_qty_reg;
    reg        snap_bid_valid_reg;
    reg        snap_ask_valid_reg;
    reg [15:0] snap_gen_reg;

    wire snap_trigger;
    wire reg_read_snap_bid = bus_req_valid && !bus_req_write && (bus_req_addr[7:0] == REG_LOB_SNAP_BID_P);

    // Latch snapshot either on explicit CPU snap_req write OR on read of REG_LOB_SNAP_BID_P
    assign snap_trigger = (bus_req_valid && bus_req_write && (bus_req_addr[7:0] == REG_LOB_CTRL) && bus_req_wdata[2]) ||
                          reg_read_snap_bid;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            snap_bid_price_reg <= 32'd0;
            snap_bid_qty_reg   <= 32'd0;
            snap_ask_price_reg <= 32'd0;
            snap_ask_qty_reg   <= 32'd0;
            snap_bid_valid_reg <= 1'b0;
            snap_ask_valid_reg <= 1'b0;
            snap_gen_reg       <= 16'd0;
        end else if (snap_trigger) begin
            snap_bid_price_reg <= best_bid_price;
            snap_bid_qty_reg   <= best_bid_qty;
            snap_ask_price_reg <= best_ask_price;
            snap_ask_qty_reg   <= best_ask_qty;
            snap_bid_valid_reg <= best_bid_valid;
            snap_ask_valid_reg <= best_ask_valid;
            snap_gen_reg       <= snap_gen_reg + 16'd1;
        end
    end

    // Error latching / clear
    reg [7:0] latched_error_code;
    reg       latched_error_valid;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            latched_error_code  <= 8'd0;
            latched_error_valid <= 1'b0;
        end else begin
            if (cfg_clear_strobe) begin
                latched_error_code  <= 8'd0;
                latched_error_valid <= 1'b0;
            end else if (error_valid) begin
                latched_error_code  <= error_code;
                latched_error_valid <= 1'b1;
            end else if (bus_req_valid && bus_req_write && (bus_req_addr[7:0] == REG_LOB_ERROR_CODE)) begin
                // W1C: writing 1 to bit 16 clears error
                if (bus_req_wdata[16]) latched_error_valid <= 1'b0;
            end
        end
    end

    // Live Spread Calculation (Registered for timing closure)
    reg [31:0] live_spread;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            live_spread <= 32'd0;
        end else begin
            live_spread <= (best_bid_valid && best_ask_valid && (best_ask_price >= best_bid_price)) ?
                           (best_ask_price - best_bid_price) : 32'd0;
        end
    end

    // Bus Write and Control Logic
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            cfg_clear_strobe <= 1'b0;
            cfg_fail_stop_en <= 1'b1;
            cfg_price_base   <= DEFAULT_PRICE_BASE;
            cfg_tick         <= DEFAULT_TICK;
            cfg_stock_locate <= DEFAULT_LOCATE;
            accel_enable     <= 1'b1;
            inject_valid     <= 1'b0;
            inject_event_data<= 256'd0;
        end else begin
            cfg_clear_strobe <= 1'b0; // default 1-cycle pulse
            inject_valid     <= 1'b0;

            if (bus_req_valid && bus_req_write) begin
                case (bus_req_addr[7:0])
                    REG_LOB_CTRL: begin
                        if (bus_req_wstrb[0]) begin
                            accel_enable     <= bus_req_wdata[0];
                            cfg_clear_strobe <= bus_req_wdata[1];
                            cfg_fail_stop_en <= bus_req_wdata[3];
                        end
                    end

                    REG_LOB_PRICE_BASE: begin
                        if (bus_req_wstrb[0]) cfg_price_base[ 7: 0] <= bus_req_wdata[ 7: 0];
                        if (bus_req_wstrb[1]) cfg_price_base[15: 8] <= bus_req_wdata[15: 8];
                        if (bus_req_wstrb[2]) cfg_price_base[23:16] <= bus_req_wdata[23:16];
                        if (bus_req_wstrb[3]) cfg_price_base[31:24] <= bus_req_wdata[31:24];
                    end

                    REG_LOB_TICK: begin
                        if (bus_req_wstrb[0]) cfg_tick[ 7: 0] <= bus_req_wdata[ 7: 0];
                        if (bus_req_wstrb[1]) cfg_tick[15: 8] <= bus_req_wdata[15: 8];
                        if (bus_req_wstrb[2]) cfg_tick[23:16] <= bus_req_wdata[23:16];
                        if (bus_req_wstrb[3]) cfg_tick[31:24] <= bus_req_wdata[31:24];
                    end

                    REG_LOB_LOCATE: begin
                        if (bus_req_wstrb[0]) cfg_stock_locate[ 7:0] <= bus_req_wdata[ 7:0];
                        if (bus_req_wstrb[1]) cfg_stock_locate[15:8] <= bus_req_wdata[15:8];
                    end

                    default: ;
                endcase
            end
        end
    end

    // Bus Read Multiplexer with Latched Address for Timing Closure
    reg [5:0] latched_read_addr;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            bus_rsp_valid     <= 1'b0;
            latched_read_addr <= 6'd0;
        end else begin
            bus_rsp_valid <= bus_req_valid;
            if (bus_req_valid && !bus_req_write) begin
                latched_read_addr <= bus_req_addr[7:2];
            end
        end
    end

    reg [31:0] rdata_comb;
    always @(*) begin
        case (latched_read_addr)
            6'h00: rdata_comb = {28'd0, cfg_fail_stop_en, 1'b0, 1'b0, accel_enable}; // 0x00 CTRL
            6'h01: rdata_comb = {25'd0, event_ready, best_ask_valid, best_bid_valid, latched_error_valid, busy, book_valid, init_done}; // 0x04 STATUS
            6'h02: rdata_comb = {15'd0, latched_error_valid, 8'd0, latched_error_code}; // 0x08 ERR
            6'h03: rdata_comb = {20'd0, active_order_count}; // 0x0C ACTIVE_ORD
            6'h04: rdata_comb = snap_bid_price_reg; // 0x10 SNAP_BID_P
            6'h05: rdata_comb = snap_bid_qty_reg;   // 0x14 SNAP_BID_Q
            6'h06: rdata_comb = snap_ask_price_reg; // 0x18 SNAP_ASK_P
            6'h07: rdata_comb = snap_ask_qty_reg;   // 0x1C SNAP_ASK_Q
            6'h08: rdata_comb = {snap_gen_reg, 14'd0, snap_ask_valid_reg, snap_bid_valid_reg}; // 0x20 FLAGS
            6'h09: rdata_comb = cfg_price_base;     // 0x24 PRICE_BASE
            6'h0A: rdata_comb = cfg_tick;           // 0x28 TICK
            6'h0B: rdata_comb = {16'd0, cfg_stock_locate}; // 0x2C LOCATE
            6'h0C: rdata_comb = event_counter;      // 0x30 EVT_COUNT
            6'h0D: rdata_comb = best_bid_price;     // 0x34 LIVE_BID_P
            6'h0E: rdata_comb = best_bid_qty;       // 0x38 LIVE_BID_Q
            6'h0F: rdata_comb = best_ask_price;     // 0x3C LIVE_ASK_P
            6'h10: rdata_comb = best_ask_qty;       // 0x40 LIVE_ASK_Q
            6'h11: rdata_comb = live_spread;        // 0x44 SPREAD
            default: rdata_comb = 32'h0000_0000;
        endcase
    end

    assign bus_rsp_rdata = rdata_comb;

endmodule
