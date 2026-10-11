// =============================================================================
// File: tb_lob_bbo.sv
// Description: Unit testbench for BBO tracking and price calculation
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_bbo;

    logic        clk;
    logic        rst_n;
    logic [31:0] cfg_price_base;
    logic [31:0] cfg_tick;

    logic        bbo_direct_upd_en;
    logic        bbo_direct_side;
    logic [12:0] bbo_direct_pidx;
    logic [31:0] bbo_direct_qty;

    logic        bbo_search_upd_en;
    logic        bbo_search_side;
    logic        bbo_search_valid;
    logic [12:0] bbo_search_pidx;
    logic [31:0] bbo_search_qty;

    logic        clear_en;

    logic        best_bid_valid;
    logic [12:0] best_bid_pidx;
    logic [31:0] best_bid_price;
    logic [31:0] best_bid_qty;

    logic        best_ask_valid;
    logic [12:0] best_ask_pidx;
    logic [31:0] best_ask_price;
    logic [31:0] best_ask_qty;

    logic        check_side;
    logic [12:0] check_pidx;
    logic        triggers_search;

    lob_bbo dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_price_base(cfg_price_base),
        .cfg_tick(cfg_tick),
        .bbo_direct_upd_en(bbo_direct_upd_en),
        .bbo_direct_side(bbo_direct_side),
        .bbo_direct_pidx(bbo_direct_pidx),
        .bbo_direct_qty(bbo_direct_qty),
        .bbo_search_upd_en(bbo_search_upd_en),
        .bbo_search_side(bbo_search_side),
        .bbo_search_valid(bbo_search_valid),
        .bbo_search_pidx(bbo_search_pidx),
        .bbo_search_qty(bbo_search_qty),
        .clear_en(clear_en),
        .best_bid_valid(best_bid_valid),
        .best_bid_pidx(best_bid_pidx),
        .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty),
        .best_ask_valid(best_ask_valid),
        .best_ask_pidx(best_ask_pidx),
        .best_ask_price(best_ask_price),
        .best_ask_qty(best_ask_qty),
        .check_side(check_side),
        .check_pidx(check_pidx),
        .triggers_search(triggers_search)
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
        cfg_price_base = 32'd100000; // $10.0000
        cfg_tick = 32'd100;          // $0.0100 (1 cent tick)
        bbo_direct_upd_en = 0;
        bbo_direct_side = 0;
        bbo_direct_pidx = 0;
        bbo_direct_qty = 0;
        bbo_search_upd_en = 0;
        bbo_search_side = 0;
        bbo_search_valid = 0;
        bbo_search_pidx = 0;
        bbo_search_qty = 0;
        clear_en = 0;
        check_side = 0;
        check_pidx = 0;

        $display("=== Starting tb_lob_bbo ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Empty book initially
        check("Initial best bid and ask are invalid", !best_bid_valid && !best_ask_valid);

        // Test 2: Direct ADD Bid at pidx 10 (Price = 100000 + 10*100 = 101000, Qty = 500)
        bbo_direct_upd_en = 1;
        bbo_direct_side = 1'b0; // BID
        bbo_direct_pidx = 13'd10;
        bbo_direct_qty = 32'd500;
        @(posedge clk);
        #1;
        bbo_direct_upd_en = 0;
        check("Best Bid updated: valid=1, pidx=10, price=101000, qty=500",
              best_bid_valid == 1 && best_bid_pidx == 13'd10 &&
              best_bid_price == 32'd101000 && best_bid_qty == 32'd500);

        // Test 3: Direct ADD higher Bid at pidx 15 (Price = 101500, Qty = 200)
        bbo_direct_upd_en = 1;
        bbo_direct_side = 1'b0;
        bbo_direct_pidx = 13'd15;
        bbo_direct_qty = 32'd200;
        @(posedge clk);
        #1;
        bbo_direct_upd_en = 0;
        check("Higher Bid replaces best: pidx=15, price=101500, qty=200",
              best_bid_valid == 1 && best_bid_pidx == 13'd15 &&
              best_bid_price == 32'd101500 && best_bid_qty == 32'd200);

        // Test 4: Removing level 15 triggers search
        check_side = 1'b0;
        check_pidx = 13'd15;
        #1;
        check("Removing current best bid pidx 15 asserts triggers_search", triggers_search == 1);

        // Removing non-best level 10 does not trigger search
        check_pidx = 13'd10;
        #1;
        check("Removing non-best bid pidx 10 does not trigger search", triggers_search == 0);

        // Test 5: Search update falls back to level 10 with qty 500
        bbo_search_upd_en = 1;
        bbo_search_side = 1'b0;
        bbo_search_valid = 1'b1;
        bbo_search_pidx = 13'd10;
        bbo_search_qty = 32'd500;
        @(posedge clk);
        #1;
        bbo_search_upd_en = 0;
        check("Search update restores Best Bid to pidx 10, price 101000",
              best_bid_valid == 1 && best_bid_pidx == 13'd10 && best_bid_price == 32'd101000);

        $display("tb_lob_bbo: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
