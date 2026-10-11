// =============================================================================
// File: tb_lob_golden.sv
// Description: Automated golden reference verification testbench for LOB core
//              Ingests vectors from intelligent-planck golden Python model
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §13, §18
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_golden;

    logic         clk;
    logic         rst_n;

    logic         event_valid;
    logic         event_ready;
    logic [255:0] event_data;

    logic         cfg_clear;
    logic         cfg_fail_stop_en;
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
        .DEFAULT_PRICE_BASE(32'd900000), // $90.0000 baseline matching golden adapter
        .DEFAULT_TICK(32'd1000),         // $0.1000 tick size
        .DEFAULT_FAIL_STOP_EN(1'b0)      // Allow verification test suite to continue on rejected events
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(event_valid),
        .event_ready(event_ready),
        .event_data(event_data),
        .cfg_clear(cfg_clear),
        .cfg_fail_stop_en(cfg_fail_stop_en),
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

    int total_vectors = 0;
    int pass_vectors  = 0;
    int fail_vectors  = 0;

    int file_fd;
    string file_path;

    logic [255:0] raw_hex;
    int           exp_success;
    int           exp_active;
    int           exp_bid_p;
    int           exp_bid_q;
    int           exp_ask_p;
    int           exp_ask_q;

    logic         act_success;
    int           act_active;
    int           act_bid_p;
    int           act_bid_q;
    int           act_ask_p;
    int           act_ask_q;

    initial begin
        clk              = 0;
        rst_n            = 0;
        event_valid      = 0;
        event_data       = '0;
        cfg_clear        = 0;
        cfg_fail_stop_en = 0; // Verification mode: reject invalid events without halting core
        cfg_price_base   = 32'd900000;
        cfg_tick         = 32'd1000;

        $display("================================================================================");
        $display("=== STARTING LOB ACCELERATOR GOLDEN REFERENCE VECTOR VERIFICATION            ===");
        $display("================================================================================");

        #20 rst_n = 1;
        #10;

        // Wait for hardware initialization (16,384 cycles for Price RAM + BRAM clears)
        $display("[INFO] Waiting for hardware initialization...");
        wait(init_done == 1'b1);
        @(posedge clk);
        #1;
        $display("[INFO] Initialization completed. book_valid=%0b, event_ready=%0b", book_valid, event_ready);

        // Try candidate file paths for golden_vectors.txt
        file_path = "../golden/golden_vectors.txt";
        file_fd = $fopen(file_path, "r");
        if (file_fd == 0) begin
            file_path = "sim/golden/golden_vectors.txt";
            file_fd = $fopen(file_path, "r");
        end
        if (file_fd == 0) begin
            file_path = "/home/ronit/acad/current/hardware/fpga-lob/sim/golden/golden_vectors.txt";
            file_fd = $fopen(file_path, "r");
        end

        if (file_fd == 0) begin
            $display("[FATAL] Could not open golden_vectors.txt from any candidate path!");
            $finish;
        end

        $display("[INFO] Opened golden vectors from '%s'", file_path);

        while ($fscanf(file_fd, "%64h %d %d %d %d %d %d\n",
                       raw_hex, exp_success, exp_active, exp_bid_p, exp_bid_q, exp_ask_p, exp_ask_q) == 7) begin
            total_vectors++;

            // Wait until ready
            wait(event_ready == 1'b1);
            @(posedge clk);
            #1;
            event_valid = 1'b1;
            event_data  = raw_hex;
            @(posedge clk);
            #1;
            event_valid = 1'b0;
            event_data  = '0;

            // Wait for completion or rejection
            wait(event_done == 1'b1 || error_valid == 1'b1);
            #1; // Sample immediately after edge

            act_success = !error_valid;
            act_active  = int'(active_order_count);
            act_bid_p   = best_bid_valid ? int'(best_bid_price) : 0;
            act_bid_q   = best_bid_valid ? int'(best_bid_qty)   : 0;
            act_ask_p   = best_ask_valid ? int'(best_ask_price) : 0;
            act_ask_q   = best_ask_valid ? int'(best_ask_qty)   : 0;

            if ((act_success == (exp_success != 0)) &&
                (act_active  == exp_active) &&
                (act_bid_p   == exp_bid_p) &&
                (act_bid_q   == exp_bid_q) &&
                (act_ask_p   == exp_ask_p) &&
                (act_ask_q   == exp_ask_q)) begin
                pass_vectors++;
                $display("[PASS] Step %02d | Success=%0d Active=%0d | Bid=%0d x %0d | Ask=%0d x %0d",
                         total_vectors, act_success, act_active, act_bid_p, act_bid_q, act_ask_p, act_ask_q);
            end else begin
                fail_vectors++;
                $display("[FAIL] Step %02d MISMATCH!", total_vectors);
                $display("       EXP: Success=%0d Active=%0d | Bid=%0d x %0d | Ask=%0d x %0d",
                         exp_success, exp_active, exp_bid_p, exp_bid_q, exp_ask_p, exp_ask_q);
                $display("       ACT: Success=%0d Active=%0d | Bid=%0d x %0d | Ask=%0d x %0d (err_code=0x%02h)",
                         act_success, act_active, act_bid_p, act_bid_q, act_ask_p, act_ask_q, error_code);
            end

            @(posedge clk);
            #1;
        end

        $fclose(file_fd);

        $display("================================================================================");
        $display("=== GOLDEN VECTOR VERIFICATION SUMMARY                                       ===");
        $display("=== Total Vectors Processed: %0d", total_vectors);
        $display("=== Passed Vectors:          %0d", pass_vectors);
        $display("=== Failed Vectors:          %0d", fail_vectors);
        $display("================================================================================");

        if (fail_vectors == 0 && total_vectors == 32) begin
            $display(">>> ALL 32 GOLDEN REFERENCE VECTORS MATCH HARDWARE EXECUTION EXACTLY! <<<");
        end else begin
            $display(">>> VERIFICATION FAILED WITH %0d MISMATCHES! <<<", fail_vectors);
        end

        $finish;
    end

endmodule
