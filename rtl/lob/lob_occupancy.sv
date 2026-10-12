// =============================================================================
// File: lob_occupancy.sv
// Description: 3-level hierarchical occupancy bitmask trees and priority encoders
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §14, §15, §16
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module lob_occupancy #(
    parameter int unsigned PRICE_LEVELS_PER_SIDE = lob_pkg::PRICE_LEVELS_PER_SIDE, // 8,192
    parameter int unsigned OCC_LEAF_WORDS         = lob_pkg::OCC_LEAF_WORDS          // 256
) (
    input  logic        clk,
    input  logic        rst_n,

    // Hardware Initialization
    input  logic        init_start,
    output logic        init_busy,
    output logic        init_done,

    // Prefetch / Normal Leaf Word Read Port (Latency = 1 cycle)
    input  logic        leaf_rd_en,
    input  logic        leaf_rd_side,       // 0=Bid, 1=Ask
    input  logic [7:0]  leaf_rd_word_idx,   // pidx[12:5]
    output logic [31:0] leaf_rd_data,

    // Leaf Update Commit Port
    input  logic        leaf_upd_en,
    input  logic        leaf_upd_side,      // 0=Bid, 1=Ask
    input  logic [12:0] leaf_upd_pidx,      // pidx
    input  logic        leaf_upd_bit_val,   // 1=Add (level non-zero), 0=Remove (level zero)

    // Search Engine Request / Result
    input  logic        search_start,
    input  logic        search_side,        // 0=Bid (highest pidx), 1=Ask (lowest pidx)
    output logic        search_busy,
    output logic        search_done,
    output logic        search_valid,       // 1 if side is non-empty
    output logic [12:0] search_pidx,

    // Live occupancy status flags
    output logic        bid_has_orders,
    output logic        ask_has_orders
);

    // -------------------------------------------------------------------------
    // Leaf Memories (256 words x 32 bits per side)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *)
    logic [31:0] leaf_mem_bid [0:OCC_LEAF_WORDS-1];

    (* ram_style = "block" *)
    logic [31:0] leaf_mem_ask [0:OCC_LEAF_WORDS-1];

    // L1 Register Masks (256 bits per side)
    logic [255:0] l1_bid;
    logic [255:0] l1_ask;

    // L0 Register Masks (8 bits per side)
    logic [7:0]   l0_bid;
    logic [7:0]   l0_ask;

    assign bid_has_orders = (l0_bid != 8'd0);
    assign ask_has_orders = (l0_ask != 8'd0);

    // Initialization counter (256 cycles)
    logic [8:0] init_cnt;
    logic       initializing;

    assign init_busy = initializing;

    // -------------------------------------------------------------------------
    // Priority Encoder Functions
    // -------------------------------------------------------------------------
    function automatic logic [2:0] prio_enc_high_8(input logic [7:0] in);
        for (int i = 7; i >= 0; i--) begin
            if (in[i]) return 3'(i);
        end
        return 3'd0;
    endfunction

    function automatic logic [4:0] prio_enc_high_32(input logic [31:0] in);
        for (int i = 31; i >= 0; i--) begin
            if (in[i]) return 5'(i);
        end
        return 5'd0;
    endfunction

    function automatic logic [2:0] prio_enc_low_8(input logic [7:0] in);
        for (int i = 0; i < 8; i++) begin
            if (in[i]) return 3'(i);
        end
        return 3'd0;
    endfunction

    function automatic logic [4:0] prio_enc_low_32(input logic [31:0] in);
        for (int i = 0; i < 32; i++) begin
            if (in[i]) return 5'(i);
        end
        return 5'd0;
    endfunction

    // -------------------------------------------------------------------------
    // Search FSM (S0..S4: 4-stage pipelined search)
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        SRCH_IDLE = 3'd0,
        SRCH_S0   = 3'd1,
        SRCH_S1   = 3'd2,
        SRCH_S2   = 3'd3,
        SRCH_S3   = 3'd4,
        SRCH_S4   = 3'd5
    } srch_state_t;

    srch_state_t srch_state;
    logic        srch_side_reg;
    logic [2:0]  srch_g;
    logic [4:0]  srch_j;
    logic [4:0]  srch_m;
    logic [7:0]  srch_leaf_addr;
    logic [31:0] srch_leaf_data;
    logic        srch_empty;

    assign search_busy = (srch_state != SRCH_IDLE);

    // Read arbitration for Leaf RAMs (Search vs Normal prefetch)
    logic       eff_leaf_rd_en;
    logic       eff_leaf_rd_side;
    logic [7:0] eff_leaf_rd_addr;

    always_comb begin
        if (srch_state == SRCH_S2) begin
            eff_leaf_rd_en   = 1'b1;
            eff_leaf_rd_side = srch_side_reg;
            eff_leaf_rd_addr = {srch_g, srch_j};
        end else begin
            eff_leaf_rd_en   = leaf_rd_en;
            eff_leaf_rd_side = leaf_rd_side;
            eff_leaf_rd_addr = leaf_rd_word_idx;
        end
    end

    // Leaf RAM Read Ports
    logic [31:0] leaf_rd_data_reg;

    always_ff @(posedge clk) begin
        if (eff_leaf_rd_en) begin
            if (eff_leaf_rd_side == 1'b0) begin
                leaf_rd_data_reg <= leaf_mem_bid[eff_leaf_rd_addr];
            end else begin
                leaf_rd_data_reg <= leaf_mem_ask[eff_leaf_rd_addr];
            end
        end
    end

    assign leaf_rd_data   = leaf_rd_data_reg;
    assign srch_leaf_data = leaf_rd_data_reg;

    // Search state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            srch_state    <= SRCH_IDLE;
            srch_side_reg <= 1'b0;
            srch_g        <= '0;
            srch_j        <= '0;
            srch_m        <= '0;
            srch_empty    <= 1'b0;
            search_done   <= 1'b0;
            search_valid  <= 1'b0;
            search_pidx   <= '0;
        end else begin
            search_done <= 1'b0;

            case (srch_state)
                SRCH_IDLE: begin
                    if (search_start && !initializing) begin
                        srch_side_reg <= search_side;
                        srch_state    <= SRCH_S0;
                    end
                end

                SRCH_S0: begin
                    // Evaluate L0 mask
                    if (srch_side_reg == 1'b0) begin
                        // Bid side: highest set bit in L0
                        if (l0_bid == 8'd0) begin
                            srch_empty   <= 1'b1;
                            search_done  <= 1'b1;
                            search_valid <= 1'b0;
                            search_pidx  <= '0;
                            srch_state   <= SRCH_IDLE;
                        end else begin
                            srch_g     <= prio_enc_high_8(l0_bid);
                            srch_state <= SRCH_S1;
                        end
                    end else begin
                        // Ask side: lowest set bit in L0
                        if (l0_ask == 8'd0) begin
                            srch_empty   <= 1'b1;
                            search_done  <= 1'b1;
                            search_valid <= 1'b0;
                            search_pidx  <= '0;
                            srch_state   <= SRCH_IDLE;
                        end else begin
                            srch_g     <= prio_enc_low_8(l0_ask);
                            srch_state <= SRCH_S1;
                        end
                    end
                end

                SRCH_S1: begin
                    // Evaluate 32-bit slice of L1 mask
                    if (srch_side_reg == 1'b0) begin
                        srch_j     <= prio_enc_high_32(l1_bid[srch_g*32 +: 32]);
                        srch_state <= SRCH_S2;
                    end else begin
                        srch_j     <= prio_enc_low_32(l1_ask[srch_g*32 +: 32]);
                        srch_state <= SRCH_S2;
                    end
                end

                SRCH_S2: begin
                    // Memory address eff_leaf_rd_addr = {srch_g, srch_j} is read
                    srch_state <= SRCH_S3;
                end

                SRCH_S3: begin
                    // Leaf memory output is now valid in srch_leaf_data
                    if (srch_side_reg == 1'b0) begin
                        srch_m <= prio_enc_high_32(srch_leaf_data);
                    end else begin
                        srch_m <= prio_enc_low_32(srch_leaf_data);
                    end
                    srch_state <= SRCH_S4;
                end

                SRCH_S4: begin
                    // Assemble pidx = {g, j, m}
                    search_done  <= 1'b1;
                    search_valid <= 1'b1;
                    search_pidx  <= {srch_g, srch_j, srch_m};
                    srch_state   <= SRCH_IDLE;
                end

                default: srch_state <= SRCH_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Memory Write & Hierarchy Updates (Leaf, L1, L0)
    // -------------------------------------------------------------------------
    logic [7:0]  upd_word_addr;
    logic [4:0]  upd_bit_pos;
    logic [2:0]  upd_grp_idx;
    logic [31:0] upd_new_word_bid;
    logic [31:0] upd_new_word_ask;

    assign upd_word_addr = leaf_upd_pidx[12:5];
    assign upd_bit_pos   = leaf_upd_pidx[4:0];
    assign upd_grp_idx   = leaf_upd_pidx[12:10];

    // Compute updated word from current leaf read / memory
    always_comb begin
        upd_new_word_bid = leaf_mem_bid[upd_word_addr];
        upd_new_word_ask = leaf_mem_ask[upd_word_addr];
        if (leaf_upd_side == 1'b0) begin
            upd_new_word_bid[upd_bit_pos] = leaf_upd_bit_val;
        end else begin
            upd_new_word_ask[upd_bit_pos] = leaf_upd_bit_val;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_bid       <= '0;
            l1_ask       <= '0;
            l0_bid       <= '0;
            l0_ask       <= '0;
            init_cnt     <= '0;
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= '0;
                initializing <= 1'b1;
                init_done    <= 1'b0;
                l1_bid       <= '0;
                l1_ask       <= '0;
                l0_bid       <= '0;
                l0_ask       <= '0;
            end else if (initializing) begin
                leaf_mem_bid[init_cnt[7:0]] <= 32'd0;
                leaf_mem_ask[init_cnt[7:0]] <= 32'd0;
                if (init_cnt == OCC_LEAF_WORDS - 1) begin
                    initializing <= 1'b0;
                    init_done    <= 1'b1;
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end else if (leaf_upd_en) begin
                if (leaf_upd_side == 1'b0) begin
                    leaf_mem_bid[upd_word_addr] <= upd_new_word_bid;
                    // Update L1
                    l1_bid[upd_word_addr] <= (upd_new_word_bid != 32'd0);
                    // Update L0
                    // Check if group has any other active words
                    for (int g = 0; g < 8; g++) begin
                        logic [31:0] grp_l1;
                        grp_l1 = l1_bid[g*32 +: 32];
                        if (g == upd_grp_idx) begin
                            grp_l1[leaf_upd_pidx[9:5]] = (upd_new_word_bid != 32'd0);
                        end
                        l0_bid[g] <= (grp_l1 != 32'd0);
                    end
                end else begin
                    leaf_mem_ask[upd_word_addr] <= upd_new_word_ask;
                    // Update L1
                    l1_ask[upd_word_addr] <= (upd_new_word_ask != 32'd0);
                    // Update L0
                    for (int g = 0; g < 8; g++) begin
                        logic [31:0] grp_l1;
                        grp_l1 = l1_ask[g*32 +: 32];
                        if (g == upd_grp_idx) begin
                            grp_l1[leaf_upd_pidx[9:5]] = (upd_new_word_ask != 32'd0);
                        end
                        l0_ask[g] <= (grp_l1 != 32'd0);
                    end
                end
            end
        end
    end

endmodule
