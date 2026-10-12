// =============================================================================
// File: lob_hash_table.sv
// Description: 1,024 sets x 8 ways hash table with 8-entry CAM collision stash
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §12, §15, §16
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module lob_hash_table #(
    parameter int unsigned HASH_SETS     = lob_pkg::HASH_SETS,
    parameter int unsigned HASH_SET_W    = lob_pkg::HASH_SET_W,
    parameter int unsigned HASH_WAYS     = lob_pkg::HASH_WAYS,
    parameter int unsigned HASH_WAY_W    = lob_pkg::HASH_WAY_W,
    parameter int unsigned STASH_ENTRIES = lob_pkg::STASH_ENTRIES,
    parameter int unsigned STASH_ADDR_W  = lob_pkg::STASH_ADDR_W,
    parameter int unsigned SLOT_ADDR_W   = lob_pkg::SLOT_ADDR_W
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Hardware Initialization
    input  logic                    init_start,
    output logic                    init_busy,
    output logic                    init_done,

    // Set Read / Lookup Port (Latency = 1 cycle)
    input  logic                    rd_en,
    input  logic [HASH_SET_W-1:0]   rd_set,
    input  logic [63:0]             lookup_key,

    // Lookup Match Results (Valid 1 cycle after rd_en)
    output logic                    match_valid,
    output logic                    match_hit,
    output logic [SLOT_ADDR_W-1:0]  match_slot,
    output logic [HASH_WAY_W-1:0]   match_way,
    output logic                    match_is_stash,
    output logic [STASH_ADDR_W-1:0] match_stash_idx,

    // Free Slot Availability for Insertion (Valid 1 cycle after rd_en)
    output logic                    free_way_avail,
    output logic [HASH_WAY_W-1:0]   free_way_idx,
    output logic                    free_stash_avail,
    output logic [STASH_ADDR_W-1:0] free_stash_idx,
    output logic                    bucket_full,

    // Insertion Write Port
    input  logic                    wr_way_en,
    input  logic [HASH_SET_W-1:0]   wr_set,
    input  logic [HASH_WAY_W-1:0]   wr_way_idx,
    input  logic                    wr_stash_en,
    input  logic [STASH_ADDR_W-1:0] wr_stash_idx,
    input  logic [SLOT_ADDR_W-1:0]  wr_slot,
    input  logic [63:0]             wr_key,

    // Invalidation Port (Remove on kill / replace)
    input  logic                    inv_way_en,
    input  logic [HASH_SET_W-1:0]   inv_set,
    input  logic [HASH_WAY_W-1:0]   inv_way_idx,
    input  logic                    inv_stash_en,
    input  logic [STASH_ADDR_W-1:0] inv_stash_idx
);

    // -------------------------------------------------------------------------
    // 8 Ways of 1,024 Sets (each 76 bits: valid, slot[10:0], key[63:0])
    // -------------------------------------------------------------------------
    // Each way synthesizes cleanly into RAMB18E1 primitives (5 x RAMB18 1Kx18)
    (* ram_style = "block" *)
    logic [75:0] way_mem [0:HASH_WAYS-1][0:HASH_SETS-1];

    // 8-entry CAM Stash (Registers/FFs)
    hash_entry_t stash [0:STASH_ENTRIES-1];

    // Initialization Counter
    logic [HASH_SET_W:0] init_cnt;
    logic                initializing;

    assign init_busy = initializing;

    // -------------------------------------------------------------------------
    // Synchronous Read Pipeline
    // -------------------------------------------------------------------------
    hash_entry_t way_rd_data [0:HASH_WAYS-1];
    logic [63:0] key_q;
    logic        rd_en_q;
    logic [HASH_SET_W-1:0] rd_set_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_q    <= '0;
            rd_en_q  <= 1'b0;
            rd_set_q <= '0;
        end else begin
            rd_en_q  <= rd_en;
            if (rd_en) begin
                key_q    <= lookup_key;
                rd_set_q <= rd_set;
            end
        end
    end

    // Memory read from all 8 ways (1 cycle latency)
    generate
        for (genvar w = 0; w < HASH_WAYS; w++) begin : gen_way_read
            always_ff @(posedge clk) begin
                if (rd_en) begin
                    way_rd_data[w] <= hash_entry_t'(way_mem[w][rd_set]);
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Lookup Compare & Free-Bucket Search Logic (Cycle t+1)
    // -------------------------------------------------------------------------
    logic                    way_hit;
    logic [SLOT_ADDR_W-1:0]  way_hit_slot;
    logic [HASH_WAY_W-1:0]   way_hit_idx;

    logic                    stash_hit;
    logic [SLOT_ADDR_W-1:0]  stash_hit_slot;
    logic [STASH_ADDR_W-1:0] stash_hit_idx;

    logic                    found_free_way;
    logic [HASH_WAY_W-1:0]   first_free_way;

    logic                    found_free_stash;
    logic [STASH_ADDR_W-1:0] first_free_stash;

    always_comb begin
        way_hit        = 1'b0;
        way_hit_slot   = '0;
        way_hit_idx    = '0;
        found_free_way = 1'b0;
        first_free_way = '0;

        // Check 8 BRAM ways
        for (int w = HASH_WAYS - 1; w >= 0; w--) begin
            if (way_rd_data[w].valid) begin
                if (way_rd_data[w].key == key_q) begin
                    way_hit      = 1'b1;
                    way_hit_slot = way_rd_data[w].slot;
                    way_hit_idx  = HASH_WAY_W'(w);
                end
            end else begin
                found_free_way = 1'b1;
                first_free_way = HASH_WAY_W'(w);
            end
        end

        stash_hit        = 1'b0;
        stash_hit_slot   = '0;
        stash_hit_idx    = '0;
        found_free_stash = 1'b0;
        first_free_stash = '0;

        // Check 8 Stash entries in parallel
        for (int s = STASH_ENTRIES - 1; s >= 0; s--) begin
            if (stash[s].valid) begin
                if (stash[s].key == key_q) begin
                    stash_hit      = 1'b1;
                    stash_hit_slot = stash[s].slot;
                    stash_hit_idx  = STASH_ADDR_W'(s);
                end
            end else begin
                found_free_stash = 1'b1;
                first_free_stash = STASH_ADDR_W'(s);
            end
        end
    end

    assign match_valid = rd_en_q;

    always_comb begin
        if (stash_hit) begin
            match_hit       = 1'b1;
            match_slot      = stash_hit_slot;
            match_way       = '0;
            match_is_stash  = 1'b1;
            match_stash_idx = stash_hit_idx;
        end else if (way_hit) begin
            match_hit       = 1'b1;
            match_slot      = way_hit_slot;
            match_way       = way_hit_idx;
            match_is_stash  = 1'b0;
            match_stash_idx = '0;
        end else begin
            match_hit       = 1'b0;
            match_slot      = '0;
            match_way       = '0;
            match_is_stash  = 1'b0;
            match_stash_idx = '0;
        end
    end

    assign free_way_avail   = found_free_way;
    assign free_way_idx     = first_free_way;
    assign free_stash_avail = found_free_stash;
    assign free_stash_idx   = first_free_stash;
    assign bucket_full      = (!found_free_way && !found_free_stash);

    // -------------------------------------------------------------------------
    // Memory Write & Invalidation
    // -------------------------------------------------------------------------
    generate
        for (genvar w = 0; w < HASH_WAYS; w++) begin : gen_way_write
            always_ff @(posedge clk) begin
                if (initializing) begin
                    way_mem[w][init_cnt[HASH_SET_W-1:0]] <= '0;
                end else if (wr_way_en && (wr_way_idx == w)) begin
                    way_mem[w][wr_set] <= {1'b1, wr_slot, wr_key};
                end else if (inv_way_en && (inv_way_idx == w)) begin
                    way_mem[w][inv_set] <= '0;
                end
            end
        end
    endgenerate

    // Stash Write & Invalidation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < STASH_ENTRIES; s++) begin
                stash[s] <= '{valid: 1'b0, slot: '0, key: '0};
            end
        end else begin
            if (initializing) begin
                for (int s = 0; s < STASH_ENTRIES; s++) begin
                    stash[s] <= '{valid: 1'b0, slot: '0, key: '0};
                end
            end else begin
                if (wr_stash_en) begin
                    stash[wr_stash_idx] <= '{valid: 1'b1, slot: wr_slot, key: wr_key};
                end
                if (inv_stash_en) begin
                    stash[inv_stash_idx] <= '{valid: 1'b0, slot: '0, key: '0};
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Initialization FSM (1,024 cycles)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt     <= '0;
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= '0;
                initializing <= 1'b1;
                init_done    <= 1'b0;
            end else if (initializing) begin
                if (init_cnt == HASH_SETS - 1) begin
                    initializing <= 1'b0;
                    init_done    <= 1'b1;
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end
        end
    end

endmodule
