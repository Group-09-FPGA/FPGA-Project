// =============================================================================
// File: tb_lob_price_ram.sv
// Description: Unit testbench for price-level aggregate quantity RAM
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_price_ram;

    logic        clk;
    logic        rst_n;
    logic        init_start;
    logic        init_busy;
    logic        init_done;

    logic        wr_en;
    logic [13:0] wr_addr;
    logic [31:0] wr_data;

    logic        rd_en;
    logic [13:0] rd_addr;
    logic        rd_valid;
    logic [31:0] rd_data;

    lob_price_ram dut (
        .clk(clk),
        .rst_n(rst_n),
        .init_start(init_start),
        .init_busy(init_busy),
        .init_done(init_done),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_valid(rd_valid),
        .rd_data(rd_data)
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
        wr_en = 0;
        wr_addr = 0;
        wr_data = 0;
        rd_en = 0;
        rd_addr = 0;

        $display("=== Starting tb_lob_price_ram ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Fast test without full 16K init (or with init)
        // Let's test write and 3-cycle read latency directly
        wr_en = 1;
        wr_addr = 14'd105;
        wr_data = 32'd75000;
        @(posedge clk);
        #1;
        wr_en = 0;

        // Issue read in cycle t
        rd_en = 1;
        rd_addr = 14'd105;
        @(posedge clk);
        #1;
        rd_en = 0;
        check("Read cycle t+1: rd_valid is 0", rd_valid == 0);

        @(posedge clk);
        #1;
        check("Read cycle t+2: rd_valid is 0", rd_valid == 0);

        @(posedge clk);
        #1;
        check("Read cycle t+3: rd_valid is 1 and rd_data matches", rd_valid == 1 && rd_data == 32'd75000);

        @(posedge clk);
        #1;
        check("Read cycle t+4: rd_valid is 0", rd_valid == 0);

        $display("tb_lob_price_ram: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
