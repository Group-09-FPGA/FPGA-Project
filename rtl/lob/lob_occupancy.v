// 3-level hierarchical occupancy bitmask trees and priority encoders

`timescale 1ns / 1ps

`include "lob_defines.vh"

module lob_occupancy #(
    parameter PRICE_LEVELS_PER_SIDE = `PRICE_LEVELS_PER_SIDE, // 8,192
    parameter OCC_LEAF_WORDS         = `OCC_LEAF_WORDS          // 256
) (
    input  wire        clk,
    input  wire        rst_n,

    // Hardware Initialization
    input  wire        init_start,
    output wire        init_busy,
    output reg         init_done,

    // Prefetch / Normal Leaf Word Read Port (Latency = 1 cycle)
    input  wire        leaf_rd_en,
    input  wire        leaf_rd_side,       // 0=Bid, 1=Ask
    input  wire [7:0]  leaf_rd_word_idx,   // pidx[12:5]
    output wire [31:0] leaf_rd_data,

    // Leaf Update Commit Port
    input  wire        leaf_upd_en,
    input  wire        leaf_upd_side,      // 0=Bid, 1=Ask
    input  wire [12:0] leaf_upd_pidx,      // pidx
    input  wire        leaf_upd_bit_val,   // 1=Add (level non-zero), 0=Remove (level zero)

    // Search Engine Request / Result
    input  wire        search_start,
    input  wire        search_side,        // 0=Bid (highest pidx), 1=Ask (lowest pidx)
    output wire        search_busy,
    output reg         search_done,
    output reg         search_valid,       // 1 if side is non-empty
    output reg  [12:0] search_pidx,

    // Live occupancy status flags
    output wire        bid_has_orders,
    output wire        ask_has_orders
);

    // Leaf Memories (256 words x 32 bits per side)
    (* ram_style = "distributed" *)
    reg [31:0] leaf_mem_bid [0:OCC_LEAF_WORDS-1];

    (* ram_style = "distributed" *)
    reg [31:0] leaf_mem_ask [0:OCC_LEAF_WORDS-1];

    // L1 Register Masks (256 bits per side)
    reg [255:0] l1_bid;
    reg [255:0] l1_ask;

    // L0 Register Masks (8 bits per side)
    reg [7:0]   l0_bid;
    reg [7:0]   l0_ask;

    assign bid_has_orders = (l0_bid != 8'd0);
    assign ask_has_orders = (l0_ask != 8'd0);

    // Initialization counter (256 cycles)
    reg [8:0] init_cnt;
    reg       initializing;

    assign init_busy = initializing;

    // Priority Encoder Functions
    function [2:0] prio_enc_high_8;
        input [7:0] in;
        integer i;
        begin
            prio_enc_high_8 = 3'd0;
            for (i = 0; i < 8; i = i + 1) begin
                if (in[i]) prio_enc_high_8 = i[2:0];
            end
        end
    endfunction

    function [4:0] prio_enc_high_32;
        input [31:0] in;
        integer i;
        begin
            prio_enc_high_32 = 5'd0;
            for (i = 0; i < 32; i = i + 1) begin
                if (in[i]) prio_enc_high_32 = i[4:0];
            end
        end
    endfunction

    function [2:0] prio_enc_low_8;
        input [7:0] in;
        integer i;
        begin
            prio_enc_low_8 = 3'd0;
            for (i = 7; i >= 0; i = i - 1) begin
                if (in[i]) prio_enc_low_8 = i[2:0];
            end
        end
    endfunction

    function [4:0] prio_enc_low_32;
        input [31:0] in;
        integer i;
        begin
            prio_enc_low_32 = 5'd0;
            for (i = 31; i >= 0; i = i - 1) begin
                if (in[i]) prio_enc_low_32 = i[4:0];
            end
        end
    endfunction

    // Search FSM (S0..S4: 4-stage pipelined search)
    localparam [2:0] SRCH_IDLE = 3'd0,
                     SRCH_S0   = 3'd1,
                     SRCH_S1   = 3'd2,
                     SRCH_S2   = 3'd3,
                     SRCH_S3   = 3'd4,
                     SRCH_S4   = 3'd5;

    reg [2:0]  srch_state;
    reg        srch_side_reg;
    reg [2:0]  srch_g;
    reg [4:0]  srch_j;
    reg [4:0]  srch_m;
    reg        srch_empty;

    assign search_busy = (srch_state != SRCH_IDLE);

    // Read arbitration for Leaf RAMs (Search vs Normal prefetch)
    reg       eff_leaf_rd_en;
    reg       eff_leaf_rd_side;
    reg [7:0] eff_leaf_rd_addr;

    always @* begin
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
    reg [31:0] leaf_rd_data_reg;

    always @(posedge clk) begin
        if (eff_leaf_rd_en) begin
            if (eff_leaf_rd_side == 1'b0) begin
                leaf_rd_data_reg <= leaf_mem_bid[eff_leaf_rd_addr];
            end else begin
                leaf_rd_data_reg <= leaf_mem_ask[eff_leaf_rd_addr];
            end
        end
    end

    assign leaf_rd_data = leaf_rd_data_reg;
    wire [31:0] srch_leaf_data = leaf_rd_data_reg;

    // Search state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            srch_state    <= SRCH_IDLE;
            srch_side_reg <= 1'b0;
            srch_g        <= 3'd0;
            srch_j        <= 5'd0;
            srch_m        <= 5'd0;
            srch_empty    <= 1'b0;
            search_done   <= 1'b0;
            search_valid  <= 1'b0;
            search_pidx   <= 13'd0;
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
                            search_pidx  <= 13'd0;
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
                            search_pidx  <= 13'd0;
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

    // Memory Write & Hierarchy Updates (Leaf, L1, L0)
    wire [7:0]  upd_word_addr = leaf_upd_pidx[12:5];
    wire [4:0]  upd_bit_pos   = leaf_upd_pidx[4:0];
    wire [2:0]  upd_grp_idx   = leaf_upd_pidx[12:10];
    reg  [31:0] upd_new_word_bid;
    reg  [31:0] upd_new_word_ask;

    // Compute updated word from current leaf read / memory
    always @* begin
        upd_new_word_bid = leaf_mem_bid[upd_word_addr];
        upd_new_word_ask = leaf_mem_ask[upd_word_addr];
        if (leaf_upd_side == 1'b0) begin
            upd_new_word_bid[upd_bit_pos] = leaf_upd_bit_val;
        end else begin
            upd_new_word_ask[upd_bit_pos] = leaf_upd_bit_val;
        end
    end

    // Leaf memory synchronous writes (no asynchronous reset)
    always @(posedge clk) begin
        if (initializing) begin
            leaf_mem_bid[init_cnt[7:0]] <= 32'd0;
            leaf_mem_ask[init_cnt[7:0]] <= 32'd0;
        end else if (leaf_upd_en) begin
            if (leaf_upd_side == 1'b0) begin
                leaf_mem_bid[upd_word_addr] <= upd_new_word_bid;
            end else begin
                leaf_mem_ask[upd_word_addr] <= upd_new_word_ask;
            end
        end
    end

    // Hierarchy masks (L1, L0) and initialization FSM
    integer g_bid;
    integer g_ask;
    reg [31:0] grp_l1_bid;
    reg [31:0] grp_l1_ask;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_bid       <= 256'd0;
            l1_ask       <= 256'd0;
            l0_bid       <= 8'd0;
            l0_ask       <= 8'd0;
            init_cnt     <= 9'd0;
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= 9'd0;
                initializing <= 1'b1;
                init_done    <= 1'b0;
                l1_bid       <= 256'd0;
                l1_ask       <= 256'd0;
                l0_bid       <= 8'd0;
                l0_ask       <= 8'd0;
            end else if (initializing) begin
                if (init_cnt == OCC_LEAF_WORDS - 1) begin
                    initializing <= 1'b0;
                    init_done    <= 1'b1;
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end else if (leaf_upd_en) begin
                if (leaf_upd_side == 1'b0) begin
                    // Update L1
                    l1_bid[upd_word_addr] <= (upd_new_word_bid != 32'd0);
                    // Update L0
                    // Check if group has any other active words
                    for (g_bid = 0; g_bid < 8; g_bid = g_bid + 1) begin
                        grp_l1_bid = l1_bid[g_bid*32 +: 32];
                        if (g_bid == upd_grp_idx) begin
                            grp_l1_bid[leaf_upd_pidx[9:5]] = (upd_new_word_bid != 32'd0);
                        end
                        l0_bid[g_bid] <= (grp_l1_bid != 32'd0);
                    end
                end else begin
                    // Update L1
                    l1_ask[upd_word_addr] <= (upd_new_word_ask != 32'd0);
                    // Update L0
                    for (g_ask = 0; g_ask < 8; g_ask = g_ask + 1) begin
                        grp_l1_ask = l1_ask[g_ask*32 +: 32];
                        if (g_ask == upd_grp_idx) begin
                            grp_l1_ask[leaf_upd_pidx[9:5]] = (upd_new_word_ask != 32'd0);
                        end
                        l0_ask[g_ask] <= (grp_l1_ask != 32'd0);
                    end
                end
            end
        end
    end

endmodule
