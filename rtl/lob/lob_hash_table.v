// 1,024 sets x 8 ways hash table with 8-entry CAM collision stash
// See docs/rtl_reference.md for how this block fits in the LOB.

`timescale 1ns / 1ps

`include "lob_defines.vh"

// Helper Module: 1,024 x 76-bit Simple Dual-Port Block RAM for one Hash Way
// Infers dedicated RAMB18E1 primitives cleanly without registers
module lob_hash_way_ram (
    input  wire        clk,
    input  wire        wr_en,
    input  wire [9:0]  wr_set,
    input  wire [75:0] wr_data,
    input  wire        rd_en,
    input  wire [9:0]  rd_set,
    output reg  [75:0] rd_data,
    input  wire        dbg_clk,
    input  wire [9:0]  dbg_set,
    output reg  [75:0] dbg_data
);
    // Two physical copies keep each RAM at one write plus one read port.
    // The original core read and the VGA-clock read cannot share a 2-port
    // BRAM with the write port.
    (* ram_style = "block" *) reg [75:0] mem [0:1023];
    (* ram_style = "block" *) reg [75:0] dbg_mem [0:1023];

    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_set] <= wr_data;
            dbg_mem[wr_set] <= wr_data;
        end
        if (rd_en) begin
            rd_data <= mem[rd_set];
        end
    end
    always @(posedge dbg_clk)
        dbg_data <= dbg_mem[dbg_set];
endmodule

module lob_hash_table #(
    parameter HASH_SETS     = `HASH_SETS,
    parameter HASH_SET_W    = `HASH_SET_W,
    parameter HASH_WAYS     = `HASH_WAYS,
    parameter HASH_WAY_W    = `HASH_WAY_W,
    parameter STASH_ENTRIES = `STASH_ENTRIES,
    parameter STASH_ADDR_W  = `STASH_ADDR_W,
    parameter SLOT_ADDR_W   = `SLOT_ADDR_W
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Hardware Initialization
    input  wire                    init_start,
    output wire                    init_busy,
    output reg                     init_done,

    // Set Read / Lookup Port (Latency = 1 cycle)
    input  wire                    rd_en,
    input  wire [HASH_SET_W-1:0]   rd_set,
    input  wire [63:0]             lookup_key,

    // Lookup Match Results (Valid 1 cycle after rd_en)
    output wire                    match_valid,
    output reg                     match_hit,
    output reg  [SLOT_ADDR_W-1:0]  match_slot,
    output reg  [HASH_WAY_W-1:0]   match_way,
    output reg                     match_is_stash,
    output reg  [STASH_ADDR_W-1:0] match_stash_idx,

    // Free Slot Availability for Insertion (Valid 1 cycle after rd_en)
    output wire                    free_way_avail,
    output wire [HASH_WAY_W-1:0]   free_way_idx,
    output wire                    free_stash_avail,
    output wire [STASH_ADDR_W-1:0] free_stash_idx,
    output wire                    bucket_full,

    // Insertion Write Port
    input  wire                    wr_way_en,
    input  wire [HASH_SET_W-1:0]   wr_set,
    input  wire [HASH_WAY_W-1:0]   wr_way_idx,
    input  wire                    wr_stash_en,
    input  wire [STASH_ADDR_W-1:0] wr_stash_idx,
    input  wire [SLOT_ADDR_W-1:0]  wr_slot,
    input  wire [63:0]             wr_key,

    // Invalidation Port (Remove on kill / replace)
    input  wire                    inv_way_en,
    input  wire [HASH_SET_W-1:0]   inv_set,
    input  wire [HASH_WAY_W-1:0]   inv_way_idx,
    input  wire                    inv_stash_en,
    input  wire [STASH_ADDR_W-1:0] inv_stash_idx,
    input  wire                    dbg_clk,
    input  wire [HASH_SET_W-1:0]   dbg_set,
    output wire [607:0]           dbg_ways,
    input  wire [STASH_ADDR_W-1:0] dbg_stash_idx,
    output reg  [75:0]            dbg_stash_data
);

    // 8 Ways of 1,024 Sets (each 76 bits: valid, slot[10:0], key[63:0])
    // 8-entry CAM Stash (Registers/FFs)
    reg [75:0] stash [0:STASH_ENTRIES-1];
    always @(posedge dbg_clk)
        dbg_stash_data <= stash[dbg_stash_idx];

    // Initialization Counter
    reg [HASH_SET_W:0] init_cnt;
    reg                initializing;

    assign init_busy = initializing;

    // Synchronous Read Pipeline
    wire [75:0]            way_rd_data [0:HASH_WAYS-1];
    reg  [63:0]            key_q;
    reg                    rd_en_q;
    reg  [HASH_SET_W-1:0]  rd_set_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_q    <= 64'd0;
            rd_en_q  <= 1'b0;
            rd_set_q <= {HASH_SET_W{1'b0}};
        end else begin
            rd_en_q  <= rd_en;
            if (rd_en) begin
                key_q    <= lookup_key;
                rd_set_q <= rd_set;
            end
        end
    end

    // Memory storage and ports for all 8 ways (1 cycle latency)
    reg  [75:0]            way_wr_data [0:HASH_WAYS-1];
    reg                    way_wr_en   [0:HASH_WAYS-1];
    reg  [HASH_SET_W-1:0]  way_wr_addr [0:HASH_WAYS-1];
    wire [75:0]            way_rd_raw  [0:HASH_WAYS-1];

    genvar w_gen;
    generate
        for (w_gen = 0; w_gen < HASH_WAYS; w_gen = w_gen + 1) begin : gen_way_bram
            always @* begin
                if (initializing) begin
                    way_wr_en[w_gen]   = 1'b1;
                    way_wr_addr[w_gen] = init_cnt[HASH_SET_W-1:0];
                    way_wr_data[w_gen] = 76'd0;
                end else if (wr_way_en && (wr_way_idx == w_gen)) begin
                    way_wr_en[w_gen]   = 1'b1;
                    way_wr_addr[w_gen] = wr_set;
                    way_wr_data[w_gen] = {1'b1, wr_slot, wr_key};
                end else if (inv_way_en && (inv_way_idx == w_gen)) begin
                    way_wr_en[w_gen]   = 1'b1;
                    way_wr_addr[w_gen] = inv_set;
                    way_wr_data[w_gen] = 76'd0;
                end else begin
                    way_wr_en[w_gen]   = 1'b0;
                    way_wr_addr[w_gen] = {HASH_SET_W{1'b0}};
                    way_wr_data[w_gen] = 76'd0;
                end
            end

            lob_hash_way_ram u_way_bram (
                .clk     (clk),
                .wr_en   (way_wr_en[w_gen]),
                .wr_set  (way_wr_addr[w_gen]),
                .wr_data (way_wr_data[w_gen]),
                .rd_en   (rd_en),
                .rd_set  (rd_set),
                .rd_data (way_rd_raw[w_gen]),
                .dbg_clk (dbg_clk),
                .dbg_set (dbg_set),
                .dbg_data(dbg_ways[w_gen*76 +: 76])
            );

            assign way_rd_data[w_gen] = way_rd_raw[w_gen];
        end
    endgenerate

    // Lookup Compare & Free-Bucket Search Logic (Cycle t+1)
    reg                    way_hit;
    reg [SLOT_ADDR_W-1:0]  way_hit_slot;
    reg [HASH_WAY_W-1:0]   way_hit_idx;

    reg                    stash_hit;
    reg [SLOT_ADDR_W-1:0]  stash_hit_slot;
    reg [STASH_ADDR_W-1:0] stash_hit_idx;

    reg                    found_free_way;
    reg [HASH_WAY_W-1:0]   first_free_way;

    reg                    found_free_stash;
    reg [STASH_ADDR_W-1:0] first_free_stash;

    integer w_loop;
    integer s_loop;

    always @* begin
        way_hit        = 1'b0;
        way_hit_slot   = {SLOT_ADDR_W{1'b0}};
        way_hit_idx    = {HASH_WAY_W{1'b0}};
        found_free_way = 1'b0;
        first_free_way = {HASH_WAY_W{1'b0}};

        // Check 8 BRAM ways
        for (w_loop = HASH_WAYS - 1; w_loop >= 0; w_loop = w_loop - 1) begin
            if (way_rd_data[w_loop][`HASH_VALID_BIT]) begin
                if (way_rd_data[w_loop][`HASH_KEY_SLICE] == key_q) begin
                    way_hit      = 1'b1;
                    way_hit_slot = way_rd_data[w_loop][`HASH_SLOT_SLICE];
                    way_hit_idx  = w_loop[HASH_WAY_W-1:0];
                end
            end else begin
                found_free_way = 1'b1;
                first_free_way = w_loop[HASH_WAY_W-1:0];
            end
        end

        stash_hit        = 1'b0;
        stash_hit_slot   = {SLOT_ADDR_W{1'b0}};
        stash_hit_idx    = {STASH_ADDR_W{1'b0}};
        found_free_stash = 1'b0;
        first_free_stash = {STASH_ADDR_W{1'b0}};

        // Check 8 Stash entries in parallel
        for (s_loop = STASH_ENTRIES - 1; s_loop >= 0; s_loop = s_loop - 1) begin
            if (stash[s_loop][`HASH_VALID_BIT]) begin
                if (stash[s_loop][`HASH_KEY_SLICE] == key_q) begin
                    stash_hit      = 1'b1;
                    stash_hit_slot = stash[s_loop][`HASH_SLOT_SLICE];
                    stash_hit_idx  = s_loop[STASH_ADDR_W-1:0];
                end
            end else begin
                found_free_stash = 1'b1;
                first_free_stash = s_loop[STASH_ADDR_W-1:0];
            end
        end
    end

    assign match_valid = rd_en_q;

    always @* begin
        if (stash_hit) begin
            match_hit       = 1'b1;
            match_slot      = stash_hit_slot;
            match_way       = {HASH_WAY_W{1'b0}};
            match_is_stash  = 1'b1;
            match_stash_idx = stash_hit_idx;
        end else if (way_hit) begin
            match_hit       = 1'b1;
            match_slot      = way_hit_slot;
            match_way       = way_hit_idx;
            match_is_stash  = 1'b0;
            match_stash_idx = {STASH_ADDR_W{1'b0}};
        end else begin
            match_hit       = 1'b0;
            match_slot      = {SLOT_ADDR_W{1'b0}};
            match_way       = {HASH_WAY_W{1'b0}};
            match_is_stash  = 1'b0;
            match_stash_idx = {STASH_ADDR_W{1'b0}};
        end
    end

    assign free_way_avail   = found_free_way;
    assign free_way_idx     = first_free_way;
    assign free_stash_avail = found_free_stash;
    assign free_stash_idx   = first_free_stash;
    assign bucket_full      = (!found_free_way && !found_free_stash);

    // Stash Write & Invalidation
    integer s_init;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s_init = 0; s_init < STASH_ENTRIES; s_init = s_init + 1) begin
                stash[s_init] <= 76'd0;
            end
        end else begin
            if (initializing) begin
                for (s_init = 0; s_init < STASH_ENTRIES; s_init = s_init + 1) begin
                    stash[s_init] <= 76'd0;
                end
            end else begin
                if (wr_stash_en) begin
                    stash[wr_stash_idx] <= {1'b1, wr_slot, wr_key};
                end
                if (inv_stash_en) begin
                    stash[inv_stash_idx] <= 76'd0;
                end
            end
        end
    end

    // Initialization FSM (1,024 cycles)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt     <= {HASH_SET_W+1{1'b0}};
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= {HASH_SET_W+1{1'b0}};
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
