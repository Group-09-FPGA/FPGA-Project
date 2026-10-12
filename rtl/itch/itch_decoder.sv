// =============================================================================
// File: itch_decoder.sv
// Description: NASDAQ TotalView-ITCH 5.0 binary message parser
//              Stock Locate filtering, Price Normalization, and Canonical 256-bit packing
// Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T)
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module itch_decoder #(
    parameter bit [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter bit [31:0] DEFAULT_TICK       = 32'd1000,
    parameter bit [15:0] DEFAULT_LOCATE     = 16'd1
) (
    input  wire        clk,
    input  wire        rst_n,

    // Ingress interface from moldudp64_decoder
    input  wire        itch_msg_valid,
    input  wire [15:0] itch_msg_len,
    input  wire [ 7:0] itch_msg_byte,
    input  wire [63:0] itch_msg_seq,
    input  wire        itch_msg_start,
    input  wire        itch_msg_last,
    output wire        itch_msg_ready,

    // Runtime Configuration from MMIO
    input  wire [15:0] cfg_stock_locate,
    input  wire [31:0] cfg_price_base,
    input  wire [31:0] cfg_tick,

    // Canonical 256-bit Event Egress (to Async FIFO)
    output reg         canon_event_valid,
    output reg [255:0] canon_event_data,
    input  wire        canon_event_ready,

    // Telemetry & Diagnostic Counters
    output reg  [31:0] cnt_itch_total_msgs,
    output reg  [31:0] cnt_itch_order_events,
    output reg  [31:0] cnt_itch_filtered_msgs,
    output reg  [31:0] cnt_itch_admin_msgs,
    output reg  [31:0] cnt_itch_oow_events
);

    wire [15:0] active_locate     = (cfg_stock_locate != 16'd0) ? cfg_stock_locate : DEFAULT_LOCATE;
    wire [31:0] active_price_base = (cfg_price_base != 32'd0)   ? cfg_price_base   : DEFAULT_PRICE_BASE;
    wire [31:0] active_tick       = (cfg_tick != 32'd0)         ? cfg_tick         : DEFAULT_TICK;

    // Fast hardware reciprocal division by 1000 using DSP multiplier
    // (x * 274877907) >> 38 == x / 1000 for all 32-bit unsigned integers
    function automatic void div_rem_1000(
        input  logic [31:0] val,
        output logic [31:0] quot,
        output logic [31:0] rem
    );
        logic [63:0] prod;
        prod = (64'(val) * 64'd274877907);
        quot = prod[63:38];
        rem  = val - (quot * 32'd1000);
    endfunction

    typedef enum logic [1:0] {
        ST_COLLECT = 2'd0,
        ST_EMIT    = 2'd1
    } parser_state_t;

    parser_state_t state;

    assign itch_msg_ready = (state == ST_COLLECT) && canon_event_ready;

    // Buffer to hold incoming ITCH message bytes (max ITCH message is ~44 bytes)
    reg [ 7:0] msg_buffer [0:47];
    reg [ 5:0] byte_cnt;
    reg [63:0] cur_seq;

    // Diagnostic registers for debug
    reg [ 7:0] msg_type;
    reg [15:0] msg_locate;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_COLLECT;
            byte_cnt               <= 6'd0;
            cur_seq                <= 64'd0;
            msg_type               <= 8'd0;
            msg_locate             <= 16'd0;
            canon_event_valid      <= 1'b0;
            canon_event_data       <= 256'd0;
            cnt_itch_total_msgs    <= 32'd0;
            cnt_itch_order_events  <= 32'd0;
            cnt_itch_filtered_msgs <= 32'd0;
            cnt_itch_admin_msgs    <= 32'd0;
            cnt_itch_oow_events    <= 32'd0;
        end else begin
            canon_event_valid <= 1'b0;

            case (state)
                ST_COLLECT: begin
                    if (itch_msg_valid) begin
                        $display("[ITCH_COLLECT @ %0t] byte_cnt=%0d start=%0b last=%0b byte=0x%02X",
                                 $time, byte_cnt, itch_msg_start, itch_msg_last, itch_msg_byte);
                        if (itch_msg_start) begin
                            cur_seq      <= itch_msg_seq;
                            msg_buffer[0]<= itch_msg_byte;
                            byte_cnt     <= 6'd1;
                        end else begin
                            msg_buffer[byte_cnt] <= itch_msg_byte;
                            byte_cnt <= byte_cnt + 6'd1;
                        end

                        if (itch_msg_last) begin
                            cnt_itch_total_msgs <= cnt_itch_total_msgs + 32'd1;
                            state <= ST_EMIT;
                        end
                    end
                end

                ST_EMIT: begin
                    logic [ 7:0] cur_type;
                    logic [15:0] cur_loc;
                    logic [63:0] cur_oid, cur_noid;
                    logic        cur_side;
                    logic [31:0] cur_shares;
                    logic [31:0] cur_raw_p;
                    logic [31:0] p_quot, p_rem;
                    logic [12:0] final_pidx;
                    logic        is_oow;
                    canonical_event_t evt;

                    cur_type   = msg_buffer[0];
                    cur_loc    = {msg_buffer[1], msg_buffer[2]};
                    msg_type   <= cur_type;
                    msg_locate <= cur_loc;

                    cur_oid    = '0;
                    cur_noid   = '0;
                    cur_side   = 1'b0;
                    cur_shares = 32'd0;
                    cur_raw_p  = 32'd0;
                    p_quot     = 32'd0;
                    p_rem      = 32'd0;
                    final_pidx = 13'd0;
                    is_oow     = 1'b0;
                    evt        = '0;

                    if (cur_loc != active_locate) begin
                        // Filter out order not matching target stock locate
                        cnt_itch_filtered_msgs <= cnt_itch_filtered_msgs + 32'd1;
                    end else begin
                        case (cur_type)
                            "A": begin // Add Order No MPID (36 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};
                                cur_side   = (msg_buffer[19] == "S") ? SIDE_ASK : SIDE_BID;
                                cur_shares = {msg_buffer[20], msg_buffer[21], msg_buffer[22], msg_buffer[23]};
                                cur_raw_p  = {msg_buffer[32], msg_buffer[33], msg_buffer[34], msg_buffer[35]};

                                if (cur_raw_p < active_price_base) begin
                                    is_oow = 1'b1;
                                    cnt_itch_oow_events <= cnt_itch_oow_events + 32'd1;
                                end else begin
                                    div_rem_1000(cur_raw_p - active_price_base, p_quot, p_rem);
                                    if ((p_rem != 32'd0) || (p_quot >= 32'd8192)) begin
                                        is_oow = 1'b1;
                                        cnt_itch_oow_events <= cnt_itch_oow_events + 32'd1;
                                    end else begin
                                        final_pidx = p_quot[12:0];
                                    end
                                end

                                evt.ver    = 4'h1;
                                evt.op     = OP_ADD;
                                evt.side   = cur_side;
                                evt.oid    = cur_oid;
                                evt.noid   = 64'd0;
                                evt.shares = cur_shares;
                                evt.pidx   = final_pidx;
                                evt.oow    = is_oow;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            "F": begin // Add Order With MPID (40 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};
                                cur_side   = (msg_buffer[19] == "S") ? SIDE_ASK : SIDE_BID;
                                cur_shares = {msg_buffer[20], msg_buffer[21], msg_buffer[22], msg_buffer[23]};
                                cur_raw_p  = {msg_buffer[32], msg_buffer[33], msg_buffer[34], msg_buffer[35]};

                                if (cur_raw_p < active_price_base) begin
                                    is_oow = 1'b1;
                                    cnt_itch_oow_events <= cnt_itch_oow_events + 32'd1;
                                end else begin
                                    div_rem_1000(cur_raw_p - active_price_base, p_quot, p_rem);
                                    if ((p_rem != 32'd0) || (p_quot >= 32'd8192)) begin
                                        is_oow = 1'b1;
                                        cnt_itch_oow_events <= cnt_itch_oow_events + 32'd1;
                                    end else begin
                                        final_pidx = p_quot[12:0];
                                    end
                                end

                                evt.ver    = 4'h1;
                                evt.op     = OP_ADD;
                                evt.side   = cur_side;
                                evt.oid    = cur_oid;
                                evt.noid   = 64'd0;
                                evt.shares = cur_shares;
                                evt.pidx   = final_pidx;
                                evt.oow    = is_oow;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            "E": begin // Order Executed (31 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};
                                cur_shares = {msg_buffer[19], msg_buffer[20], msg_buffer[21], msg_buffer[22]};

                                evt.ver    = 4'h1;
                                evt.op     = OP_EXECUTE;
                                evt.oid    = cur_oid;
                                evt.shares = cur_shares;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            "C": begin // Order Executed with Price (36 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};
                                cur_shares = {msg_buffer[19], msg_buffer[20], msg_buffer[21], msg_buffer[22]};

                                evt.ver    = 4'h1;
                                evt.op     = OP_EXECUTE;
                                evt.oid    = cur_oid;
                                evt.shares = cur_shares;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            "X": begin // Order Cancel (23 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};
                                cur_shares = {msg_buffer[19], msg_buffer[20], msg_buffer[21], msg_buffer[22]};

                                evt.ver    = 4'h1;
                                evt.op     = OP_CANCEL;
                                evt.oid    = cur_oid;
                                evt.shares = cur_shares;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            "D": begin // Order Delete (19 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};

                                evt.ver    = 4'h1;
                                evt.op     = OP_DELETE;
                                evt.oid    = cur_oid;
                                evt.shares = 32'd0;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            "U": begin // Order Replace (35 bytes)
                                cur_oid    = {msg_buffer[11], msg_buffer[12], msg_buffer[13], msg_buffer[14],
                                              msg_buffer[15], msg_buffer[16], msg_buffer[17], msg_buffer[18]};
                                cur_noid   = {msg_buffer[19], msg_buffer[20], msg_buffer[21], msg_buffer[22],
                                              msg_buffer[23], msg_buffer[24], msg_buffer[25], msg_buffer[26]};
                                cur_shares = {msg_buffer[27], msg_buffer[28], msg_buffer[29], msg_buffer[30]};
                                cur_raw_p  = {msg_buffer[31], msg_buffer[32], msg_buffer[33], msg_buffer[34]};

                                if (cur_raw_p < active_price_base) begin
                                    is_oow = 1'b1;
                                    cnt_itch_oow_events <= cnt_itch_oow_events + 32'd1;
                                end else begin
                                    div_rem_1000(cur_raw_p - active_price_base, p_quot, p_rem);
                                    if ((p_rem != 32'd0) || (p_quot >= 32'd8192)) begin
                                        is_oow = 1'b1;
                                        cnt_itch_oow_events <= cnt_itch_oow_events + 32'd1;
                                    end else begin
                                        final_pidx = p_quot[12:0];
                                    end
                                end

                                evt.ver    = 4'h1;
                                evt.op     = OP_REPLACE;
                                evt.oid    = cur_oid;
                                evt.noid   = cur_noid;
                                evt.shares = cur_shares;
                                evt.pidx   = final_pidx;
                                evt.oow    = is_oow;
                                evt.seq    = cur_seq[31:0];

                                canon_event_valid     <= 1'b1;
                                canon_event_data      <= evt;
                                cnt_itch_order_events <= cnt_itch_order_events + 32'd1;
                            end

                            default: begin
                                cnt_itch_admin_msgs <= cnt_itch_admin_msgs + 32'd1;
                            end
                        endcase
                    end

                    byte_cnt <= 6'd0;
                    state    <= ST_COLLECT;
                end

                default: state <= ST_COLLECT;
            endcase
        end
    end

endmodule
