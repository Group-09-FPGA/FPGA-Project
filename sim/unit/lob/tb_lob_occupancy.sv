// =============================================================================
// File: tb_lob_occupancy.sv
// Description: Unit testbench for 3-level occupancy hierarchy and priority encoder search
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_occupancy;

    logic        clk;
    logic        rst_n;
    logic        init_start;
    logic        init_busy;
    logic        init_done;

    logic        leaf_rd_en;
    logic        leaf_rd_side;
    logic [7:0]  leaf_rd_word_idx;
    logic [31:0] leaf_rd_data;

    logic        leaf_upd_en;
    logic        leaf_upd_side;
    logic [12:0] leaf_upd_pidx;
    logic        leaf_upd_bit_val;

    logic        search_start;
    logic        search_side;
    logic        search_busy;
    logic        search_done;
    logic        search_valid;
    logic [12:0] search_pidx;

    logic        bid_has_orders;
    logic        ask_has_orders;

    lob_occupancy dut (
        .clk(clk),
        .rst_n(rst_n),
        .init_start(init_start),
        .init_busy(init_busy),
        .init_done(init_done),
        .leaf_rd_en(leaf_rd_en),
        .leaf_rd_side(leaf_rd_side),
        .leaf_rd_word_idx(leaf_rd_word_idx),
        .leaf_rd_data(leaf_rd_data),
        .leaf_upd_en(leaf_upd_en),
        .leaf_upd_side(leaf_upd_side),
        .leaf_upd_pidx(leaf_upd_pidx),
        .leaf_upd_bit_val(leaf_upd_bit_val),
        .search_start(search_start),
        .search_side(search_side),
        .search_busy(search_busy),
        .search_done(search_done),
        .search_valid(search_valid),
        .search_pidx(search_pidx),
        .bid_has_orders(bid_has_orders),
        .ask_has_orders(ask_has_orders)
    );

    always #5 clk = ~clk;

    int test_count = 0;
    int pass_count = 0;

    task check(input string test_name, input logic cond);
        test_count++;
        if (cond) begin
            pass_count++;
            $display("[PASS] %s", test_name);
        end else begin
            $display("[FAIL] %s", test_name);
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        init_start = 0;
        leaf_rd_en = 0;
        leaf_rd_side = 0;
        leaf_rd_word_idx = 0;
        leaf_upd_en = 0;
        leaf_upd_side = 0;
        leaf_upd_pidx = 0;
        leaf_upd_bit_val = 0;
        search_start = 0;
        search_side = 0;

        $display("=== Starting tb_lob_occupancy ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Initialize (256 cycles)
        init_start = 1;
        @(posedge clk);
        #1;
        init_start = 0;
        wait(init_done == 1);
        @(posedge clk);
        #1;
        check("Occupancy initialized (empty book: bid_has_orders=0, ask_has_orders=0)",
              bid_has_orders == 0 && ask_has_orders == 0);

        // Test 2: Search empty book returns valid=0
        search_start = 1;
        search_side = 1'b0; // BID
        @(posedge clk);
        #1;
        search_start = 0;
        wait(search_done == 1);
        @(posedge clk);
        #1;
        check("Search empty Bid side gives search_valid=0", search_valid == 0);

        // Test 3: Add Bid at level 500 and level 750
        leaf_upd_en = 1;
        leaf_upd_side = 1'b0; // Bid
        leaf_upd_pidx = 13'd500;
        leaf_upd_bit_val = 1'b1;
        @(posedge clk);
        #1;

        leaf_upd_pidx = 13'd750;
        @(posedge clk);
        #1;
        leaf_upd_en = 0;

        check("Bid side now has orders", bid_has_orders == 1);

        // Test 4: Search Bid side finds maximum level 750
        search_start = 1;
        search_side = 1'b0;
        @(posedge clk);
        #1;
        search_start = 0;
        wait(search_done == 1);
        check("Search Bid finds highest pidx 750", search_valid == 1 && search_pidx == 13'd750);

        // Test 5: Add Ask at level 1000 and level 1200
        leaf_upd_en = 1;
        leaf_upd_side = 1'b1; // Ask
        leaf_upd_pidx = 13'd1200;
        leaf_upd_bit_val = 1'b1;
        @(posedge clk);
        #1;
        leaf_upd_pidx = 13'd1000;
        @(posedge clk);
        #1;
        leaf_upd_en = 0;

        // Search Ask side finds minimum level 1000
        search_start = 1;
        search_side = 1'b1;
        @(posedge clk);
        #1;
        search_start = 0;
        wait(search_done == 1);
        check("Search Ask finds lowest pidx 1000", search_valid == 1 && search_pidx == 13'd1000);

        // Test 6: Remove level 750 on Bid side
        leaf_upd_en = 1;
        leaf_upd_side = 1'b0;
        leaf_upd_pidx = 13'd750;
        leaf_upd_bit_val = 1'b0;
        @(posedge clk);
        #1;
        leaf_upd_en = 0;

        // Search Bid side now finds new highest: level 500
        search_start = 1;
        search_side = 1'b0;
        @(posedge clk);
        #1;
        search_start = 0;
        wait(search_done == 1);
        check("After removing level 750, Search Bid finds level 500", search_valid == 1 && search_pidx == 13'd500);

        $display("tb_lob_occupancy: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
