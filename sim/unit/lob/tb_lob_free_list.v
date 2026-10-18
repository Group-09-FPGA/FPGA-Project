// =============================================================================
// File: tb_lob_free_list.v
// Description: Unit testbench for LIFO free list allocator (Verilog-2001)
// =============================================================================

`timescale 1ns / 1ps

`include "lob_defines.vh"

module tb_lob_free_list;

    reg         clk;
    reg         rst_n;
    reg         init_start;
    wire        init_busy;
    wire        init_done;

    reg         rd_top_en;
    wire [10:0] top_slot;
    wire        top_valid;
    reg         pop_commit;

    reg         push_en;
    reg  [10:0] push_slot;

    wire        empty;
    wire        full;
    wire [11:0] free_count;
    wire [11:0] active_count;

    lob_free_list dut (
        .clk(clk),
        .rst_n(rst_n),
        .init_start(init_start),
        .init_busy(init_busy),
        .init_done(init_done),
        .rd_top_en(rd_top_en),
        .top_slot(top_slot),
        .top_valid(top_valid),
        .pop_commit(pop_commit),
        .push_en(push_en),
        .push_slot(push_slot),
        .empty(empty),
        .full(full),
        .free_count(free_count),
        .active_count(active_count)
    );

    always #5 clk = ~clk;

    integer test_count;
    integer pass_count;

    task check;
        input [511:0] test_name;
        input cond;
        begin
            test_count = test_count + 1;
            if (cond) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end else begin
                $display("[FAIL] %0s", test_name);
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        init_start = 0;
        rd_top_en = 0;
        pop_commit = 0;
        push_en = 0;
        push_slot = 0;
        test_count = 0;
        pass_count = 0;

        $display("=== Starting tb_lob_free_list ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Initialization
        init_start = 1;
        #10 init_start = 0;
        wait(init_done == 1);
        #10;
        check("Free list initialized (full=1, free_count=2048, active_count=0)",
              (full == 1) && (free_count == 12'd2048) && (active_count == 12'd0));

        // Test 2: Prefetch top slot (sp-1 = 2047)
        rd_top_en = 1;
        #10;
        rd_top_en = 0;
        check("Top slot is 2047 with top_valid=1", (top_valid == 1) && (top_slot == 11'd2047));

        // Test 3: Commit pop
        pop_commit = 1;
        #10;
        pop_commit = 0;
        check("After pop_commit: free_count=2047, active_count=1",
              (free_count == 12'd2047) && (active_count == 12'd1));

        // Test 4: Prefetch next top slot (2046)
        rd_top_en = 1;
        #10;
        rd_top_en = 0;
        check("Next top slot is 2046", (top_valid == 1) && (top_slot == 11'd2046));

        // Test 5: Reclaim (push) slot 2047 back
        push_en = 1;
        push_slot = 11'd2047;
        #10;
        push_en = 0;
        check("After push: free_count=2048, full=1",
              (free_count == 12'd2048) && (full == 1));

        // Read top again to verify pushed value is now at top
        rd_top_en = 1;
        #10;
        rd_top_en = 0;
        check("Pushed slot 2047 is back at top", (top_valid == 1) && (top_slot == 11'd2047));

        $display("tb_lob_free_list: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) begin
            $display("Test failures detected!");
            $finish(1);
        end
        $finish;
    end

endmodule
