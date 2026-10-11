// =============================================================================
// File: lob_bbo.sv
// Description: Best Bid & Offer (BBO) tracking and price computation
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §14, §16, §18
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module lob_bbo (
    input  logic        clk,
    input  logic        rst_n,

    // Runtime Configuration
    input  logic [31:0] cfg_price_base,
    input  logic [31:0] cfg_tick,

    // Fast-Path Direct Updates from Operation Commit
    input  logic        bbo_direct_upd_en,
    input  logic        bbo_direct_side,     // 0=Bid, 1=Ask
    input  logic [12:0] bbo_direct_pidx,
    input  logic [31:0] bbo_direct_qty,

    // Search Results Update Port (When previous best level reached zero)
    input  logic        bbo_search_upd_en,
    input  logic        bbo_search_side,     // 0=Bid, 1=Ask
    input  logic        bbo_search_valid,    // 0 if book side empty
    input  logic [12:0] bbo_search_pidx,
    input  logic [31:0] bbo_search_qty,

    // Clear / Reset
    input  logic        clear_en,

    // External BBO Outputs
    output logic        best_bid_valid,
    output logic [12:0] best_bid_pidx,
    output logic [31:0] best_bid_price,
    output logic [31:0] best_bid_qty,

    output logic        best_ask_valid,
    output logic [12:0] best_ask_pidx,
    output logic [31:0] best_ask_price,
    output logic [31:0] best_ask_qty,

    // Signal indicating if removing a level triggers an occupancy search
    input  logic        check_side,
    input  logic [12:0] check_pidx,
    output logic        triggers_search
);

    logic        bid_valid_r;
    logic [12:0] bid_pidx_r;
    logic [31:0] bid_qty_r;

    logic        ask_valid_r;
    logic [12:0] ask_pidx_r;
    logic [31:0] ask_qty_r;

    // Check if an operation that clears a level targets the current best level
    always_comb begin
        if (check_side == 1'b0) begin
            triggers_search = bid_valid_r && (check_pidx == bid_pidx_r);
        end else begin
            triggers_search = ask_valid_r && (check_pidx == ask_pidx_r);
        end
    end

    // -------------------------------------------------------------------------
    // BBO Tracking Registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bid_valid_r    <= 1'b0;
            bid_pidx_r     <= '0;
            bid_qty_r      <= 32'd0;
            ask_valid_r    <= 1'b0;
            ask_pidx_r     <= '0;
            ask_qty_r      <= 32'd0;
        end else if (clear_en) begin
            bid_valid_r <= 1'b0;
            bid_pidx_r  <= '0;
            bid_qty_r   <= 32'd0;
            ask_valid_r <= 1'b0;
            ask_pidx_r  <= '0;
            ask_qty_r   <= 32'd0;
        end else begin
                // 1. Direct Commit Update (Fast Path)
                if (bbo_direct_upd_en) begin
                    if (bbo_direct_side == 1'b0) begin
                        // BID:
                        // Case A: Better price than current best, or book was empty
                        if (!bid_valid_r || (bbo_direct_pidx > bid_pidx_r)) begin
                            if (bbo_direct_qty > 0) begin
                                bid_valid_r <= 1'b1;
                                bid_pidx_r  <= bbo_direct_pidx;
                                bid_qty_r   <= bbo_direct_qty;
                            end
                        end
                        // Case B: Same price as current best
                        else if (bbo_direct_pidx == bid_pidx_r) begin
                            if (bbo_direct_qty > 0) begin
                                bid_qty_r <= bbo_direct_qty;
                            end
                            // If drops to zero, bbo_search_upd_en will update it after search
                        end
                    end else begin
                        // ASK:
                        // Case A: Better (lower) price than current best, or book was empty
                        if (!ask_valid_r || (bbo_direct_pidx < ask_pidx_r)) begin
                            if (bbo_direct_qty > 0) begin
                                ask_valid_r <= 1'b1;
                                ask_pidx_r  <= bbo_direct_pidx;
                                ask_qty_r   <= bbo_direct_qty;
                            end
                        end
                        // Case B: Same price as current best
                        else if (bbo_direct_pidx == ask_pidx_r) begin
                            if (bbo_direct_qty > 0) begin
                                ask_qty_r <= bbo_direct_qty;
                            end
                        end
                    end
                end

                // 2. Search Update (When previous best level emptied out)
                if (bbo_search_upd_en) begin
                    if (bbo_search_side == 1'b0) begin
                        bid_valid_r <= bbo_search_valid;
                        bid_pidx_r  <= bbo_search_pidx;
                        bid_qty_r   <= bbo_search_valid ? bbo_search_qty : 32'd0;
                    end else begin
                        ask_valid_r <= bbo_search_valid;
                        ask_pidx_r  <= bbo_search_pidx;
                        ask_qty_r   <= bbo_search_valid ? bbo_search_qty : 32'd0;
                    end
                end
            end
        end

    // -------------------------------------------------------------------------
    // 2-Stage Pipelined Price DSP Multiplier & Adder for 100 MHz Timing Closure
    // -------------------------------------------------------------------------
    logic        s1_bid_valid;
    logic [12:0] s1_bid_pidx;
    logic [31:0] s1_bid_qty;
    logic [31:0] s1_bid_prod;
    logic [31:0] s1_bid_base;

    logic        s1_ask_valid;
    logic [12:0] s1_ask_pidx;
    logic [31:0] s1_ask_qty;
    logic [31:0] s1_ask_prod;
    logic [31:0] s1_ask_base;

    logic [31:0] tick_pipe;
    logic [31:0] base_pipe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_pipe <= 32'd1000;
            base_pipe <= 32'd900000;
        end else begin
            tick_pipe <= cfg_tick;
            base_pipe <= cfg_price_base;
        end
    end

    // Stage 1: DSP Multiplication (pidx * tick) & pipeline registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_bid_valid <= 1'b0;
            s1_bid_pidx  <= '0;
            s1_bid_qty   <= 32'd0;
            s1_bid_prod  <= 32'd0;
            s1_bid_base  <= 32'd0;

            s1_ask_valid <= 1'b0;
            s1_ask_pidx  <= '0;
            s1_ask_qty   <= 32'd0;
            s1_ask_prod  <= 32'd0;
            s1_ask_base  <= 32'd0;
        end else if (clear_en) begin
            s1_bid_valid <= 1'b0;
            s1_bid_pidx  <= '0;
            s1_bid_qty   <= 32'd0;
            s1_bid_prod  <= 32'd0;
            s1_bid_base  <= 32'd0;

            s1_ask_valid <= 1'b0;
            s1_ask_pidx  <= '0;
            s1_ask_qty   <= 32'd0;
            s1_ask_prod  <= 32'd0;
            s1_ask_base  <= 32'd0;
        end else begin
            s1_bid_valid <= bid_valid_r;
            s1_bid_pidx  <= bid_pidx_r;
            s1_bid_qty   <= bid_qty_r;
            s1_bid_prod  <= 32'(bid_pidx_r) * tick_pipe;
            s1_bid_base  <= base_pipe;

            s1_ask_valid <= ask_valid_r;
            s1_ask_pidx  <= ask_pidx_r;
            s1_ask_qty   <= ask_qty_r;
            s1_ask_prod  <= 32'(ask_pidx_r) * tick_pipe;
            s1_ask_base  <= base_pipe;
        end
    end

    // Stage 2: Final Addition (base + prod) & Output Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_bid_valid <= 1'b0;
            best_bid_pidx  <= '0;
            best_bid_price <= 32'd0;
            best_bid_qty   <= 32'd0;

            best_ask_valid <= 1'b0;
            best_ask_pidx  <= '0;
            best_ask_price <= 32'd0;
            best_ask_qty   <= 32'd0;
        end else if (clear_en) begin
            best_bid_valid <= 1'b0;
            best_bid_pidx  <= '0;
            best_bid_price <= 32'd0;
            best_bid_qty   <= 32'd0;

            best_ask_valid <= 1'b0;
            best_ask_pidx  <= '0;
            best_ask_price <= 32'd0;
            best_ask_qty   <= 32'd0;
        end else begin
            best_bid_valid <= s1_bid_valid;
            best_bid_pidx  <= s1_bid_pidx;
            best_bid_price <= s1_bid_valid ? (s1_bid_base + s1_bid_prod) : 32'd0;
            best_bid_qty   <= s1_bid_qty;

            best_ask_valid <= s1_ask_valid;
            best_ask_pidx  <= s1_ask_pidx;
            best_ask_price <= s1_ask_valid ? (s1_ask_base + s1_ask_prod) : 32'd0;
            best_ask_qty   <= s1_ask_qty;
        end
    end

endmodule
