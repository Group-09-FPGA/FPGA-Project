// =============================================================================
// File: tb_lob_core.sv
// Description: End-to-end integration testbench for LOB accelerator core
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_core;

    logic         clk;
    logic         rst_n;

    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;

    logic         cfg_clear;
    logic [31:0]  cfg_price_base;
    logic [31:0]  cfg_tick;

    logic         book_valid;
    logic         init_done;
    logic         busy;
    logic         error_valid;
    logic [7:0]   error_code;
    logic [11:0]  active_order_count;
    logic         event_done;

    logic         best_bid_valid;
    logic [31:0]  best_bid_price;
    logic [31:0]  best_bid_qty;

    logic         best_ask_valid;
    logic [31:0]  best_ask_price;
    logic [31:0]  best_ask_qty;

    lob_core #(
        .DEFAULT_PRICE_BASE(32'd1000000), // $100.0000
        .DEFAULT_TICK(32'd10000)          // $1.0000 tick
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(event_valid),
        .event_ready(event_ready),
        .event_data(event_data),
        .cfg_clear(cfg_clear),
        .cfg_price_base(cfg_price_base),
        .cfg_tick(cfg_tick),
        .book_valid(book_valid),
        .init_done(init_done),
        .busy(busy),
        .error_valid(error_valid),
        .error_code(error_code),
        .active_order_count(active_order_count),
        .event_done(event_done),
        .best_bid_valid(best_bid_valid),
        .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty),
        .best_ask_valid(best_ask_valid),
        .best_ask_price(best_ask_price),
        .best_ask_qty(best_ask_qty)
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
            $display("[FAIL] %s (err_valid=%b, err_code=0x%02h, bid_v=%b, bid_q=%0d, ask_v=%b, ask_q=%0d)",
                     test_name, error_valid, error_code, best_bid_valid, best_bid_qty, best_ask_valid, best_ask_qty);
        end
    endtask

    // Helper task to send an event synchronously and wait for event_done
    task send_event(input canonical_event_t evt);
        wait(event_ready == 1);
        @(posedge clk);
        #1;
        event_valid = 1'b1;
        event_data  = evt;
        @(posedge clk);
        #1;
        event_valid = 1'b0;
        event_data  = '0;
        wait(event_done == 1 || error_valid == 1);
        @(posedge clk);
        #1;
    endtask

    canonical_event_t evt;

    initial begin
        clk = 0;
        rst_n = 0;
        event_valid = 0;
        event_data = '0;
        cfg_clear = 0;
        cfg_price_base = 32'd1000000;
        cfg_tick = 32'd10000;

        $display("=== Starting tb_lob_core Integration Verification ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Wait for hardware initialization (16,384 cycles)
        wait(init_done == 1);
        @(posedge clk);
        #1;
        check("Initialization finished: book_valid=1, event_ready=1, active_orders=0",
              book_valid == 1 && event_ready == 1 && active_order_count == 0);

        // Test 2: ADD Order 101 (BUY, pidx 10, 50 shares)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_ADD;
        evt.side = SIDE_BID;
        evt.oid = 64'd101;
        evt.shares = 32'd50;
        evt.pidx = 13'd10;
        send_event(evt);
        check("ADD 101: best_bid_valid=1, pidx=10, qty=50, active_orders=1",
              best_bid_valid == 1 && best_bid_qty == 50 && active_order_count == 1);

        // Test 3: ADD Order 102 (BUY, pidx 9, 30 shares)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_ADD;
        evt.side = SIDE_BID;
        evt.oid = 64'd102;
        evt.shares = 32'd30;
        evt.pidx = 13'd9;
        send_event(evt);
        check("ADD 102 (lower bid): best_bid remains pidx=10, qty=50, active_orders=2",
              best_bid_valid == 1 && best_bid_qty == 50 && active_order_count == 2);

        // Test 4: ADD Order 201 (SELL, pidx 13, 20 shares)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_ADD;
        evt.side = SIDE_ASK;
        evt.oid = 64'd201;
        evt.shares = 32'd20;
        evt.pidx = 13'd13;
        send_event(evt);
        check("ADD 201: best_ask_valid=1, qty=20, active_orders=3",
              best_ask_valid == 1 && best_ask_qty == 20 && active_order_count == 3);

        // Test 5: ADD Order 202 (SELL, pidx 12, 15 shares - better ask)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_ADD;
        evt.side = SIDE_ASK;
        evt.oid = 64'd202;
        evt.shares = 32'd15;
        evt.pidx = 13'd12;
        send_event(evt);
        check("ADD 202 (better ask): best_ask becomes pidx=12, qty=15, active_orders=4",
              best_ask_valid == 1 && best_ask_qty == 15 && active_order_count == 4);

        // Test 6: Partial EXECUTE on Order 101 (20 shares)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_EXECUTE;
        evt.oid = 64'd101;
        evt.shares = 32'd20;
        send_event(evt);
        check("Partial EXEC 101 (20 sh): best_bid_qty=30, active_orders=4",
              best_bid_valid == 1 && best_bid_qty == 30 && active_order_count == 4);

        // Test 7: Full EXECUTE on Order 101 (remaining 30 shares) -> Level 10 emptied!
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_EXECUTE;
        evt.oid = 64'd101;
        evt.shares = 32'd30;
        send_event(evt);
        check("Full EXEC 101: order killed, level 10 emptied, search updates best_bid to pidx=9, qty=30",
              best_bid_valid == 1 && best_bid_qty == 30 && active_order_count == 3);

        // Test 8: Partial CANCEL on Order 102 (10 shares)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_CANCEL;
        evt.oid = 64'd102;
        evt.shares = 32'd10;
        send_event(evt);
        check("Partial CANCEL 102: best_bid_qty=20, active_orders=3",
              best_bid_valid == 1 && best_bid_qty == 20 && active_order_count == 3);

        // Test 9: DELETE on Order 202 (entire remaining 15 shares) -> Level 12 emptied!
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_DELETE;
        evt.oid = 64'd202;
        evt.shares = 32'd0;
        send_event(evt);
        check("DELETE 202: level 12 emptied, search updates best_ask to pidx=13, qty=20",
              best_ask_valid == 1 && best_ask_qty == 20 && active_order_count == 2);

        // Test 10: REPLACE Order 201 with Order 203 (new pidx 11, new shares 40)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_REPLACE;
        evt.oid = 64'd201;
        evt.noid = 64'd203;
        evt.shares = 32'd40;
        evt.pidx = 13'd11;
        send_event(evt);
        check("REPLACE 201->203: best_ask becomes pidx=11, qty=40, active_orders=2",
              best_ask_valid == 1 && best_ask_qty == 40 && active_order_count == 2);

        // Test 11: Fail-Stop on Duplicate OID (add existing 203)
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_ADD;
        evt.side = SIDE_ASK;
        evt.oid = 64'd203;
        evt.shares = 32'd10;
        evt.pidx = 13'd14;
        send_event(evt);
        check("Duplicate OID triggers fail-stop: error_valid=1, code=FAIL_DUP_OID, book_valid=0",
              error_valid == 1 && error_code == FAIL_DUP_OID && book_valid == 0);

        // Test 12: Recovery via cfg_clear
        cfg_clear = 1;
        @(posedge clk);
        #1;
        cfg_clear = 0;
        wait(init_done == 0);
        wait(init_done == 1);
        @(posedge clk);
        #1;
        check($sformatf("cfg_clear: book_valid=%b, active_orders=%0d, err_valid=%b, err_code=0x%02h, init_done=%b",
                        book_valid, active_order_count, error_valid, error_code, init_done),
              book_valid == 1 && active_order_count == 0 && error_valid == 0);

        // Test 13: Missing OID error detection
        evt = '0;
        evt.ver = 4'h1;
        evt.op = OP_EXECUTE;
        evt.oid = 64'd99999;
        evt.shares = 32'd10;
        send_event(evt);
        check("Missing OID triggers fail-stop: error_valid=1, code=FAIL_MISSING_OID, book_valid=0",
              error_valid == 1 && error_code == FAIL_MISSING_OID && book_valid == 0);

        $display("tb_lob_core: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
