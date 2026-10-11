// =============================================================================
// File: tb_lob_slot_table.sv
// Description: Unit testbench for active order slot storage
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_slot_table;

    logic        clk;
    logic        rst_n;
    logic        init_start;
    logic        init_busy;
    logic        init_done;

    logic        wr_en;
    logic [10:0] wr_addr;
    slot_entry_t wr_data;

    logic        rd_en;
    logic [10:0] rd_addr;
    slot_entry_t rd_data;

    lob_slot_table dut (
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
        .rd_data(rd_data)
    );

    always #5 clk = ~clk; // 100 MHz clock

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
        wr_data = '0;
        rd_en = 0;
        rd_addr = 0;

        $display("=== Starting tb_lob_slot_table ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Initialization sequence
        init_start = 1;
        #10 init_start = 0;
        check("init_busy asserted during initialization", init_busy == 1);

        wait(init_done == 1);
        #10;
        check("init_done asserted after 2048 cycles", init_done == 1 && init_busy == 0);

        // Test 2: Check that slot 0 was cleared
        rd_en = 1;
        rd_addr = 11'd0;
        #10;
        check("Slot 0 valid bit is 0 after init", rd_data.valid == 1'b0);

        // Test 3: Write slot 42 and read back (1 cycle latency)
        wr_en = 1;
        wr_addr = 11'd42;
        wr_data = '{valid: 1'b1, side: 1'b1, pidx: 13'd500, shares: 32'd1000};
        #10;
        wr_en = 0;

        rd_en = 1;
        rd_addr = 11'd42;
        #10;
        rd_en = 0;
        check("Read back written slot 42 (valid=1, side=1, pidx=500, shares=1000)",
              rd_data.valid == 1'b1 && rd_data.side == 1'b1 &&
              rd_data.pidx == 13'd500 && rd_data.shares == 32'd1000);

        // Test 4: Write forwarding on same cycle read
        wr_en = 1;
        wr_addr = 11'd100;
        wr_data = '{valid: 1'b1, side: 1'b0, pidx: 13'd250, shares: 32'd75};
        rd_en = 1;
        rd_addr = 11'd100;
        #10;
        wr_en = 0;
        rd_en = 0;
        check("Write forwarding on concurrent read/write to slot 100",
              rd_data.valid == 1'b1 && rd_data.shares == 32'd75 && rd_data.pidx == 13'd250);

        $display("tb_lob_slot_table: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
