// Limit order book engine: takes one canonical event at a time, updates the
// hash table, slot table, free list, price RAM, occupancy bitmaps and BBO.
// Ports named display_* are read-only views used by the VGA and UART readback.

`timescale 1ns / 1ps

`include "lob_defines.vh"

module lob_core #(
    parameter [31:0] DEFAULT_PRICE_BASE   = 32'd0,
    parameter [31:0] DEFAULT_TICK         = 32'd1,
    parameter        DEFAULT_FAIL_STOP_EN = 1'b1
) (
    input  wire         clk,
    input  wire         rst_n,

    // Canonical Event Ingestion Interface
    input  wire         event_valid,
    output wire         event_ready,
    input  wire [255:0] event_data,

    // Runtime Control & Configuration
    input  wire         cfg_clear,
    input  wire         cfg_fail_stop_en,
    input  wire         run_enable,
    input  wire         feed_fault,
    input  wire [31:0]  cfg_price_base,
    input  wire [31:0]  cfg_tick,

    // Accelerator State & Telemetry
    output reg          book_valid,
    output reg          init_done,
    output wire         busy,
    output reg          error_valid,
    output reg  [7:0]   error_code,
    output wire [11:0]  active_order_count,
    output reg          event_done,
    // Last completed event's committed RAM writes, for UART storage telemetry.
    output wire [315:0] storage_trace,

    // Best Bid & Offer (BBO)
    output wire         best_bid_valid,
    output wire [31:0]  best_bid_price,
    output wire [31:0]  best_bid_qty,

    output wire         best_ask_valid,
    output wire [31:0]  best_ask_price,
    output wire [31:0]  best_ask_qty,

    // Read-only display ports for the existing FPGA memories.
    input  wire         display_clk,
    input  wire [10:0]  display_slot_addr,
    output wire [46:0]  display_slot_data,
    input  wire [9:0]   display_hash_set,
    output wire [607:0] display_hash_ways,
    input  wire [2:0]   display_stash_idx,
    output wire [75:0]  display_stash_data,
    input  wire [13:0]  display_price_addr,
    output wire [31:0]  display_price_data,
    input  wire [10:0]  display_free_addr,
    output wire [10:0]  display_free_data,
    output wire [11:0]  display_free_count,
    output reg          level_count_delta_valid,
    output reg          level_count_delta_inc,
    output reg [13:0]   level_count_delta_addr
);

    // Local Constants and Functions
    localparam [3:0] OP_ADD     = `OP_ADD;
    localparam [3:0] OP_EXECUTE = `OP_EXECUTE;
    localparam [3:0] OP_CANCEL  = `OP_CANCEL;
    localparam [3:0] OP_DELETE  = `OP_DELETE;
    localparam [3:0] OP_REPLACE = `OP_REPLACE;

    localparam [7:0] FAIL_NONE        = `FAIL_NONE;
    localparam [7:0] FAIL_EVT_FORMAT  = `FAIL_EVT_FORMAT;
    localparam [7:0] FAIL_DUP_OID     = `FAIL_DUP_OID;
    localparam [7:0] FAIL_MISSING_OID = `FAIL_MISSING_OID;
    localparam [7:0] FAIL_NO_SLOT     = `FAIL_NO_SLOT;
    localparam [7:0] FAIL_HASH_FULL   = `FAIL_HASH_FULL;
    localparam [7:0] FAIL_QTY_OVF     = `FAIL_QTY_OVF;
    localparam [7:0] FAIL_QTY_UF      = `FAIL_QTY_UF;
    localparam [7:0] FAIL_PRICE_OOW   = `FAIL_PRICE_OOW;
    localparam [7:0] FAIL_INVALID_OP  = `FAIL_INVALID_OP;
    localparam [7:0] FAIL_FEED_LOSS   = `FAIL_FEED_LOSS;

    function [9:0] hash_oid;
        input [63:0] oid;
        begin
            hash_oid = oid[9:0]   ^
                       oid[19:10] ^
                       oid[29:20] ^
                       oid[39:30] ^
                       oid[49:40] ^
                       oid[59:50] ^
                       {6'b0, oid[63:60]};
        end
    endfunction

    // Configuration Multiplexing (Registered for Timing Closure)
    reg [31:0] eff_price_base;
    reg [31:0] eff_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eff_price_base <= DEFAULT_PRICE_BASE;
            eff_tick       <= DEFAULT_TICK;
        end else begin
            eff_price_base <= cfg_price_base;
            eff_tick       <= (cfg_tick != 32'd0) ? cfg_tick : DEFAULT_TICK;
        end
    end

    wire eff_fail_stop;
    assign eff_fail_stop  = cfg_fail_stop_en;

    // Submodule Interconnect Wires

    // 1. Decoder Signals
    wire [255:0] dec_evt;
    wire             dec_valid;
    wire             dec_error;
    wire [7:0]       dec_err_code;
    wire             dec_is_add, dec_is_exec, dec_is_cancel, dec_is_delete, dec_is_replace, dec_price_oow;

    lob_event_decoder u_decoder (
        .raw_event(event_data), .decoded_evt(dec_evt), .evt_valid(dec_valid), .evt_error(dec_error),
        .error_code(dec_err_code), .is_add(dec_is_add), .is_exec(dec_is_exec),
        .is_cancel(dec_is_cancel), .is_delete(dec_is_delete), .is_replace(dec_is_replace),
        .price_oow(dec_price_oow)
    );

    // 2. Hash Table Signals
    reg          hash_init_start;
    wire         hash_init_busy, hash_init_done;
    reg          hash_rd_en;
    reg [9:0]    hash_rd_set;
    reg [63:0]   hash_lookup_key;
    wire         hash_match_valid, hash_match_hit;
    wire [10:0]  hash_match_slot;
    wire [2:0]   hash_match_way;
    wire         hash_match_is_stash;
    wire [2:0]   hash_match_stash_idx;
    wire         hash_free_way_avail;
    wire [2:0]   hash_free_way_idx;
    wire         hash_free_stash_avail;
    wire [2:0]   hash_free_stash_idx;
    wire         hash_bucket_full;
    reg          hash_wr_way_en;
    reg [9:0]    hash_wr_set;
    reg [2:0]    hash_wr_way_idx;
    reg          hash_wr_stash_en;
    reg [2:0]    hash_wr_stash_idx;
    reg [10:0]   hash_wr_slot;
    reg [63:0]   hash_wr_key;
    reg          hash_inv_way_en;
    reg [9:0]    hash_inv_set;
    reg [2:0]    hash_inv_way_idx;
    reg          hash_inv_stash_en;
    reg [2:0]    hash_inv_stash_idx;

    lob_hash_table u_hash_table (
        .clk(clk), .rst_n(rst_n), .init_start(hash_init_start), .init_busy(hash_init_busy),
        .init_done(hash_init_done), .rd_en(hash_rd_en), .rd_set(hash_rd_set),
        .lookup_key(hash_lookup_key), .match_valid(hash_match_valid), .match_hit(hash_match_hit),
        .match_slot(hash_match_slot), .match_way(hash_match_way),
        .match_is_stash(hash_match_is_stash), .match_stash_idx(hash_match_stash_idx),
        .free_way_avail(hash_free_way_avail), .free_way_idx(hash_free_way_idx),
        .free_stash_avail(hash_free_stash_avail), .free_stash_idx(hash_free_stash_idx),
        .bucket_full(hash_bucket_full), .wr_way_en(hash_wr_way_en), .wr_set(hash_wr_set),
        .wr_way_idx(hash_wr_way_idx), .wr_stash_en(hash_wr_stash_en),
        .wr_stash_idx(hash_wr_stash_idx), .wr_slot(hash_wr_slot), .wr_key(hash_wr_key),
        .inv_way_en(hash_inv_way_en), .inv_set(hash_inv_set), .inv_way_idx(hash_inv_way_idx),
        .inv_stash_en(hash_inv_stash_en), .inv_stash_idx(hash_inv_stash_idx),
        .dbg_clk(display_clk), .dbg_set(display_hash_set), .dbg_ways(display_hash_ways),
        .dbg_stash_idx(display_stash_idx), .dbg_stash_data(display_stash_data)
    );

    // 3. Slot Table Signals
    reg          slot_init_start;
    wire         slot_init_busy, slot_init_done;
    reg          slot_wr_en;
    reg [10:0]   slot_wr_addr;
    reg [46:0]   slot_wr_data;
    reg          slot_rd_en;
    reg [10:0]   slot_rd_addr;
    wire [46:0]  slot_rd_data;

    lob_slot_table u_slot_table (
        .clk(clk), .rst_n(rst_n), .init_start(slot_init_start), .init_busy(slot_init_busy),
        .init_done(slot_init_done), .wr_en(slot_wr_en), .wr_addr(slot_wr_addr),
        .wr_data(slot_wr_data), .rd_en(slot_rd_en), .rd_addr(slot_rd_addr), .rd_data(slot_rd_data),
        .dbg_clk(display_clk), .dbg_addr(display_slot_addr), .dbg_data(display_slot_data)
    );

    // 4. Free List Signals
    reg          free_init_start;
    wire         free_init_busy, free_init_done;
    reg          free_rd_top_en;
    wire [10:0]  free_top_slot;
    wire         free_top_valid;
    reg          free_pop_commit;
    reg          free_push_en;
    reg [10:0]   free_push_slot;
    wire         free_empty;
    wire         free_full;
    wire [11:0]  free_count;
    wire [11:0]  free_active_count;

    lob_free_list u_free_list (
        .clk(clk), .rst_n(rst_n), .init_start(free_init_start), .init_busy(free_init_busy),
        .init_done(free_init_done), .rd_top_en(free_rd_top_en), .top_slot(free_top_slot),
        .top_valid(free_top_valid), .pop_commit(free_pop_commit), .push_en(free_push_en),
        .push_slot(free_push_slot), .empty(free_empty), .full(free_full), .free_count(free_count),
        .active_count(free_active_count), .dbg_clk(display_clk), .dbg_addr(display_free_addr),
        .dbg_data(display_free_data)
    );

    assign display_free_count = free_count;

    assign active_order_count = free_active_count;

    // 5. Price RAM Signals
    reg          price_init_start;
    wire         price_init_busy, price_init_done;
    reg          price_wr_en;
    reg [13:0]  price_wr_addr;
    reg [31:0]  price_wr_data;
    reg          price_rd_en;
    reg [13:0]  price_rd_addr;
    wire         price_rd_valid;
    wire [31:0]  price_rd_data;

    lob_price_ram u_price_ram (
        .clk(clk), .rst_n(rst_n), .init_start(price_init_start), .init_busy(price_init_busy),
        .init_done(price_init_done), .wr_en(price_wr_en), .wr_addr(price_wr_addr),
        .wr_data(price_wr_data), .rd_en(price_rd_en), .rd_addr(price_rd_addr),
        .rd_valid(price_rd_valid), .rd_data(price_rd_data),
        .dbg_clk(display_clk), .dbg_addr(display_price_addr), .dbg_data(display_price_data)
    );

    // 6. Occupancy Signals
    reg          occ_init_start;
    wire         occ_init_busy, occ_init_done;
    reg          occ_leaf_rd_en;
    reg          occ_leaf_rd_side;
    reg [7:0]   occ_leaf_rd_word_idx;
    wire [31:0] occ_leaf_rd_data;
    reg          occ_leaf_upd_en;
    reg          occ_leaf_upd_side;
    reg [12:0]  occ_leaf_upd_pidx;
    reg          occ_leaf_upd_bit_val;
    reg          occ_search_start;
    reg          occ_search_side;
    wire         occ_search_busy;
    wire         occ_search_done;
    wire         occ_search_valid;
    wire [12:0] occ_search_pidx;
    wire         occ_bid_has_orders;
    wire         occ_ask_has_orders;

    lob_occupancy u_occupancy (
        .clk(clk), .rst_n(rst_n), .init_start(occ_init_start), .init_busy(occ_init_busy),
        .init_done(occ_init_done), .leaf_rd_en(occ_leaf_rd_en), .leaf_rd_side(occ_leaf_rd_side),
        .leaf_rd_word_idx(occ_leaf_rd_word_idx), .leaf_rd_data(occ_leaf_rd_data),
        .leaf_upd_en(occ_leaf_upd_en), .leaf_upd_side(occ_leaf_upd_side),
        .leaf_upd_pidx(occ_leaf_upd_pidx), .leaf_upd_bit_val(occ_leaf_upd_bit_val),
        .search_start(occ_search_start), .search_side(occ_search_side),
        .search_busy(occ_search_busy), .search_done(occ_search_done),
        .search_valid(occ_search_valid), .search_pidx(occ_search_pidx),
        .bid_has_orders(occ_bid_has_orders), .ask_has_orders(occ_ask_has_orders)
    );

    // 7. BBO Signals
    reg          bbo_direct_upd_en;
    reg          bbo_direct_side;
    reg [12:0]  bbo_direct_pidx;
    reg [31:0]  bbo_direct_qty;
    reg          bbo_search_upd_en;
    reg          bbo_search_side;
    reg          bbo_search_valid;
    reg [12:0]  bbo_search_pidx;
    reg [31:0]  bbo_search_qty;
    reg          bbo_clear_en;
    wire [12:0] bbo_cur_best_bid_pidx;
    wire [12:0] bbo_cur_best_ask_pidx;
    wire         bbo_check_side;
    wire [12:0] bbo_check_pidx;
    wire         bbo_triggers_search;

    lob_bbo u_bbo (
        .clk(clk), .rst_n(rst_n), .cfg_price_base(eff_price_base), .cfg_tick(eff_tick),
        .bbo_direct_upd_en(bbo_direct_upd_en), .bbo_direct_side(bbo_direct_side),
        .bbo_direct_pidx(bbo_direct_pidx), .bbo_direct_qty(bbo_direct_qty),
        .bbo_search_upd_en(bbo_search_upd_en), .bbo_search_side(bbo_search_side),
        .bbo_search_valid(bbo_search_valid), .bbo_search_pidx(bbo_search_pidx),
        .bbo_search_qty(bbo_search_qty), .clear_en(bbo_clear_en), .best_bid_valid(best_bid_valid),
        .best_bid_pidx(bbo_cur_best_bid_pidx), .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty), .best_ask_valid(best_ask_valid),
        .best_ask_pidx(bbo_cur_best_ask_pidx), .best_ask_price(best_ask_price),
        .best_ask_qty(best_ask_qty), .check_side(bbo_check_side), .check_pidx(bbo_check_pidx),
        .triggers_search(bbo_triggers_search)
    );

    // ---- sequencer --------------------------------------------------------
    localparam [5:0]
        ST_RESET = 0, ST_INIT_START = 1, ST_INIT_WAIT = 2, ST_IDLE = 3,
        ST_ADD_C1 = 4, ST_ADD_C2 = 5, ST_ADD_C3 = 6, ST_ADD_C4 = 7, ST_ADD_C5 = 8, ST_ADD_C6 = 9,
        ST_ECD_C1 = 10, ST_ECD_C2 = 11, ST_ECD_C3 = 12, ST_ECD_C4 = 13, ST_ECD_C5 = 14,
        ST_ECD_C6 = 15, ST_ECD_C7 = 16, ST_ECD_C8 = 17, ST_ECD_C9 = 18, ST_ECD_C10 = 19,
        ST_REP_C1 = 20, ST_REP_C2 = 21, ST_REP_C3 = 22, ST_REP_C4 = 23, ST_REP_C5 = 24,
        ST_REP_C6 = 25, ST_REP_C7 = 26, ST_REP_C8 = 27, ST_REP_C9 = 28, ST_REP_C10 = 29,
        ST_REP_C11 = 30, ST_REP_C12 = 31,
        ST_SEARCH_START = 32, ST_SEARCH_WAIT = 33, ST_SEARCH_PRICER = 34,
        ST_SEARCH_PRICE1 = 35, ST_SEARCH_PRICE2 = 36, ST_SEARCH_COMMIT = 37,
        ST_DONE = 38, ST_FAIL_STOP = 39;

    reg [5:0] state;

    reg [255:0] cur_evt;
    wire [3:0]  cur_evt_op     = cur_evt[`EVT_OP_SLICE];
    wire        cur_evt_side   = cur_evt[`EVT_SIDE_BIT];
    wire [63:0] cur_evt_oid    = cur_evt[`EVT_OID_SLICE];
    wire [63:0] cur_evt_noid   = cur_evt[`EVT_NOID_SLICE];
    wire [31:0] cur_evt_shares = cur_evt[`EVT_SHARES_SLICE];
    wire [12:0] cur_evt_pidx   = cur_evt[`EVT_PIDX_SLICE];

    wire        slot_rd_side   = slot_rd_data[`SLOT_SIDE_BIT];
    wire [12:0] slot_rd_pidx   = slot_rd_data[`SLOT_PIDX_SLICE];
    wire [31:0] slot_rd_shares = slot_rd_data[`SLOT_SHARES_SLICE];
    reg reg_is_add, reg_is_exec, reg_is_cancel, reg_is_delete, reg_is_replace;

    // Execute / cancel / delete working state
    reg [10:0] lat_slot;
    reg [2:0]  lat_way, lat_stash_idx;
    reg        lat_is_stash;
    reg        lat_ord_side;
    reg [12:0] lat_ord_pidx;
    reg [31:0] lat_ord_shares, lat_deduct_shares, lat_rem_shares, lat_new_level_qty;
    reg        lat_is_kill, lat_level_zero, lat_triggers_search;

    // Replace working state
    reg [10:0] rep_slot;
    reg [2:0]  rep_old_way, rep_old_stash_idx, rep_new_way, rep_new_stash_idx;
    reg        rep_old_is_stash, rep_new_use_stash, rep_ord_side;
    reg [12:0] rep_old_pidx, rep_new_pidx;
    reg [31:0] rep_old_shares, rep_new_shares, rep_price_old_qty, rep_price_new_qty;
    reg [31:0] rep_new_old_level_qty, rep_new_new_level_qty;
    reg        rep_old_level_zero, rep_triggers_search;

    // Best-price search working state
    reg        search_target_side;
    reg [12:0] found_search_pidx;
    reg        found_search_valid;

    assign busy        = (state != ST_IDLE) && (state != ST_FAIL_STOP);
    assign event_ready = (state == ST_IDLE) && init_done && book_valid &&
                         run_enable && !feed_fault;

    // The BBO compares the level being emptied against the current best.
    assign bbo_check_side = (state == ST_ECD_C8) ? lat_ord_side :
                            (state == ST_REP_C8) ? rep_ord_side : 1'b0;
    assign bbo_check_pidx = (state == ST_ECD_C8) ? lat_ord_pidx :
                            (state == ST_REP_C8) ? rep_old_pidx : 13'd0;

    lob_storage_trace u_trace (
        .clk(clk), .rst_n(rst_n),
        .event_accept(event_valid && event_ready), .event_done(event_done),
        .op(cur_evt_op), .oid(cur_evt_oid), .noid(cur_evt_noid),
        .slot_wr_en(slot_wr_en), .slot_wr_addr(slot_wr_addr), .slot_wr_data(slot_wr_data),
        .inv_way_en(hash_inv_way_en), .inv_stash_en(hash_inv_stash_en),
        .inv_set(hash_inv_stash_en ? hash_oid(cur_evt_oid) : hash_inv_set),
        .inv_way_idx(hash_inv_way_idx), .inv_stash_idx(hash_inv_stash_idx),
        .ins_way_en(hash_wr_way_en), .ins_stash_en(hash_wr_stash_en),
        .ins_set(hash_wr_stash_en ? hash_oid(hash_wr_key) : hash_wr_set),
        .ins_way_idx(hash_wr_way_idx), .ins_stash_idx(hash_wr_stash_idx),
        .price_wr_en(price_wr_en), .price_wr_addr(price_wr_addr), .price_wr_data(price_wr_data),
        .trace(storage_trace)
    );

    // ---- one-cycle command helpers (all drive registered controls) --------
    task fail;                      // record the error; stop if fail-stop is on
        input [7:0] code;
        begin
            error_valid <= 1'b1;
            error_code  <= code;
            if (eff_fail_stop) begin
                book_valid <= 1'b0;
                state      <= ST_FAIL_STOP;
            end else
                state <= ST_IDLE;
        end
    endtask

    task finish;
        begin
            event_done <= 1'b1;
            state      <= ST_IDLE;
        end
    endtask

    task hash_lookup;
        input [63:0] oid;
        begin
            hash_rd_en      <= 1'b1;
            hash_rd_set     <= hash_oid(oid);
            hash_lookup_key <= oid;
        end
    endtask

    task hash_insert;
        input        use_stash;
        input [2:0]  stash_idx, way_idx;
        input [10:0] slot;
        input [63:0] key;
        begin
            hash_wr_slot <= slot;
            hash_wr_key  <= key;
            if (use_stash) begin
                hash_wr_stash_en  <= 1'b1;
                hash_wr_stash_idx <= stash_idx;
            end else begin
                hash_wr_way_en  <= 1'b1;
                hash_wr_set     <= hash_oid(key);
                hash_wr_way_idx <= way_idx;
            end
        end
    endtask

    task hash_remove;
        input       use_stash;
        input [2:0] stash_idx, way_idx;
        begin
            if (use_stash) begin
                hash_inv_stash_en  <= 1'b1;
                hash_inv_stash_idx <= stash_idx;
            end else begin
                hash_inv_way_en  <= 1'b1;
                hash_inv_set     <= hash_oid(cur_evt_oid);
                hash_inv_way_idx <= way_idx;
            end
        end
    endtask

    task slot_read;
        input [10:0] slot;
        begin
            slot_rd_en   <= 1'b1;
            slot_rd_addr <= slot;
        end
    endtask

    task slot_write;
        input [10:0] slot;
        input        valid, side;
        input [12:0] pidx;
        input [31:0] shares;
        begin
            slot_wr_en   <= 1'b1;
            slot_wr_addr <= slot;
            slot_wr_data <= {valid, side, pidx, shares};
        end
    endtask

    task price_read;
        input        side;
        input [12:0] pidx;
        begin
            price_rd_en   <= 1'b1;
            price_rd_addr <= {side, pidx};
        end
    endtask

    task price_write;
        input        side;
        input [12:0] pidx;
        input [31:0] qty;
        begin
            price_wr_en   <= 1'b1;
            price_wr_addr <= {side, pidx};
            price_wr_data <= qty;
        end
    endtask

    task level_count;               // order count of a price level changes by one
        input        inc, side;
        input [12:0] pidx;
        begin
            level_count_delta_valid <= 1'b1;
            level_count_delta_inc   <= inc;
            level_count_delta_addr  <= {side, pidx};
        end
    endtask

    task occupancy_set;
        input        side;
        input [12:0] pidx;
        input        val;
        begin
            occ_leaf_upd_en      <= 1'b1;
            occ_leaf_upd_side    <= side;
            occ_leaf_upd_pidx    <= pidx;
            occ_leaf_upd_bit_val <= val;
        end
    endtask

    task bbo_direct;
        input        side;
        input [12:0] pidx;
        input [31:0] qty;
        begin
            bbo_direct_upd_en <= 1'b1;
            bbo_direct_side   <= side;
            bbo_direct_pidx   <= pidx;
            bbo_direct_qty    <= qty;
        end
    endtask

    task bbo_search_result;
        input        valid;
        input [12:0] pidx;
        input [31:0] qty;
        begin
            bbo_search_upd_en <= 1'b1;
            bbo_search_side   <= search_target_side;
            bbo_search_valid  <= valid;
            bbo_search_pidx   <= pidx;
            bbo_search_qty    <= qty;
        end
    endtask

    // ---- main FSM ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RESET;
            book_valid <= 1'b0; init_done <= 1'b0;
            error_valid <= 1'b0; error_code <= FAIL_NONE;
            event_done <= 1'b0;
            level_count_delta_valid <= 1'b0; level_count_delta_inc <= 1'b0; level_count_delta_addr <= 14'd0;

            {hash_init_start, slot_init_start, free_init_start, price_init_start, occ_init_start} <= 5'd0;
            hash_rd_en <= 1'b0; hash_rd_set <= 0; hash_lookup_key <= 0;
            hash_wr_way_en <= 1'b0; hash_wr_set <= 0; hash_wr_way_idx <= 0;
            hash_wr_stash_en <= 1'b0; hash_wr_stash_idx <= 0; hash_wr_slot <= 0; hash_wr_key <= 0;
            hash_inv_way_en <= 1'b0; hash_inv_set <= 0; hash_inv_way_idx <= 0;
            hash_inv_stash_en <= 1'b0; hash_inv_stash_idx <= 0;
            slot_wr_en <= 1'b0; slot_wr_addr <= 0; slot_wr_data <= 0;
            slot_rd_en <= 1'b0; slot_rd_addr <= 0;
            free_rd_top_en <= 1'b0; free_pop_commit <= 1'b0; free_push_en <= 1'b0; free_push_slot <= 0;
            price_wr_en <= 1'b0; price_wr_addr <= 0; price_wr_data <= 0;
            price_rd_en <= 1'b0; price_rd_addr <= 0;
            occ_leaf_rd_en <= 1'b0; occ_leaf_rd_side <= 1'b0; occ_leaf_rd_word_idx <= 0;
            occ_leaf_upd_en <= 1'b0; occ_leaf_upd_side <= 1'b0; occ_leaf_upd_pidx <= 0; occ_leaf_upd_bit_val <= 1'b0;
            occ_search_start <= 1'b0; occ_search_side <= 1'b0;
            bbo_direct_upd_en <= 1'b0; bbo_direct_side <= 1'b0; bbo_direct_pidx <= 0; bbo_direct_qty <= 0;
            bbo_search_upd_en <= 1'b0; bbo_search_side <= 1'b0; bbo_search_valid <= 1'b0;
            bbo_search_pidx <= 0; bbo_search_qty <= 0; bbo_clear_en <= 1'b0;

            cur_evt <= 0;
            {reg_is_add, reg_is_exec, reg_is_cancel, reg_is_delete, reg_is_replace} <= 5'd0;
            lat_slot <= 0; lat_way <= 0; lat_is_stash <= 1'b0; lat_stash_idx <= 0;
            lat_ord_side <= 1'b0; lat_ord_pidx <= 0; lat_ord_shares <= 0;
            lat_deduct_shares <= 0; lat_rem_shares <= 0; lat_is_kill <= 1'b0;
            lat_new_level_qty <= 0; lat_level_zero <= 1'b0; lat_triggers_search <= 1'b0;
            rep_slot <= 0; rep_old_way <= 0; rep_old_is_stash <= 1'b0; rep_old_stash_idx <= 0;
            rep_new_way <= 0; rep_new_use_stash <= 1'b0; rep_new_stash_idx <= 0;
            rep_ord_side <= 1'b0; rep_old_pidx <= 0; rep_new_pidx <= 0;
            rep_old_shares <= 0; rep_new_shares <= 0; rep_price_old_qty <= 0; rep_price_new_qty <= 0;
            rep_new_old_level_qty <= 0; rep_new_new_level_qty <= 0;
            rep_old_level_zero <= 1'b0; rep_triggers_search <= 1'b0;
            search_target_side <= 1'b0; found_search_pidx <= 0; found_search_valid <= 1'b0;
        end else begin
            // Every command is a one-cycle pulse unless a state sets it again.
            event_done <= 1'b0; level_count_delta_valid <= 1'b0;
            {hash_init_start, slot_init_start, free_init_start, price_init_start, occ_init_start} <= 5'd0;
            hash_rd_en <= 1'b0; hash_wr_way_en <= 1'b0; hash_wr_stash_en <= 1'b0;
            hash_inv_way_en <= 1'b0; hash_inv_stash_en <= 1'b0;
            slot_wr_en <= 1'b0; slot_rd_en <= 1'b0;
            free_rd_top_en <= 1'b0; free_pop_commit <= 1'b0; free_push_en <= 1'b0;
            price_wr_en <= 1'b0; price_rd_en <= 1'b0;
            occ_leaf_rd_en <= 1'b0; occ_leaf_upd_en <= 1'b0; occ_search_start <= 1'b0;
            bbo_direct_upd_en <= 1'b0; bbo_search_upd_en <= 1'b0; bbo_clear_en <= 1'b0;

            if (cfg_clear && state != ST_INIT_WAIT) begin
                state <= ST_RESET;
                book_valid <= 1'b0; init_done <= 1'b0;
                error_valid <= 1'b0; error_code <= FAIL_NONE;
                bbo_clear_en <= 1'b1;
            end else if (feed_fault) begin
                // A lost message makes the book untrustworthy until reset and replay.
                state <= ST_FAIL_STOP;
                book_valid <= 1'b0; error_valid <= 1'b1; error_code <= FAIL_FEED_LOSS;
            end else begin
                case (state)
                    // -- initialisation --
                    ST_RESET: begin
                        {hash_init_start, slot_init_start, free_init_start, price_init_start, occ_init_start} <= 5'b11111;
                        bbo_clear_en <= 1'b1;
                        init_done    <= 1'b0;
                        book_valid   <= 1'b0;
                        state        <= ST_INIT_START;
                    end
                    ST_INIT_START: state <= ST_INIT_WAIT;
                    ST_INIT_WAIT: begin
                        // The price RAM (16384 cycles) is the slowest to initialise.
                        if (price_init_done && hash_init_done && slot_init_done && free_init_done && occ_init_done &&
                            !price_init_busy && !hash_init_busy && !slot_init_busy && !free_init_busy && !occ_init_busy) begin
                            init_done  <= 1'b1;
                            book_valid <= 1'b1;
                            state      <= ST_IDLE;
                        end
                    end

                    // -- accept an event --
                    ST_IDLE: begin
                        error_valid <= 1'b0;
                        if (event_valid && event_ready) begin
                            cur_evt        <= dec_evt;
                            reg_is_add     <= dec_is_add;
                            reg_is_exec    <= dec_is_exec;
                            reg_is_cancel  <= dec_is_cancel;
                            reg_is_delete  <= dec_is_delete;
                            reg_is_replace <= dec_is_replace;
                            if (dec_error)          fail(dec_err_code);
                            else if (dec_price_oow) fail(FAIL_PRICE_OOW);
                            else case (dec_evt[`EVT_OP_SLICE])
                                OP_ADD:                       state <= ST_ADD_C1;
                                OP_EXECUTE, OP_CANCEL, OP_DELETE: state <= ST_ECD_C1;
                                OP_REPLACE:                   state <= ST_REP_C1;
                                default:                      fail(FAIL_INVALID_OP);
                            endcase
                        end
                    end

                    // -- ADD --
                    ST_ADD_C1: begin   // prefetch from every structure
                        hash_lookup(cur_evt_oid);
                        free_rd_top_en       <= 1'b1;
                        price_read(cur_evt_side, cur_evt_pidx);
                        occ_leaf_rd_en       <= 1'b1;
                        occ_leaf_rd_side     <= cur_evt_side;
                        occ_leaf_rd_word_idx <= cur_evt_pidx[12:5];
                        state <= ST_ADD_C2;
                    end
                    ST_ADD_C2: state <= ST_ADD_C3;
                    ST_ADD_C3: begin
                        if (hash_match_hit)         fail(FAIL_DUP_OID);
                        else if (free_empty)        fail(FAIL_NO_SLOT);
                        else if (hash_bucket_full)  fail(FAIL_HASH_FULL);
                        else begin
                            lat_slot      <= free_top_slot;
                            lat_way       <= hash_free_way_idx;
                            lat_is_stash  <= !hash_free_way_avail && hash_free_stash_avail;
                            lat_stash_idx <= hash_free_stash_idx;
                            state         <= ST_ADD_C4;
                        end
                    end
                    ST_ADD_C4: if (price_rd_valid) begin
                        if ((price_rd_data + cur_evt_shares) < price_rd_data) fail(FAIL_QTY_OVF);
                        else begin
                            lat_new_level_qty <= price_rd_data + cur_evt_shares;
                            state             <= ST_ADD_C5;
                        end
                    end
                    ST_ADD_C5: begin   // commit
                        hash_insert(lat_is_stash, lat_stash_idx, lat_way, lat_slot, cur_evt_oid);
                        slot_write(lat_slot, 1'b1, cur_evt_side, cur_evt_pidx, cur_evt_shares);
                        free_pop_commit <= 1'b1;
                        price_write(cur_evt_side, cur_evt_pidx, lat_new_level_qty);
                        level_count(1'b1, cur_evt_side, cur_evt_pidx);
                        occupancy_set(cur_evt_side, cur_evt_pidx, 1'b1);
                        bbo_direct(cur_evt_side, cur_evt_pidx, lat_new_level_qty);
                        state <= ST_ADD_C6;
                    end
                    ST_ADD_C6: finish;

                    // -- EXECUTE / CANCEL / DELETE --
                    ST_ECD_C1: begin
                        hash_lookup(cur_evt_oid);
                        state <= ST_ECD_C2;
                    end
                    ST_ECD_C2: state <= ST_ECD_C3;
                    ST_ECD_C3: begin
                        if (!hash_match_hit) fail(FAIL_MISSING_OID);
                        else begin
                            lat_slot      <= hash_match_slot;
                            lat_way       <= hash_match_way;
                            lat_is_stash  <= hash_match_is_stash;
                            lat_stash_idx <= hash_match_stash_idx;
                            slot_read(hash_match_slot);
                            state <= ST_ECD_C4;
                        end
                    end
                    ST_ECD_C4: state <= ST_ECD_C5;
                    ST_ECD_C5: begin   // slot data valid
                        lat_ord_side   <= slot_rd_side;
                        lat_ord_pidx   <= slot_rd_pidx;
                        lat_ord_shares <= slot_rd_shares;
                        if (reg_is_delete) begin
                            lat_deduct_shares <= slot_rd_shares;
                            lat_rem_shares    <= 32'd0;
                            lat_is_kill       <= 1'b1;
                            price_read(slot_rd_side, slot_rd_pidx);
                            state             <= ST_ECD_C6;
                        end else begin
                            lat_deduct_shares <= cur_evt_shares;
                            if (cur_evt_shares > slot_rd_shares) fail(FAIL_QTY_UF);
                            else begin
                                lat_rem_shares <= slot_rd_shares - cur_evt_shares;
                                lat_is_kill    <= (slot_rd_shares == cur_evt_shares);
                                price_read(slot_rd_side, slot_rd_pidx);
                                state          <= ST_ECD_C6;
                            end
                        end
                    end
                    ST_ECD_C6: state <= ST_ECD_C7;
                    ST_ECD_C7: state <= ST_ECD_C8;
                    ST_ECD_C8: if (price_rd_valid) begin
                        if (lat_deduct_shares > price_rd_data) fail(FAIL_QTY_UF);
                        else begin
                            lat_new_level_qty   <= price_rd_data - lat_deduct_shares;
                            lat_level_zero      <= (price_rd_data == lat_deduct_shares);
                            lat_triggers_search <= bbo_triggers_search && (price_rd_data == lat_deduct_shares);
                            state               <= ST_ECD_C9;
                        end
                    end
                    ST_ECD_C9: begin   // commit
                        slot_write(lat_slot, !lat_is_kill, lat_ord_side, lat_ord_pidx, lat_rem_shares);
                        price_write(lat_ord_side, lat_ord_pidx, lat_new_level_qty);
                        if (lat_level_zero) occupancy_set(lat_ord_side, lat_ord_pidx, 1'b0);
                        if (lat_is_kill) begin
                            level_count(1'b0, lat_ord_side, lat_ord_pidx);
                            hash_remove(lat_is_stash, lat_stash_idx, lat_way);
                            free_push_en   <= 1'b1;
                            free_push_slot <= lat_slot;
                        end
                        if (!lat_triggers_search) bbo_direct(lat_ord_side, lat_ord_pidx, lat_new_level_qty);
                        state <= ST_ECD_C10;
                    end
                    ST_ECD_C10: begin
                        if (lat_triggers_search) begin
                            search_target_side <= lat_ord_side;
                            state              <= ST_SEARCH_START;
                        end else
                            finish;
                    end

                    // -- REPLACE --
                    ST_REP_C1: begin
                        hash_lookup(cur_evt_oid);
                        state <= ST_REP_C2;
                    end
                    ST_REP_C2: state <= ST_REP_C3;
                    ST_REP_C3: begin
                        if (!hash_match_hit) fail(FAIL_MISSING_OID);
                        else begin
                            rep_slot          <= hash_match_slot;
                            rep_old_way       <= hash_match_way;
                            rep_old_is_stash  <= hash_match_is_stash;
                            rep_old_stash_idx <= hash_match_stash_idx;
                            hash_lookup(cur_evt_noid);          // the new id must not exist
                            slot_read(hash_match_slot);
                            state <= ST_REP_C4;
                        end
                    end
                    ST_REP_C4: state <= ST_REP_C5;
                    ST_REP_C5: begin
                        if (hash_match_hit)         fail(FAIL_DUP_OID);
                        else if (hash_bucket_full)  fail(FAIL_HASH_FULL);
                        else begin
                            rep_new_way       <= hash_free_way_idx;
                            rep_new_use_stash <= !hash_free_way_avail && hash_free_stash_avail;
                            rep_new_stash_idx <= hash_free_stash_idx;
                            rep_ord_side      <= slot_rd_side;
                            rep_old_pidx      <= slot_rd_pidx;
                            rep_old_shares    <= slot_rd_shares;
                            rep_new_pidx      <= cur_evt_pidx;
                            rep_new_shares    <= cur_evt_shares;
                            price_read(slot_rd_side, slot_rd_pidx);      // old level
                            state <= ST_REP_C6;
                        end
                    end
                    ST_REP_C6: begin
                        price_read(rep_ord_side, rep_new_pidx);          // new level
                        state <= ST_REP_C7;
                    end
                    ST_REP_C7: state <= ST_REP_C8;
                    ST_REP_C8: if (price_rd_valid) begin               // old level data
                        rep_price_old_qty <= price_rd_data;
                        if (rep_old_shares > price_rd_data) fail(FAIL_QTY_UF);
                        else begin
                            rep_new_old_level_qty <= price_rd_data - rep_old_shares;
                            rep_old_level_zero    <= (price_rd_data == rep_old_shares);
                            rep_triggers_search   <= bbo_triggers_search && (price_rd_data == rep_old_shares);
                            state                 <= ST_REP_C9;
                        end
                    end
                    ST_REP_C9: if (price_rd_valid) begin               // new level data
                        rep_price_new_qty <= price_rd_data;
                        // Same level: add to the quantity left after removing the old order.
                        if (rep_old_pidx == rep_new_pidx) begin
                            if ((rep_new_old_level_qty + rep_new_shares) < rep_new_old_level_qty) fail(FAIL_QTY_OVF);
                            else begin
                                rep_new_new_level_qty <= rep_new_old_level_qty + rep_new_shares;
                                state                 <= ST_REP_C10;
                            end
                        end else begin
                            if ((price_rd_data + rep_new_shares) < price_rd_data) fail(FAIL_QTY_OVF);
                            else begin
                                rep_new_new_level_qty <= price_rd_data + rep_new_shares;
                                state                 <= ST_REP_C10;
                            end
                        end
                    end
                    ST_REP_C10: begin  // commit 1: remove the old entry and old level
                        hash_remove(rep_old_is_stash, rep_old_stash_idx, rep_old_way);
                        if (rep_old_pidx != rep_new_pidx) begin
                            level_count(1'b0, rep_ord_side, rep_old_pidx);
                            price_write(rep_ord_side, rep_old_pidx, rep_new_old_level_qty);
                            if (rep_old_level_zero) occupancy_set(rep_ord_side, rep_old_pidx, 1'b0);
                        end
                        state <= ST_REP_C11;
                    end
                    ST_REP_C11: begin  // commit 2: insert the new entry and new level
                        hash_insert(rep_new_use_stash, rep_new_stash_idx, rep_new_way, rep_slot, cur_evt_noid);
                        slot_write(rep_slot, 1'b1, rep_ord_side, rep_new_pidx, rep_new_shares);
                        price_write(rep_ord_side, rep_new_pidx, rep_new_new_level_qty);
                        if (rep_old_pidx != rep_new_pidx) level_count(1'b1, rep_ord_side, rep_new_pidx);
                        occupancy_set(rep_ord_side, rep_new_pidx, 1'b1);
                        if (rep_triggers_search && rep_old_pidx != rep_new_pidx) begin
                            search_target_side <= rep_ord_side;
                            state              <= ST_SEARCH_START;
                        end else begin
                            bbo_direct(rep_ord_side, rep_new_pidx, rep_new_new_level_qty);
                            state <= ST_REP_C12;
                        end
                    end
                    ST_REP_C12: finish;

                    // -- find the new best price after the best level emptied --
                    ST_SEARCH_START: begin
                        occ_search_start <= 1'b1;
                        occ_search_side  <= search_target_side;
                        state            <= ST_SEARCH_WAIT;
                    end
                    ST_SEARCH_WAIT: if (occ_search_done) begin
                        found_search_valid <= occ_search_valid;
                        found_search_pidx  <= occ_search_pidx;
                        if (occ_search_valid) begin
                            price_read(search_target_side, occ_search_pidx);
                            state <= ST_SEARCH_PRICER;
                        end else begin               // that side is now empty
                            bbo_search_result(1'b0, 13'd0, 32'd0);
                            state <= ST_DONE;
                        end
                    end
                    ST_SEARCH_PRICER: state <= ST_SEARCH_PRICE1;
                    ST_SEARCH_PRICE1: state <= ST_SEARCH_PRICE2;
                    ST_SEARCH_PRICE2: if (price_rd_valid) begin
                        bbo_search_result(1'b1, found_search_pidx, price_rd_data);
                        state <= ST_DONE;
                    end
                    ST_DONE: finish;

                    ST_FAIL_STOP: ;       // halted until reset
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
