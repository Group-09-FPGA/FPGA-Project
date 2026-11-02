// =============================================================================
// File: vga_top.v
// Description: Real-time 640x480 @ 60Hz VGA Market Data & Order Book Visualizer
//              Renders Book Status, BBO (Bid in Green, Ask in Red), Spread,
//              Active Orders, Total Events, and Network Frame Counters.
// Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T)
// =============================================================================

`timescale 1ns / 1ps

module vga_top (
    input  wire        clk_vga,          // 25.0 MHz pixel clock
    input  wire        rst_n,            // Active-low synchronous reset

    // Market Data & LOB Status Inputs (from Core Domain)
    input  wire        book_valid,
    input  wire        best_bid_valid,
    input  wire [31:0] best_bid_price,
    input  wire [31:0] best_bid_qty,
    input  wire        best_ask_valid,
    input  wire [31:0] best_ask_price,
    input  wire [31:0] best_ask_qty,
    input  wire [11:0] active_orders,
    input  wire [31:0] event_count,
    input  wire [31:0] cnt_rx_frames,
    input  wire [31:0] cnt_crc_err,
    input  wire [31:0] cnt_mold_msgs,
    input  wire [31:0] cnt_seq_gaps,
    input  wire [31:0] cnt_udp_packets,
    input  wire [31:0] cnt_itch_events,
    input  wire [31:0] cnt_fifo_events,
    input  wire [7:0]  error_code,

    // Board-owned quote and event rings. SW2/SW3 select one of the latest
    // four entries while the full rings remain available for paged VGA views.
    input  wire [1:0]  history_select,
    input  wire [7:0]  quote_history_count,
    input  wire [8:0]  event_history_count,
    input  wire [6:0]  quote_history_next,
    input  wire [7:0]  event_history_next,
    output wire [6:0]  quote_history_addr,
    input  wire [174:0] quote_history_data,
    output wire [7:0]  event_history_addr,
    input  wire [393:0] event_history_data,
    output wire [10:0] display_slot_addr,
    input  wire [46:0]  display_slot_data,
    output wire [9:0]  display_hash_set,
    input  wire [607:0] display_hash_ways,
    output wire [2:0]  display_stash_idx,
    input  wire [75:0] display_stash_data,
    output wire [13:0] display_price_addr,
    input  wire [31:0] display_price_data,
    input  wire [11:0] display_level_order_count,
    output wire [10:0] display_free_addr,
    input  wire [10:0] display_free_data,

    // VGA Physical Pins
    output reg         vga_hs,           // Horizontal Sync (active-low)
    output reg         vga_vs,           // Vertical Sync (active-low)
    output reg  [3:0]  vga_r,            // Red 4-bit DAC
    output reg  [3:0]  vga_g,            // Green 4-bit DAC
    output reg  [3:0]  vga_b             // Blue 4-bit DAC
);

    // -------------------------------------------------------------------------
    // 640x480 @ 60 Hz Standard Video Timing Parameters
    // -------------------------------------------------------------------------
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC   = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    wire h_sync_active = (h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC);
    wire v_sync_active = (v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC);
    wire video_on      = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    reg [1:0] history_select_meta, history_select_vga;
    always @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            history_select_meta <= 2'd0;
            history_select_vga <= 2'd0;
        end else begin
            history_select_meta <= history_select;
            history_select_vga <= history_select_meta;
        end
    end
    assign quote_history_addr = quote_history_next - 7'd1 - {5'd0, history_select_vga};
    assign event_history_addr = event_history_next - 8'd1 - {6'd0, history_select_vga};
    wire quote_history_visible = quote_history_count > {6'd0, history_select_vga};
    wire event_history_visible = event_history_count > {7'd0, history_select_vga};
    wire trace_insert = event_history_visible && event_history_data[108];
    wire trace_remove = event_history_visible && event_history_data[123];
    wire [2:0] selected_way = trace_insert ? event_history_data[97:95] : event_history_data[112:110];
    wire selected_stash = trace_insert ? event_history_data[94] : event_history_data[109];
    assign display_slot_addr = event_history_visible && event_history_data[182]
                             ? event_history_data[181:171] : 11'd0;
    assign display_hash_set = trace_insert ? event_history_data[107:98] :
                              trace_remove ? event_history_data[122:113] : 10'd0;
    assign display_stash_idx = selected_way;
    assign display_price_addr = event_history_visible && event_history_data[93]
                              ? event_history_data[92:79] : 14'd0;
    assign display_free_addr = active_orders < 12'd2048
                             ? 11'd2047 - active_orders[10:0] : 11'd0;
    wire selected_hash_valid = selected_stash ? display_stash_data[75] :
                               display_hash_ways[selected_way*76 + 75];
    wire [11:0] display_free_hex = {1'b0, display_free_data};

    // -------------------------------------------------------------------------
    // Tear-Free Coherent Snapshot on VBLANK Start
    // -------------------------------------------------------------------------
    reg        snap_book_valid;
    reg        snap_bid_valid;
    reg [31:0] snap_bid_p;
    reg [31:0] snap_bid_q;
    reg        snap_ask_valid;
    reg [31:0] snap_ask_p;
    reg [31:0] snap_ask_q;
    reg [31:0] snap_spread;
    reg [11:0] snap_orders;
    reg [31:0] snap_events;
    reg [31:0] snap_frames;
    reg [31:0] snap_crc_err;
    reg [31:0] snap_msgs;
    reg [31:0] snap_gaps;

    wire vblank_start = (v_cnt == V_ACTIVE) && (h_cnt == 0);

    always @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            snap_book_valid <= 1'b0;
            snap_bid_valid  <= 1'b0;
            snap_bid_p      <= 32'd0;
            snap_bid_q      <= 32'd0;
            snap_ask_valid  <= 1'b0;
            snap_ask_p      <= 32'd0;
            snap_ask_q      <= 32'd0;
            snap_spread     <= 32'd0;
            snap_orders     <= 12'd0;
            snap_events     <= 32'd0;
            snap_frames     <= 32'd0;
            snap_crc_err    <= 32'd0;
            snap_msgs       <= 32'd0;
            snap_gaps       <= 32'd0;
        end else if (vblank_start) begin
            snap_book_valid <= book_valid;
            snap_bid_valid  <= best_bid_valid;
            snap_bid_p      <= best_bid_price;
            snap_bid_q      <= best_bid_qty;
            snap_ask_valid  <= best_ask_valid;
            snap_ask_p      <= best_ask_price;
            snap_ask_q      <= best_ask_qty;
            snap_orders     <= active_orders;
            snap_events     <= event_count;
            snap_frames     <= cnt_rx_frames;
            snap_crc_err    <= cnt_crc_err;
            snap_msgs       <= cnt_mold_msgs;
            snap_gaps       <= cnt_seq_gaps;

            if (best_ask_valid && best_bid_valid && (best_ask_price >= best_bid_price))
                snap_spread <= best_ask_price - best_bid_price;
            else
                snap_spread <= 32'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Text Grid: 40 Columns x 30 Rows (16x16 pixels per character, 8x8 font scaled 2x)
    // -------------------------------------------------------------------------
    wire [5:0] col_idx = h_cnt[9:4]; // 0..39
    wire [4:0] row_idx = v_cnt[8:4]; // 0..29

    wire [2:0] font_x  = h_cnt[3:1]; // 0..7 (scaled 2x)
    wire [2:0] font_y  = v_cnt[3:1]; // 0..7 (scaled 2x)

    // Helper: 4-bit nibble to ASCII character
    function [7:0] nibble_to_hex;
        input [3:0] n;
        begin
            nibble_to_hex = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
        end
    endfunction

    // -------------------------------------------------------------------------
    // Procedural Character Selector based on (row_idx, col_idx)
    // -------------------------------------------------------------------------
    reg [7:0] char_code;
    reg [3:0] fg_r, fg_g, fg_b;

    always @(*) begin
        char_code = 8'h20; // Default Space
        fg_r = 4'hE; fg_g = 4'hE; fg_b = 4'hE; // Default White

        case (row_idx)
            // Title Bar
            5'd1: begin
                fg_r = 4'h0; fg_g = 4'hE; fg_b = 4'hF; // Cyan
                case (col_idx)
                    6'd2:  char_code = "F"; 6'd3:  char_code = "P"; 6'd4:  char_code = "G"; 6'd5:  char_code = "A";
                    6'd7:  char_code = "M"; 6'd8:  char_code = "A"; 6'd9:  char_code = "R"; 6'd10: char_code = "K";
                    6'd11: char_code = "E"; 6'd12: char_code = "T";
                    6'd14: char_code = "D"; 6'd15: char_code = "A"; 6'd16: char_code = "T"; 6'd17: char_code = "A";
                    6'd19: char_code = "P"; 6'd20: char_code = "R"; 6'd21: char_code = "O"; 6'd22: char_code = "C";
                    6'd23: char_code = "E"; 6'd24: char_code = "S"; 6'd25: char_code = "S"; 6'd26: char_code = "O"; 6'd27: char_code = "R";
                    default: char_code = " ";
                endcase
            end

            // Subtitle
            5'd2: begin
                fg_r = 4'h8; fg_g = 4'hA; fg_b = 4'hC;
                case (col_idx)
                    6'd2: char_code = "N"; 6'd3: char_code = "E"; 6'd4: char_code = "X"; 6'd5: char_code = "Y"; 6'd6: char_code = "S";
                    6'd8: char_code = "A"; 6'd9: char_code = "7"; 6'd10: char_code = "-"; 6'd11: char_code = "1"; 6'd12: char_code = "0"; 6'd13: char_code = "0"; 6'd14: char_code = "T";
                    6'd17: char_code = "I"; 6'd18: char_code = "T"; 6'd19: char_code = "C"; 6'd20: char_code = "H"; 6'd21: char_code = "5"; 6'd22: char_code = "."; 6'd23: char_code = "0";
                    default: char_code = " ";
                endcase
            end

            // Separator 1
            5'd3, 5'd13, 5'd23: begin
                fg_r = 4'h3; fg_g = 4'h5; fg_b = 4'h8;
                char_code = "-";
            end

            // Status Line
            5'd5: begin
                fg_r = 4'hF; fg_g = 4'hF; fg_b = 4'hF;
                case (col_idx)
                    6'd2: char_code = "S"; 6'd3: char_code = "T"; 6'd4: char_code = "A"; 6'd5: char_code = "T"; 6'd6: char_code = "U"; 6'd7: char_code = "S"; 6'd8: char_code = ":";
                    6'd10: begin
                        fg_r = snap_book_valid ? 4'h0 : 4'hF;
                        fg_g = snap_book_valid ? 4'hF : 4'h2;
                        fg_b = 4'h0;
                        char_code = snap_book_valid ? "O" : "E";
                    end
                    6'd11: begin
                        fg_r = snap_book_valid ? 4'h0 : 4'hF;
                        fg_g = snap_book_valid ? 4'hF : 4'h2;
                        fg_b = 4'h0;
                        char_code = snap_book_valid ? "K" : "R";
                    end
                    6'd18: char_code = "L"; 6'd19: char_code = "O"; 6'd20: char_code = "C"; 6'd21: char_code = "A"; 6'd22: char_code = "T"; 6'd23: char_code = "E"; 6'd24: char_code = ":";
                    6'd26: char_code = "#"; 6'd27: char_code = "0"; 6'd28: char_code = "0"; 6'd29: char_code = "0"; 6'd30: char_code = "1";
                    6'd34: char_code = "E"; 6'd35: char_code = ":";
                    6'd36: char_code = nibble_to_hex(error_code[7:4]);
                    6'd37: char_code = nibble_to_hex(error_code[3:0]);
                    default: char_code = " ";
                endcase
            end

            // BEST BID (Green)
            5'd7: begin
                fg_r = 4'h0; fg_g = 4'hF; fg_b = 4'h3; // Bright Green
                case (col_idx)
                    6'd2: char_code = "B"; 6'd3: char_code = "E"; 6'd4: char_code = "S"; 6'd5: char_code = "T";
                    6'd7: char_code = "B"; 6'd8: char_code = "I"; 6'd9: char_code = "D"; 6'd10: char_code = ":";
                    6'd12: char_code = "$";
                    6'd13: char_code = nibble_to_hex(snap_bid_p[31:28]);
                    6'd14: char_code = nibble_to_hex(snap_bid_p[27:24]);
                    6'd15: char_code = nibble_to_hex(snap_bid_p[23:20]);
                    6'd16: char_code = nibble_to_hex(snap_bid_p[19:16]);
                    6'd17: char_code = nibble_to_hex(snap_bid_p[15:12]);
                    6'd18: char_code = nibble_to_hex(snap_bid_p[11:8]);
                    6'd19: char_code = nibble_to_hex(snap_bid_p[7:4]);
                    6'd20: char_code = nibble_to_hex(snap_bid_p[3:0]);
                    6'd23: char_code = "Q"; 6'd24: char_code = "T"; 6'd25: char_code = "Y"; 6'd26: char_code = ":";
                    6'd28: char_code = nibble_to_hex(snap_bid_q[15:12]);
                    6'd29: char_code = nibble_to_hex(snap_bid_q[11:8]);
                    6'd30: char_code = nibble_to_hex(snap_bid_q[7:4]);
                    6'd31: char_code = nibble_to_hex(snap_bid_q[3:0]);
                    default: char_code = " ";
                endcase
            end

            // BEST ASK (Red)
            5'd9: begin
                fg_r = 4'hF; fg_g = 4'h3; fg_b = 4'h3; // Bright Red
                case (col_idx)
                    6'd2: char_code = "B"; 6'd3: char_code = "E"; 6'd4: char_code = "S"; 6'd5: char_code = "T";
                    6'd7: char_code = "A"; 6'd8: char_code = "S"; 6'd9: char_code = "K"; 6'd10: char_code = ":";
                    6'd12: char_code = "$";
                    6'd13: char_code = nibble_to_hex(snap_ask_p[31:28]);
                    6'd14: char_code = nibble_to_hex(snap_ask_p[27:24]);
                    6'd15: char_code = nibble_to_hex(snap_ask_p[23:20]);
                    6'd16: char_code = nibble_to_hex(snap_ask_p[19:16]);
                    6'd17: char_code = nibble_to_hex(snap_ask_p[15:12]);
                    6'd18: char_code = nibble_to_hex(snap_ask_p[11:8]);
                    6'd19: char_code = nibble_to_hex(snap_ask_p[7:4]);
                    6'd20: char_code = nibble_to_hex(snap_ask_p[3:0]);
                    6'd23: char_code = "Q"; 6'd24: char_code = "T"; 6'd25: char_code = "Y"; 6'd26: char_code = ":";
                    6'd28: char_code = nibble_to_hex(snap_ask_q[15:12]);
                    6'd29: char_code = nibble_to_hex(snap_ask_q[11:8]);
                    6'd30: char_code = nibble_to_hex(snap_ask_q[7:4]);
                    6'd31: char_code = nibble_to_hex(snap_ask_q[3:0]);
                    default: char_code = " ";
                endcase
            end

            // SPREAD (Yellow)
            5'd11: begin
                fg_r = 4'hF; fg_g = 4'hE; fg_b = 4'h2; // Bright Yellow
                case (col_idx)
                    6'd2: char_code = "S"; 6'd3: char_code = "P"; 6'd4: char_code = "R"; 6'd5: char_code = "E"; 6'd6: char_code = "A"; 6'd7: char_code = "D"; 6'd8: char_code = ":";
                    6'd12: char_code = "$";
                    6'd13: char_code = nibble_to_hex(snap_spread[31:28]);
                    6'd14: char_code = nibble_to_hex(snap_spread[27:24]);
                    6'd15: char_code = nibble_to_hex(snap_spread[23:20]);
                    6'd16: char_code = nibble_to_hex(snap_spread[19:16]);
                    6'd17: char_code = nibble_to_hex(snap_spread[15:12]);
                    6'd18: char_code = nibble_to_hex(snap_spread[11:8]);
                    6'd19: char_code = nibble_to_hex(snap_spread[7:4]);
                    6'd20: char_code = nibble_to_hex(snap_spread[3:0]);
                    default: char_code = " ";
                endcase
            end

            // ACTIVE ORDERS
            5'd15: begin
                fg_r = 4'hD; fg_g = 4'hD; fg_b = 4'hD;
                case (col_idx)
                    6'd2:  char_code = "A"; 6'd3:  char_code = "C"; 6'd4:  char_code = "T"; 6'd5:  char_code = "I";
                    6'd6:  char_code = "V"; 6'd7:  char_code = "E"; 6'd9:  char_code = "O"; 6'd10: char_code = "R";
                    6'd11: char_code = "D"; 6'd12: char_code = "E"; 6'd13: char_code = "R"; 6'd14: char_code = "S"; 6'd15: char_code = ":";
                    6'd18: char_code = nibble_to_hex(snap_orders[11:8]);
                    6'd19: char_code = nibble_to_hex(snap_orders[7:4]);
                    6'd20: char_code = nibble_to_hex(snap_orders[3:0]);
                    default: char_code = " ";
                endcase
            end

            // TOTAL EVENTS
            5'd17: begin
                fg_r = 4'hD; fg_g = 4'hD; fg_b = 4'hD;
                case (col_idx)
                    6'd2:  char_code = "T"; 6'd3:  char_code = "O"; 6'd4:  char_code = "T"; 6'd5:  char_code = "A"; 6'd6:  char_code = "L";
                    6'd8:  char_code = "E"; 6'd9:  char_code = "V"; 6'd10: char_code = "E"; 6'd11: char_code = "N"; 6'd12: char_code = "T"; 6'd13: char_code = "S"; 6'd14: char_code = ":";
                    6'd17: char_code = nibble_to_hex(snap_events[27:24]);
                    6'd18: char_code = nibble_to_hex(snap_events[23:20]);
                    6'd19: char_code = nibble_to_hex(snap_events[19:16]);
                    6'd20: char_code = nibble_to_hex(snap_events[15:12]);
                    6'd21: char_code = nibble_to_hex(snap_events[11:8]);
                    6'd22: char_code = nibble_to_hex(snap_events[7:4]);
                    6'd23: char_code = nibble_to_hex(snap_events[3:0]);
                    default: char_code = " ";
                endcase
            end

            // ETHERNET FRAMES & CRC ERRORS
            5'd19: begin
                fg_r = 4'h8; fg_g = 4'hC; fg_b = 4'hF;
                case (col_idx)
                    6'd2:  char_code = "E"; 6'd3:  char_code = "T"; 6'd4:  char_code = "H";
                    6'd6:  char_code = "R"; 6'd7:  char_code = "X"; 6'd8:  char_code = ":";
                    6'd10: char_code = nibble_to_hex(snap_frames[15:12]);
                    6'd11: char_code = nibble_to_hex(snap_frames[11:8]);
                    6'd12: char_code = nibble_to_hex(snap_frames[7:4]);
                    6'd13: char_code = nibble_to_hex(snap_frames[3:0]);
                    6'd18: char_code = "C"; 6'd19: char_code = "R"; 6'd20: char_code = "C"; 6'd21: char_code = "-"; 6'd22: char_code = "E"; 6'd23: char_code = "R"; 6'd24: char_code = "R"; 6'd25: char_code = ":";
                    6'd27: char_code = nibble_to_hex(snap_crc_err[7:4]);
                    6'd28: char_code = nibble_to_hex(snap_crc_err[3:0]);
                    default: char_code = " ";
                endcase
            end

            // MOLD MESSAGES & SEQUENCE GAPS
            5'd21: begin
                fg_r = 4'h8; fg_g = 4'hC; fg_b = 4'hF;
                case (col_idx)
                    6'd2:  char_code = "M"; 6'd3:  char_code = "O"; 6'd4:  char_code = "L"; 6'd5:  char_code = "D";
                    6'd7:  char_code = "M"; 6'd8:  char_code = "S"; 6'd9:  char_code = "G"; 6'd10: char_code = ":";
                    6'd12: char_code = nibble_to_hex(snap_msgs[15:12]);
                    6'd13: char_code = nibble_to_hex(snap_msgs[11:8]);
                    6'd14: char_code = nibble_to_hex(snap_msgs[7:4]);
                    6'd15: char_code = nibble_to_hex(snap_msgs[3:0]);
                    6'd18: char_code = "S"; 6'd19: char_code = "E"; 6'd20: char_code = "Q"; 6'd21: char_code = "-"; 6'd22: char_code = "G"; 6'd23: char_code = "A"; 6'd24: char_code = "P"; 6'd25: char_code = ":";
                    6'd27: char_code = nibble_to_hex(snap_gaps[7:4]);
                    6'd28: char_code = nibble_to_hex(snap_gaps[3:0]);
                    default: char_code = " ";
                endcase
            end

            5'd24: begin
                fg_r = 4'h8; fg_g = 4'hC; fg_b = 4'hF;
                case (col_idx)
                    6'd2: char_code = "U"; 6'd3: char_code = "D";
                    6'd4: char_code = "P"; 6'd5: char_code = ":";
                    6'd12: char_code = "I"; 6'd13: char_code = "T";
                    6'd14: char_code = "C"; 6'd15: char_code = "H";
                    6'd16: char_code = ":";
                    6'd23: char_code = "F"; 6'd24: char_code = "I";
                    6'd25: char_code = "F"; 6'd26: char_code = "O";
                    6'd27: char_code = ":";
                    default: begin
                        if (col_idx >= 6'd6 && col_idx <= 6'd9)
                            char_code = nibble_to_hex(cnt_udp_packets[15 - ((col_idx - 6'd6) * 4) -: 4]);
                        else if (col_idx >= 6'd17 && col_idx <= 6'd20)
                            char_code = nibble_to_hex(cnt_itch_events[15 - ((col_idx - 6'd17) * 4) -: 4]);
                        else if (col_idx >= 6'd28 && col_idx <= 6'd31)
                            char_code = nibble_to_hex(cnt_fifo_events[15 - ((col_idx - 6'd28) * 4) -: 4]);
                    end
                endcase
            end

            // Browse board-owned histories with physical SW2/SW3.
            5'd27: begin
                fg_r = 4'h8; fg_g = 4'hC; fg_b = 4'hF;
                if (quote_history_visible) begin
                    case (col_idx)
                        6'd2: char_code = "H"; 6'd3: char_code = "I";
                        6'd4: char_code = "S"; 6'd5: char_code = "T";
                        6'd7: char_code = "#";
                        6'd13: char_code = "B"; 6'd14: char_code = ":";
                        6'd24: char_code = "A"; 6'd25: char_code = ":";
                        default: begin
                            if (col_idx >= 6'd8 && col_idx <= 6'd11)
                                char_code = nibble_to_hex(quote_history_data[15 - ((col_idx - 6'd8) * 4) -: 4]);
                            else if (col_idx >= 6'd15 && col_idx <= 6'd22)
                                char_code = nibble_to_hex(quote_history_data[172 - ((col_idx - 6'd15) * 4) -: 4]);
                            else if (col_idx >= 6'd26 && col_idx <= 6'd33)
                                char_code = nibble_to_hex(quote_history_data[107 - ((col_idx - 6'd26) * 4) -: 4]);
                        end
                    endcase
                end
            end
            5'd28: begin
                fg_r = 4'h8; fg_g = 4'hA; fg_b = 4'hC;
                if (event_history_visible) begin
                    case (col_idx)
                        6'd2: char_code = "E"; 6'd3: char_code = "V";
                        6'd4: char_code = "E"; 6'd5: char_code = "N";
                        6'd6: char_code = "T"; 6'd8: char_code = "#";
                        6'd14: char_code = "O"; 6'd15: char_code = "P";
                        6'd16: char_code = ":";
                        6'd19: char_code = "I"; 6'd20: char_code = "D";
                        6'd21: char_code = ":";
                        default: begin
                            if (col_idx >= 6'd9 && col_idx <= 6'd12)
                                char_code = nibble_to_hex(event_history_data[377 - ((col_idx - 6'd9) * 4) -: 4]);
                            else if (col_idx == 6'd17)
                                char_code = nibble_to_hex(event_history_data[314:311]);
                            else if (col_idx >= 6'd22 && col_idx <= 6'd29)
                                char_code = nibble_to_hex(event_history_data[278 - ((col_idx - 6'd22) * 4) -: 4]);
                        end
                    endcase
                end
            end
            5'd29: begin
                fg_r = 4'h9; fg_g = 4'hB; fg_b = 4'hC;
                if (event_history_visible) begin
                    case (col_idx)
                        6'd2: char_code = "R"; 6'd3: char_code = "A";
                        6'd4: char_code = "M";
                        6'd6: char_code = "S"; 6'd7: char_code = ":";
                        6'd8: char_code = display_slot_data[46] ? "1" : "0";
                        6'd10: char_code = "Q"; 6'd11: char_code = ":";
                        6'd17: char_code = "P"; 6'd18: char_code = ":";
                        6'd24: char_code = "H"; 6'd25: char_code = ":";
                        6'd26: char_code = selected_hash_valid ? "1" : "0";
                        6'd28: char_code = "F"; 6'd29: char_code = ":";
                        6'd34: char_code = "C"; 6'd35: char_code = ":";
                        default: begin
                            if (col_idx >= 6'd12 && col_idx <= 6'd15)
                                char_code = nibble_to_hex(display_slot_data[15 - ((col_idx - 6'd12) * 4) -: 4]);
                            else if (col_idx >= 6'd19 && col_idx <= 6'd22)
                                char_code = nibble_to_hex(display_price_data[15 - ((col_idx - 6'd19) * 4) -: 4]);
                            else if (col_idx >= 6'd30 && col_idx <= 6'd32)
                                char_code = nibble_to_hex(display_free_hex[11 - ((col_idx - 6'd30) * 4) -: 4]);
                            else if (col_idx >= 6'd36 && col_idx <= 6'd38)
                                char_code = nibble_to_hex(display_level_order_count[11 - ((col_idx - 6'd36) * 4) -: 4]);
                        end
                    endcase
                end
            end

            default: begin
                char_code = " ";
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Font ROM (Standard 8x8 bitmap table)
    // -------------------------------------------------------------------------
    function [7:0] font_lookup;
        input [7:0] ascii;
        input [2:0] y;
        begin
        case (ascii)
            "0": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h6E; 3'd3: font_lookup = 8'h76; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "1": case(y) 3'd0: font_lookup = 8'h18; 3'd1: font_lookup = 8'h38; 3'd2: font_lookup = 8'h18; 3'd3: font_lookup = 8'h18; 3'd4: font_lookup = 8'h18; 3'd5: font_lookup = 8'h18; 3'd6: font_lookup = 8'h7E; default: font_lookup = 8'h00; endcase
            "2": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h06; 3'd3: font_lookup = 8'h0C; 3'd4: font_lookup = 8'h30; 3'd5: font_lookup = 8'h60; 3'd6: font_lookup = 8'h7E; default: font_lookup = 8'h00; endcase
            "3": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h06; 3'd3: font_lookup = 8'h1C; 3'd4: font_lookup = 8'h06; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "4": case(y) 3'd0: font_lookup = 8'h0C; 3'd1: font_lookup = 8'h1C; 3'd2: font_lookup = 8'h34; 3'd3: font_lookup = 8'h64; 3'd4: font_lookup = 8'h7E; 3'd5: font_lookup = 8'h04; 3'd6: font_lookup = 8'h04; default: font_lookup = 8'h00; endcase
            "5": case(y) 3'd0: font_lookup = 8'h7E; 3'd1: font_lookup = 8'h60; 3'd2: font_lookup = 8'h7C; 3'd3: font_lookup = 8'h06; 3'd4: font_lookup = 8'h06; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "6": case(y) 3'd0: font_lookup = 8'h1C; 3'd1: font_lookup = 8'h30; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h7C; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "7": case(y) 3'd0: font_lookup = 8'h7E; 3'd1: font_lookup = 8'h06; 3'd2: font_lookup = 8'h0C; 3'd3: font_lookup = 8'h18; 3'd4: font_lookup = 8'h30; 3'd5: font_lookup = 8'h30; 3'd6: font_lookup = 8'h30; default: font_lookup = 8'h00; endcase
            "8": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h3C; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "9": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h3E; 3'd4: font_lookup = 8'h06; 3'd5: font_lookup = 8'h0C; 3'd6: font_lookup = 8'h38; default: font_lookup = 8'h00; endcase
            "A": case(y) 3'd0: font_lookup = 8'h18; 3'd1: font_lookup = 8'h3C; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h66; 3'd4: font_lookup = 8'h7E; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h66; default: font_lookup = 8'h00; endcase
            "B": case(y) 3'd0: font_lookup = 8'h7C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h7C; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h7C; default: font_lookup = 8'h00; endcase
            "C": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h60; 3'd4: font_lookup = 8'h60; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "D": case(y) 3'd0: font_lookup = 8'h78; 3'd1: font_lookup = 8'h6C; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h66; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h6C; 3'd6: font_lookup = 8'h78; default: font_lookup = 8'h00; endcase
            "E": case(y) 3'd0: font_lookup = 8'h7E; 3'd1: font_lookup = 8'h60; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h7C; 3'd4: font_lookup = 8'h60; 3'd5: font_lookup = 8'h60; 3'd6: font_lookup = 8'h7E; default: font_lookup = 8'h00; endcase
            "F": case(y) 3'd0: font_lookup = 8'h7E; 3'd1: font_lookup = 8'h60; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h7C; 3'd4: font_lookup = 8'h60; 3'd5: font_lookup = 8'h60; 3'd6: font_lookup = 8'h60; default: font_lookup = 8'h00; endcase
            "G": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h6E; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "H": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h7E; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h66; default: font_lookup = 8'h00; endcase
            "I": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h18; 3'd2: font_lookup = 8'h18; 3'd3: font_lookup = 8'h18; 3'd4: font_lookup = 8'h18; 3'd5: font_lookup = 8'h18; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "K": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h6C; 3'd2: font_lookup = 8'h78; 3'd3: font_lookup = 8'h70; 3'd4: font_lookup = 8'h78; 3'd5: font_lookup = 8'h6C; 3'd6: font_lookup = 8'h66; default: font_lookup = 8'h00; endcase
            "L": case(y) 3'd0: font_lookup = 8'h60; 3'd1: font_lookup = 8'h60; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h60; 3'd4: font_lookup = 8'h60; 3'd5: font_lookup = 8'h60; 3'd6: font_lookup = 8'h7E; default: font_lookup = 8'h00; endcase
            "M": case(y) 3'd0: font_lookup = 8'h63; 3'd1: font_lookup = 8'h77; 3'd2: font_lookup = 8'h7F; 3'd3: font_lookup = 8'h6B; 3'd4: font_lookup = 8'h63; 3'd5: font_lookup = 8'h63; 3'd6: font_lookup = 8'h63; default: font_lookup = 8'h00; endcase
            "N": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h76; 3'd2: font_lookup = 8'h7E; 3'd3: font_lookup = 8'h7E; 3'd4: font_lookup = 8'h6E; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h66; default: font_lookup = 8'h00; endcase
            "O": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h66; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "P": case(y) 3'd0: font_lookup = 8'h7C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h7C; 3'd4: font_lookup = 8'h60; 3'd5: font_lookup = 8'h60; 3'd6: font_lookup = 8'h60; default: font_lookup = 8'h00; endcase
            "Q": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h66; 3'd4: font_lookup = 8'h6A; 3'd5: font_lookup = 8'h6C; 3'd6: font_lookup = 8'h36; default: font_lookup = 8'h00; endcase
            "R": case(y) 3'd0: font_lookup = 8'h7C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h7C; 3'd4: font_lookup = 8'h78; 3'd5: font_lookup = 8'h6C; 3'd6: font_lookup = 8'h66; default: font_lookup = 8'h00; endcase
            "S": case(y) 3'd0: font_lookup = 8'h3C; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h60; 3'd3: font_lookup = 8'h3C; 3'd4: font_lookup = 8'h06; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "T": case(y) 3'd0: font_lookup = 8'h7E; 3'd1: font_lookup = 8'h18; 3'd2: font_lookup = 8'h18; 3'd3: font_lookup = 8'h18; 3'd4: font_lookup = 8'h18; 3'd5: font_lookup = 8'h18; 3'd6: font_lookup = 8'h18; default: font_lookup = 8'h00; endcase
            "U": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h66; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h3C; default: font_lookup = 8'h00; endcase
            "V": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h66; 3'd4: font_lookup = 8'h66; 3'd5: font_lookup = 8'h3C; 3'd6: font_lookup = 8'h18; default: font_lookup = 8'h00; endcase
            "X": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h3C; 3'd3: font_lookup = 8'h18; 3'd4: font_lookup = 8'h3C; 3'd5: font_lookup = 8'h66; 3'd6: font_lookup = 8'h66; default: font_lookup = 8'h00; endcase
            "Y": case(y) 3'd0: font_lookup = 8'h66; 3'd1: font_lookup = 8'h66; 3'd2: font_lookup = 8'h66; 3'd3: font_lookup = 8'h3C; 3'd4: font_lookup = 8'h18; 3'd5: font_lookup = 8'h18; 3'd6: font_lookup = 8'h18; default: font_lookup = 8'h00; endcase
            "-": case(y) 3'd3: font_lookup = 8'h7E; default: font_lookup = 8'h00; endcase
            ":": case(y) 3'd1: font_lookup = 8'h18; 3'd2: font_lookup = 8'h18; 3'd4: font_lookup = 8'h18; 3'd5: font_lookup = 8'h18; default: font_lookup = 8'h00; endcase
            "$": case(y) 3'd0: font_lookup = 8'h18; 3'd1: font_lookup = 8'h3E; 3'd2: font_lookup = 8'h58; 3'd3: font_lookup = 8'h3C; 3'd4: font_lookup = 8'h0E; 3'd5: font_lookup = 8'h7C; 3'd6: font_lookup = 8'h18; default: font_lookup = 8'h00; endcase
            ".": case(y) 3'd5: font_lookup = 8'h18; 3'd6: font_lookup = 8'h18; default: font_lookup = 8'h00; endcase
            "#": case(y) 3'd1: font_lookup = 8'h24; 3'd2: font_lookup = 8'h7E; 3'd3: font_lookup = 8'h24; 3'd4: font_lookup = 8'h7E; 3'd5: font_lookup = 8'h24; default: font_lookup = 8'h00; endcase
            default: font_lookup = 8'h00;
        endcase
            end
    endfunction

    // -------------------------------------------------------------------------
    // Pixel Output Pipeline (Registered)
    // -------------------------------------------------------------------------
    wire [7:0] font_row_bits = font_lookup(char_code, font_y);
    wire pixel_on = font_row_bits[3'd7 - font_x];

    // Graphical Depth Bar on row 25-26
    wire is_bar_row = (row_idx == 5'd25 || row_idx == 5'd26);
    wire [9:0] bid_bar_w = (snap_bid_q > 32'd250) ? 10'd250 : snap_bid_q[9:0];
    wire [9:0] ask_bar_w = (snap_ask_q > 32'd250) ? 10'd250 : snap_ask_q[9:0];

    wire in_bid_bar = is_bar_row && (h_cnt >= 10'd50)  && (h_cnt < 10'd50  + bid_bar_w);
    wire in_ask_bar = is_bar_row && (h_cnt >= 10'd350) && (h_cnt < 10'd350 + ask_bar_w);

    always @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
            vga_r  <= 4'h0;
            vga_g  <= 4'h0;
            vga_b  <= 4'h0;
        end else begin
            vga_hs <= ~h_sync_active;
            vga_vs <= ~v_sync_active;

            if (video_on) begin
                if (in_bid_bar) begin
                    // Bid depth bar: Green
                    vga_r <= 4'h0; vga_g <= 4'hE; vga_b <= 4'h2;
                end else if (in_ask_bar) begin
                    // Ask depth bar: Red
                    vga_r <= 4'hE; vga_g <= 4'h1; vga_b <= 4'h1;
                end else if (pixel_on) begin
                    // Character foreground
                    vga_r <= fg_r;
                    vga_g <= fg_g;
                    vga_b <= fg_b;
                end else begin
                    // Background: Dark Slate Blue
                    vga_r <= 4'h0;
                    vga_g <= 4'h1;
                    vga_b <= 4'h2;
                end
            end else begin
                // Blanking interval
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end
        end
    end

endmodule
