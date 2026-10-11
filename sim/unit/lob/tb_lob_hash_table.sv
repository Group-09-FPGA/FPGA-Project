// =============================================================================
// File: tb_lob_hash_table.sv
// Description: Unit testbench for 1024x8 hash table and 8-entry CAM stash
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_lob_hash_table;

    logic        clk;
    logic        rst_n;
    logic        init_start;
    logic        init_busy;
    logic        init_done;

    logic        rd_en;
    logic [9:0]  rd_set;
    logic [63:0] lookup_key;

    logic        match_valid;
    logic        match_hit;
    logic [10:0] match_slot;
    logic [2:0]  match_way;
    logic        match_is_stash;
    logic [2:0]  match_stash_idx;

    logic        free_way_avail;
    logic [2:0]  free_way_idx;
    logic        free_stash_avail;
    logic [2:0]  free_stash_idx;
    logic        bucket_full;

    logic        wr_way_en;
    logic [9:0]  wr_set;
    logic [2:0]  wr_way_idx;
    logic        wr_stash_en;
    logic [2:0]  wr_stash_idx;
    logic [10:0] wr_slot;
    logic [63:0] wr_key;

    logic        inv_way_en;
    logic [9:0]  inv_set;
    logic [2:0]  inv_way_idx;
    logic        inv_stash_en;
    logic [2:0]  inv_stash_idx;

    lob_hash_table dut (
        .clk(clk),
        .rst_n(rst_n),
        .init_start(init_start),
        .init_busy(init_busy),
        .init_done(init_done),
        .rd_en(rd_en),
        .rd_set(rd_set),
        .lookup_key(lookup_key),
        .match_valid(match_valid),
        .match_hit(match_hit),
        .match_slot(match_slot),
        .match_way(match_way),
        .match_is_stash(match_is_stash),
        .match_stash_idx(match_stash_idx),
        .free_way_avail(free_way_avail),
        .free_way_idx(free_way_idx),
        .free_stash_avail(free_stash_avail),
        .free_stash_idx(free_stash_idx),
        .bucket_full(bucket_full),
        .wr_way_en(wr_way_en),
        .wr_set(wr_set),
        .wr_way_idx(wr_way_idx),
        .wr_stash_en(wr_stash_en),
        .wr_stash_idx(wr_stash_idx),
        .wr_slot(wr_slot),
        .wr_key(wr_key),
        .inv_way_en(inv_way_en),
        .inv_set(inv_set),
        .inv_way_idx(inv_way_idx),
        .inv_stash_en(inv_stash_en),
        .inv_stash_idx(inv_stash_idx)
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
        rd_en = 0;
        rd_set = 0;
        lookup_key = 0;
        wr_way_en = 0;
        wr_set = 0;
        wr_way_idx = 0;
        wr_stash_en = 0;
        wr_stash_idx = 0;
        wr_slot = 0;
        wr_key = 0;
        inv_way_en = 0;
        inv_set = 0;
        inv_way_idx = 0;
        inv_stash_en = 0;
        inv_stash_idx = 0;

        $display("=== Starting tb_lob_hash_table ===");
        #20 rst_n = 1;
        #10;

        // Test 1: Initialize hash table
        init_start = 1;
        #10 init_start = 0;
        wait(init_done == 1);
        @(posedge clk);
        #1;
        check("Hash table initialized (init_done=1)", init_done == 1 && init_busy == 0);

        // Test 2: Miss on empty table
        lookup_key = 64'd12345;
        rd_set = hash_oid(lookup_key);
        rd_en = 1;
        @(posedge clk);
        #1;
        rd_en = 0;
        check($sformatf("Lookup on empty table returns miss and free way available (valid=%b, hit=%b, free_avail=%b, free_idx=%0d)",
                        match_valid, match_hit, free_way_avail, free_way_idx),
              match_valid == 1 && match_hit == 0 && free_way_avail == 1);

        // Test 3: Insert into way 0 and read back
        wr_way_en = 1;
        wr_set = hash_oid(64'd12345);
        wr_way_idx = 3'd0;
        wr_slot = 11'd42;
        wr_key = 64'd12345;
        #10;
        wr_way_en = 0;

        lookup_key = 64'd12345;
        rd_set = hash_oid(lookup_key);
        rd_en = 1;
        #10;
        rd_en = 0;
        #1;
        check("Lookup finds inserted key in way 0 with slot 42",
              match_valid == 1 && match_hit == 1 && match_is_stash == 0 &&
              match_way == 3'd0 && match_slot == 11'd42);

        // Test 4: Fill all 8 ways in the same set to trigger stash
        for (int w = 1; w < 8; w++) begin
            wr_way_en = 1;
            wr_set = hash_oid(64'd12345);
            wr_way_idx = 3'(w);
            wr_slot = 11'(100 + w);
            // Construct keys that have the exact same hash
            // Since hash_oid folds 10-bit chunks, adding (1 << 60) doesn't change bottom 6 bits if added in same chunk,
            // or simply use distinct keys:
            wr_key = 64'd12345 + (64'(w) << 10) + (64'(w) << 20); // hash is same because w XOR w = 0!
            #10;
        end
        wr_way_en = 0;

        // Now lookup in this set to see that all 8 ways are full and free_stash_avail is true
        lookup_key = 64'd99999;
        rd_set = hash_oid(64'd12345); // read the full set
        rd_en = 1;
        #10;
        rd_en = 0;
        #1;
        check("When all 8 ways are occupied, free_way_avail=0 and free_stash_avail=1",
              free_way_avail == 0 && free_stash_avail == 1 && !bucket_full);

        // Test 5: Insert 9th colliding key into stash
        wr_stash_en = 1;
        wr_stash_idx = 3'd0;
        wr_slot = 11'd777;
        wr_key = 64'hAABBCCDDEEFF0011;
        #10;
        wr_stash_en = 0;

        // Lookup key in stash
        lookup_key = 64'hAABBCCDDEEFF0011;
        rd_set = hash_oid(lookup_key);
        rd_en = 1;
        #10;
        rd_en = 0;
        #1;
        check("Lookup finds key in stash (match_is_stash=1, slot=777)",
              match_hit == 1 && match_is_stash == 1 && match_stash_idx == 3'd0 && match_slot == 11'd777);

        // Test 6: Invalidate key in way 0
        inv_way_en = 1;
        inv_set = hash_oid(64'd12345);
        inv_way_idx = 3'd0;
        #10;
        inv_way_en = 0;

        lookup_key = 64'd12345;
        rd_set = hash_oid(lookup_key);
        rd_en = 1;
        #10;
        rd_en = 0;
        #1;
        check("After invalidation, key 12345 is not found", match_hit == 0);

        $display("tb_lob_hash_table: %0d / %0d passed.", pass_count, test_count);
        if (pass_count != test_count) $fatal(1, "Test failures detected!");
        $finish;
    end

endmodule
