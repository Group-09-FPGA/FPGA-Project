// =============================================================================
// File: lob_core.v
// Description: Top-level sequencer and transaction controller for LOB accelerator
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Behavior is defined by this RTL and its regression tests.
// =============================================================================

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

    // Best Bid & Offer (BBO)
    output wire         best_bid_valid,
    output wire [31:0]  best_bid_price,
    output wire [31:0]  best_bid_qty,

    output wire         best_ask_valid,
    output wire [31:0]  best_ask_price,
    output wire [31:0]  best_ask_qty
);

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    // Local Constants and Functions
    // -------------------------------------------------------------------------
    localparam [3:0] OP_INVALID = `OP_INVALID;
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
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Submodule Interconnect Wires
    // -------------------------------------------------------------------------

    // 1. Decoder Signals
    wire [255:0] dec_evt;
    wire             dec_valid;
    wire             dec_error;
    wire [7:0]       dec_err_code;
    wire             dec_is_add, dec_is_exec, dec_is_cancel, dec_is_delete, dec_is_replace, dec_price_oow;

    lob_event_decoder u_decoder (
        .raw_event(event_data),
        .decoded_evt(dec_evt),
        .evt_valid(dec_valid),
        .evt_error(dec_error),
        .error_code(dec_err_code),
        .is_add(dec_is_add),
        .is_exec(dec_is_exec),
        .is_cancel(dec_is_cancel),
        .is_delete(dec_is_delete),
        .is_replace(dec_is_replace),
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
        .clk(clk),
        .rst_n(rst_n),
        .init_start(hash_init_start),
        .init_busy(hash_init_busy),
        .init_done(hash_init_done),
        .rd_en(hash_rd_en),
        .rd_set(hash_rd_set),
        .lookup_key(hash_lookup_key),
        .match_valid(hash_match_valid),
        .match_hit(hash_match_hit),
        .match_slot(hash_match_slot),
        .match_way(hash_match_way),
        .match_is_stash(hash_match_is_stash),
        .match_stash_idx(hash_match_stash_idx),
        .free_way_avail(hash_free_way_avail),
        .free_way_idx(hash_free_way_idx),
        .free_stash_avail(hash_free_stash_avail),
        .free_stash_idx(hash_free_stash_idx),
        .bucket_full(hash_bucket_full),
        .wr_way_en(hash_wr_way_en),
        .wr_set(hash_wr_set),
        .wr_way_idx(hash_wr_way_idx),
        .wr_stash_en(hash_wr_stash_en),
        .wr_stash_idx(hash_wr_stash_idx),
        .wr_slot(hash_wr_slot),
        .wr_key(hash_wr_key),
        .inv_way_en(hash_inv_way_en),
        .inv_set(hash_inv_set),
        .inv_way_idx(hash_inv_way_idx),
        .inv_stash_en(hash_inv_stash_en),
        .inv_stash_idx(hash_inv_stash_idx)
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
        .clk(clk),
        .rst_n(rst_n),
        .init_start(slot_init_start),
        .init_busy(slot_init_busy),
        .init_done(slot_init_done),
        .wr_en(slot_wr_en),
        .wr_addr(slot_wr_addr),
        .wr_data(slot_wr_data),
        .rd_en(slot_rd_en),
        .rd_addr(slot_rd_addr),
        .rd_data(slot_rd_data)
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
        .clk(clk),
        .rst_n(rst_n),
        .init_start(free_init_start),
        .init_busy(free_init_busy),
        .init_done(free_init_done),
        .rd_top_en(free_rd_top_en),
        .top_slot(free_top_slot),
        .top_valid(free_top_valid),
        .pop_commit(free_pop_commit),
        .push_en(free_push_en),
        .push_slot(free_push_slot),
        .empty(free_empty),
        .full(free_full),
        .free_count(free_count),
        .active_count(free_active_count)
    );

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
        .clk(clk),
        .rst_n(rst_n),
        .init_start(price_init_start),
        .init_busy(price_init_busy),
        .init_done(price_init_done),
        .wr_en(price_wr_en),
        .wr_addr(price_wr_addr),
        .wr_data(price_wr_data),
        .rd_en(price_rd_en),
        .rd_addr(price_rd_addr),
        .rd_valid(price_rd_valid),
        .rd_data(price_rd_data)
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
        .clk(clk),
        .rst_n(rst_n),
        .init_start(occ_init_start),
        .init_busy(occ_init_busy),
        .init_done(occ_init_done),
        .leaf_rd_en(occ_leaf_rd_en),
        .leaf_rd_side(occ_leaf_rd_side),
        .leaf_rd_word_idx(occ_leaf_rd_word_idx),
        .leaf_rd_data(occ_leaf_rd_data),
        .leaf_upd_en(occ_leaf_upd_en),
        .leaf_upd_side(occ_leaf_upd_side),
        .leaf_upd_pidx(occ_leaf_upd_pidx),
        .leaf_upd_bit_val(occ_leaf_upd_bit_val),
        .search_start(occ_search_start),
        .search_side(occ_search_side),
        .search_busy(occ_search_busy),
        .search_done(occ_search_done),
        .search_valid(occ_search_valid),
        .search_pidx(occ_search_pidx),
        .bid_has_orders(occ_bid_has_orders),
        .ask_has_orders(occ_ask_has_orders)
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
        .clk(clk),
        .rst_n(rst_n),
        .cfg_price_base(eff_price_base),
        .cfg_tick(eff_tick),
        .bbo_direct_upd_en(bbo_direct_upd_en),
        .bbo_direct_side(bbo_direct_side),
        .bbo_direct_pidx(bbo_direct_pidx),
        .bbo_direct_qty(bbo_direct_qty),
        .bbo_search_upd_en(bbo_search_upd_en),
        .bbo_search_side(bbo_search_side),
        .bbo_search_valid(bbo_search_valid),
        .bbo_search_pidx(bbo_search_pidx),
        .bbo_search_qty(bbo_search_qty),
        .clear_en(bbo_clear_en),
        .best_bid_valid(best_bid_valid),
        .best_bid_pidx(bbo_cur_best_bid_pidx),
        .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty),
        .best_ask_valid(best_ask_valid),
        .best_ask_pidx(bbo_cur_best_ask_pidx),
        .best_ask_price(best_ask_price),
        .best_ask_qty(best_ask_qty),
        .check_side(bbo_check_side),
        .check_pidx(bbo_check_pidx),
        .triggers_search(bbo_triggers_search)
    );

    // -------------------------------------------------------------------------
    // Sequencer State Machine
    // -------------------------------------------------------------------------
    localparam [5:0]
        ST_RESET         = 6'd0,
        ST_INIT_START    = 6'd1,
        ST_INIT_WAIT     = 6'd2,
        ST_IDLE          = 6'd3,

        // ADD States (C1..C6)
        ST_ADD_C1        = 6'd4,
        ST_ADD_C2        = 6'd5,
        ST_ADD_C3        = 6'd6,
        ST_ADD_C4        = 6'd7,
        ST_ADD_C5        = 6'd8,
        ST_ADD_C6        = 6'd9,

        // EXECUTE / CANCEL / DELETE States (C1..C10)
        ST_ECD_C1        = 6'd10,
        ST_ECD_C2        = 6'd11,
        ST_ECD_C3        = 6'd12,
        ST_ECD_C4        = 6'd13,
        ST_ECD_C5        = 6'd14,
        ST_ECD_C6        = 6'd15,
        ST_ECD_C7        = 6'd16,
        ST_ECD_C8        = 6'd17,
        ST_ECD_C9        = 6'd18,
        ST_ECD_C10       = 6'd19,

        // REPLACE States (C1..C12)
        ST_REP_C1        = 6'd20,
        ST_REP_C2        = 6'd21,
        ST_REP_C3        = 6'd22,
        ST_REP_C4        = 6'd23,
        ST_REP_C5        = 6'd24,
        ST_REP_C6        = 6'd25,
        ST_REP_C7        = 6'd26,
        ST_REP_C8        = 6'd27,
        ST_REP_C9        = 6'd28,
        ST_REP_C10       = 6'd29,
        ST_REP_C11       = 6'd30,
        ST_REP_C12       = 6'd31,

        // Post-Removal BBO Search Pipeline
        ST_SEARCH_START  = 6'd32,
        ST_SEARCH_WAIT   = 6'd33,
        ST_SEARCH_PRICER = 6'd34,
        ST_SEARCH_PRICE1 = 6'd35,
        ST_SEARCH_PRICE2 = 6'd36,
        ST_SEARCH_COMMIT = 6'd37,

        // Terminal States
        ST_DONE          = 6'd38,
        ST_FAIL_STOP     = 6'd39;

    reg [5:0] state;


    // Operation Tracking Registers
    reg [255:0] cur_evt;

    wire [3:0]  cur_evt_ver    = cur_evt[`EVT_VER_SLICE];
    wire [3:0]  cur_evt_op     = cur_evt[`EVT_OP_SLICE];
    wire        cur_evt_side   = cur_evt[`EVT_SIDE_BIT];
    wire [63:0] cur_evt_oid    = cur_evt[`EVT_OID_SLICE];
    wire [63:0] cur_evt_noid   = cur_evt[`EVT_NOID_SLICE];
    wire [31:0] cur_evt_shares = cur_evt[`EVT_SHARES_SLICE];
    wire [12:0] cur_evt_pidx   = cur_evt[`EVT_PIDX_SLICE];
    wire        cur_evt_oow    = cur_evt[`EVT_OOW_BIT];
    wire [31:0] cur_evt_seq    = cur_evt[`EVT_SEQ_SLICE];

    wire        slot_rd_valid  = slot_rd_data[`SLOT_VALID_BIT];
    wire        slot_rd_side   = slot_rd_data[`SLOT_SIDE_BIT];
    wire [12:0] slot_rd_pidx   = slot_rd_data[`SLOT_PIDX_SLICE];
    wire [31:0] slot_rd_shares = slot_rd_data[`SLOT_SHARES_SLICE];
    reg               reg_is_add, reg_is_exec, reg_is_cancel, reg_is_delete, reg_is_replace;

    // Intermediate Latched State
    reg [10:0] lat_slot;
    reg [2:0]  lat_way;
    reg        lat_is_stash;
    reg [2:0]  lat_stash_idx;
    reg        lat_ord_side;
    reg [12:0] lat_ord_pidx;
    reg [31:0] lat_ord_shares;
    reg [31:0] lat_deduct_shares;
    reg [31:0] lat_rem_shares;
    reg        lat_is_kill;
    reg [31:0] lat_new_level_qty;
    reg        lat_level_zero;
    reg        lat_triggers_search;

    // Replace Specific Registers
    reg [10:0] rep_slot;
    reg [2:0]  rep_old_way;
    reg        rep_old_is_stash;
    reg [2:0]  rep_old_stash_idx;
    reg [2:0]  rep_new_way;
    reg        rep_new_use_stash;
    reg [2:0]  rep_new_stash_idx;
    reg        rep_ord_side;
    reg [12:0] rep_old_pidx;
    reg [12:0] rep_new_pidx;
    reg [31:0] rep_old_shares;
    reg [31:0] rep_new_shares;
    reg [31:0] rep_price_old_qty;
    reg [31:0] rep_price_new_qty;
    reg [31:0] rep_new_old_level_qty;
    reg [31:0] rep_new_new_level_qty;
    reg        rep_old_level_zero;
    reg        rep_triggers_search;

    // Search Execution State
    reg        search_target_side;
    reg [12:0] found_search_pidx;
    reg        found_search_valid;

    // -------------------------------------------------------------------------
    // Output Status Flags
    // -------------------------------------------------------------------------
    assign busy        = (state != ST_IDLE) && (state != ST_FAIL_STOP);
    assign event_ready = (state == ST_IDLE) && init_done && book_valid &&
                         run_enable && !feed_fault;

    // Trigger signals for check against current BBO
    assign bbo_check_side = (state == ST_ECD_C8) ? lat_ord_side :
                            (state == ST_REP_C8) ? rep_ord_side : 1'b0;
    assign bbo_check_pidx = (state == ST_ECD_C8) ? lat_ord_pidx :
                            (state == ST_REP_C8) ? rep_old_pidx : 13'd0;

    // -------------------------------------------------------------------------
    // Main Control FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_RESET;
            book_valid          <= 1'b0;
            init_done           <= 1'b0;
            error_valid         <= 1'b0;
            error_code          <= FAIL_NONE;
            event_done          <= 1'b0;

            hash_init_start     <= 1'b0;
            slot_init_start     <= 1'b0;
            free_init_start     <= 1'b0;
            price_init_start    <= 1'b0;
            occ_init_start      <= 1'b0;

            hash_rd_en          <= 1'b0;
            hash_rd_set         <= 0;
            hash_lookup_key     <= 0;
            hash_wr_way_en      <= 1'b0;
            hash_wr_set         <= 0;
            hash_wr_way_idx     <= 0;
            hash_wr_stash_en    <= 1'b0;
            hash_wr_stash_idx   <= 0;
            hash_wr_slot        <= 0;
            hash_wr_key         <= 0;
            hash_inv_way_en     <= 1'b0;
            hash_inv_set        <= 0;
            hash_inv_way_idx    <= 0;
            hash_inv_stash_en   <= 1'b0;
            hash_inv_stash_idx  <= 0;

            slot_wr_en          <= 1'b0;
            slot_wr_addr        <= 0;
            slot_wr_data        <= 0;
            slot_rd_en          <= 1'b0;
            slot_rd_addr        <= 0;

            free_rd_top_en      <= 1'b0;
            free_pop_commit     <= 1'b0;
            free_push_en        <= 1'b0;
            free_push_slot      <= 0;

            price_wr_en         <= 1'b0;
            price_wr_addr       <= 0;
            price_wr_data       <= 0;
            price_rd_en         <= 1'b0;
            price_rd_addr       <= 0;

            occ_leaf_rd_en      <= 1'b0;
            occ_leaf_rd_side    <= 1'b0;
            occ_leaf_rd_word_idx<= 0;
            occ_leaf_upd_en     <= 1'b0;
            occ_leaf_upd_side   <= 1'b0;
            occ_leaf_upd_pidx   <= 0;
            occ_leaf_upd_bit_val<= 1'b0;
            occ_search_start    <= 1'b0;
            occ_search_side     <= 1'b0;

            bbo_direct_upd_en   <= 1'b0;
            bbo_direct_side     <= 1'b0;
            bbo_direct_pidx     <= 0;
            bbo_direct_qty      <= 0;
            bbo_search_upd_en   <= 1'b0;
            bbo_search_side     <= 1'b0;
            bbo_search_valid    <= 1'b0;
            bbo_search_pidx     <= 0;
            bbo_search_qty      <= 0;
            bbo_clear_en        <= 1'b0;

            cur_evt             <= 0;
            reg_is_add          <= 1'b0;
            reg_is_exec         <= 1'b0;
            reg_is_cancel       <= 1'b0;
            reg_is_delete       <= 1'b0;
            reg_is_replace      <= 1'b0;

            lat_slot            <= 0;
            lat_way             <= 0;
            lat_is_stash        <= 1'b0;
            lat_stash_idx       <= 0;
            lat_ord_side        <= 1'b0;
            lat_ord_pidx        <= 0;
            lat_ord_shares      <= 0;
            lat_deduct_shares   <= 0;
            lat_rem_shares      <= 0;
            lat_is_kill         <= 1'b0;
            lat_new_level_qty   <= 0;
            lat_level_zero      <= 1'b0;
            lat_triggers_search <= 1'b0;

            rep_slot            <= 0;
            rep_old_way         <= 0;
            rep_old_is_stash    <= 1'b0;
            rep_old_stash_idx   <= 0;
            rep_new_way         <= 0;
            rep_new_use_stash   <= 1'b0;
            rep_new_stash_idx   <= 0;
            rep_ord_side        <= 1'b0;
            rep_old_pidx        <= 0;
            rep_new_pidx        <= 0;
            rep_old_shares      <= 0;
            rep_new_shares      <= 0;
            rep_price_old_qty   <= 0;
            rep_price_new_qty   <= 0;
            rep_new_old_level_qty <= 0;
            rep_new_new_level_qty <= 0;
            rep_old_level_zero  <= 1'b0;
            rep_triggers_search <= 1'b0;

            search_target_side  <= 1'b0;
            found_search_pidx   <= 0;
            found_search_valid  <= 1'b0;
        end else begin
            // Default single-cycle pulse resets
            event_done          <= 1'b0;
            hash_init_start     <= 1'b0;
            slot_init_start     <= 1'b0;
            free_init_start     <= 1'b0;
            price_init_start    <= 1'b0;
            occ_init_start      <= 1'b0;
            hash_rd_en          <= 1'b0;
            hash_wr_way_en      <= 1'b0;
            hash_wr_stash_en    <= 1'b0;
            hash_inv_way_en     <= 1'b0;
            hash_inv_stash_en   <= 1'b0;
            slot_wr_en          <= 1'b0;
            slot_rd_en          <= 1'b0;
            free_rd_top_en      <= 1'b0;
            free_pop_commit     <= 1'b0;
            free_push_en        <= 1'b0;
            price_wr_en         <= 1'b0;
            price_rd_en         <= 1'b0;
            occ_leaf_rd_en      <= 1'b0;
            occ_leaf_upd_en     <= 1'b0;
            occ_search_start    <= 1'b0;
            bbo_direct_upd_en   <= 1'b0;
            bbo_search_upd_en   <= 1'b0;
            bbo_clear_en        <= 1'b0;

            // Global CPU Clear Handling
            if (cfg_clear && (state != ST_INIT_WAIT)) begin
                state            <= ST_RESET;
                book_valid       <= 1'b0;
                init_done        <= 1'b0;
                error_valid      <= 1'b0;
                error_code       <= FAIL_NONE;
                bbo_clear_en     <= 1'b1;
            end else if (feed_fault) begin
                // The contents of the book cannot be trusted after a lost feed
                // event.  A full clear and replay is required before use.
                state       <= ST_FAIL_STOP;
                book_valid  <= 1'b0;
                error_valid <= 1'b1;
                error_code  <= FAIL_FEED_LOSS;
            end else begin
                case (state)
                    // ---------------------------------------------------------
                    // 0. RESET / HARDWARE INITIALIZATION
                    // ---------------------------------------------------------
                    ST_RESET: begin
                        hash_init_start  <= 1'b1;
                        slot_init_start  <= 1'b1;
                        free_init_start  <= 1'b1;
                        price_init_start <= 1'b1;
                        occ_init_start   <= 1'b1;
                        bbo_clear_en     <= 1'b1;
                        init_done        <= 1'b0;
                        book_valid       <= 1'b0;
                        state            <= ST_INIT_START;
                    end

                    ST_INIT_START: begin
                        // In this cycle, submodules have latched init_start=1 and asserted initializing=1
                        state <= ST_INIT_WAIT;
                    end

                    ST_INIT_WAIT: begin
                        // Price RAM initialization takes 16,384 cycles (dominates all others)
                        if (price_init_done && hash_init_done && slot_init_done && free_init_done && occ_init_done &&
                            !price_init_busy && !hash_init_busy && !slot_init_busy && !free_init_busy && !occ_init_busy) begin
                            init_done  <= 1'b1;
                            book_valid <= 1'b1;
                            state      <= ST_IDLE;
                        end
                    end

                    // ---------------------------------------------------------
                    // 1. IDLE / EVENT INGESTION
                    // ---------------------------------------------------------
                    ST_IDLE: begin
                        error_valid <= 1'b0;
                        if (event_valid && event_ready) begin
                            cur_evt        <= dec_evt;
                            reg_is_add     <= dec_is_add;
                            reg_is_exec    <= dec_is_exec;
                            reg_is_cancel  <= dec_is_cancel;
                            reg_is_delete  <= dec_is_delete;
                            reg_is_replace <= dec_is_replace;

                            if (dec_error) begin
                                // Immediate format failure
                                error_valid <= 1'b1;
                                error_code  <= dec_err_code;
                                if (eff_fail_stop) begin
                                    book_valid <= 1'b0;
                                    state      <= ST_FAIL_STOP;
                                end else begin
                                    state      <= ST_IDLE;
                                end
                            end else if (dec_price_oow) begin
                                // Out of window price failure
                                error_valid <= 1'b1;
                                error_code  <= FAIL_PRICE_OOW;
                                if (eff_fail_stop) begin
                                    book_valid <= 1'b0;
                                    state      <= ST_FAIL_STOP;
                                end else begin
                                    state      <= ST_IDLE;
                                end
                            end else begin
                                case (dec_evt[`EVT_OP_SLICE])
                                    OP_ADD:     state <= ST_ADD_C1;
                                    OP_EXECUTE,
                                    OP_CANCEL,
                                    OP_DELETE:  state <= ST_ECD_C1;
                                    OP_REPLACE: state <= ST_REP_C1;
                                    default: begin
                                        error_valid <= 1'b1;
                                        error_code  <= FAIL_INVALID_OP;
                                        if (eff_fail_stop) begin
                                            book_valid <= 1'b0;
                                            state      <= ST_FAIL_STOP;
                                        end else begin
                                            state      <= ST_IDLE;
                                        end
                                    end
                                endcase
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // 2. ADD OPERATION SCHEDULE (C1..C6)
                    // ---------------------------------------------------------
                    ST_ADD_C1: begin
                        // Prefetch reads across all structures
                        hash_rd_en          <= 1'b1;
                        hash_rd_set         <= hash_oid(cur_evt_oid);
                        hash_lookup_key     <= cur_evt_oid;

                        free_rd_top_en      <= 1'b1;

                        price_rd_en         <= 1'b1;
                        price_rd_addr       <= {cur_evt_side, cur_evt_pidx};

                        occ_leaf_rd_en      <= 1'b1;
                        occ_leaf_rd_side    <= cur_evt_side;
                        occ_leaf_rd_word_idx<= cur_evt_pidx[12:5];

                        state <= ST_ADD_C2;
                    end

                    ST_ADD_C2: begin
                        // Hash and free list read results ready on next edge
                        state <= ST_ADD_C3;
                    end

                    ST_ADD_C3: begin
                        // Validate hash match and capacity
                        if (hash_match_hit) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_DUP_OID;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else if (free_empty) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_NO_SLOT;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else if (hash_bucket_full) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_HASH_FULL;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else begin
                            // Latch allocation targets
                            lat_slot      <= free_top_slot;
                            lat_way       <= hash_free_way_idx;
                            lat_is_stash  <= !hash_free_way_avail && hash_free_stash_avail;
                            lat_stash_idx <= hash_free_stash_idx;
                            state         <= ST_ADD_C4;
                        end
                    end

                    ST_ADD_C4: begin
                        // Price RAM read data is now valid (Latency 3 from C1)
                        if (price_rd_valid) begin
                            // Overflow check: 32-bit addition carry
                            if ((price_rd_data + cur_evt_shares) < price_rd_data) begin
                                error_valid <= 1'b1;
                                error_code  <= FAIL_QTY_OVF;
                                if (eff_fail_stop) begin
                                    book_valid <= 1'b0;
                                    state      <= ST_FAIL_STOP;
                                end else begin
                                    state      <= ST_IDLE;
                                end
                            end else begin
                                lat_new_level_qty <= price_rd_data + cur_evt_shares;
                                state             <= ST_ADD_C5;
                            end
                        end
                    end

                    ST_ADD_C5: begin
                        // ATOMIC COMMIT POINT
                        // Hash table entry write
                        if (lat_is_stash) begin
                            hash_wr_stash_en  <= 1'b1;
                            hash_wr_stash_idx <= lat_stash_idx;
                            hash_wr_slot      <= lat_slot;
                            hash_wr_key       <= cur_evt_oid;
                        end else begin
                            hash_wr_way_en    <= 1'b1;
                            hash_wr_set       <= hash_oid(cur_evt_oid);
                            hash_wr_way_idx   <= lat_way;
                            hash_wr_slot      <= lat_slot;
                            hash_wr_key       <= cur_evt_oid;
                        end

                        // Slot table entry write
                        slot_wr_en   <= 1'b1;
                        slot_wr_addr <= lat_slot;
                        slot_wr_data <= {1'b1, cur_evt_side, cur_evt_pidx, cur_evt_shares};

                        // Free list pop
                        free_pop_commit <= 1'b1;

                        // Price RAM level quantity write
                        price_wr_en   <= 1'b1;
                        price_wr_addr <= {cur_evt_side, cur_evt_pidx};
                        price_wr_data <= lat_new_level_qty;

                        // Occupancy mask set
                        occ_leaf_upd_en      <= 1'b1;
                        occ_leaf_upd_side    <= cur_evt_side;
                        occ_leaf_upd_pidx    <= cur_evt_pidx;
                        occ_leaf_upd_bit_val <= 1'b1;

                        // Direct BBO Fast Path update
                        bbo_direct_upd_en <= 1'b1;
                        bbo_direct_side   <= cur_evt_side;
                        bbo_direct_pidx   <= cur_evt_pidx;
                        bbo_direct_qty    <= lat_new_level_qty;

                        state <= ST_ADD_C6;
                    end

                    ST_ADD_C6: begin
                        event_done <= 1'b1;
                        state      <= ST_IDLE;
                    end

                    // ---------------------------------------------------------
                    // 3. EXECUTE / CANCEL / DELETE SCHEDULE (C1..C10)
                    // ---------------------------------------------------------
                    ST_ECD_C1: begin
                        hash_rd_en      <= 1'b1;
                        hash_rd_set     <= hash_oid(cur_evt_oid);
                        hash_lookup_key <= cur_evt_oid;
                        state           <= ST_ECD_C2;
                    end

                    ST_ECD_C2: begin
                        state <= ST_ECD_C3;
                    end

                    ST_ECD_C3: begin
                        if (!hash_match_hit) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_MISSING_OID;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else begin
                            lat_slot      <= hash_match_slot;
                            lat_way       <= hash_match_way;
                            lat_is_stash  <= hash_match_is_stash;
                            lat_stash_idx <= hash_match_stash_idx;

                            // Read active slot table (1 cycle latency)
                            slot_rd_en   <= 1'b1;
                            slot_rd_addr <= hash_match_slot;
                            state        <= ST_ECD_C4;
                        end
                    end

                    ST_ECD_C4: begin
                        // Wait 1 cycle for slot table read data to latch
                        state <= ST_ECD_C5;
                    end

                    ST_ECD_C5: begin
                        // Slot data is now valid
                        lat_ord_side   <= slot_rd_side;
                        lat_ord_pidx   <= slot_rd_pidx;
                        lat_ord_shares <= slot_rd_shares;

                        // Calculate reduction amount
                        if (reg_is_delete) begin
                            lat_deduct_shares <= slot_rd_shares;
                            lat_rem_shares    <= 32'd0;
                            lat_is_kill       <= 1'b1;
                            price_rd_en       <= 1'b1;
                            price_rd_addr     <= {slot_rd_side, slot_rd_pidx};
                            state             <= ST_ECD_C6;
                        end else begin
                            lat_deduct_shares <= cur_evt_shares;
                            if (cur_evt_shares > slot_rd_shares) begin
                                error_valid <= 1'b1;
                                error_code  <= FAIL_QTY_UF;
                                if (eff_fail_stop) begin
                                    book_valid <= 1'b0;
                                    state      <= ST_FAIL_STOP;
                                end else begin
                                    state      <= ST_IDLE;
                                end
                            end else begin
                                lat_rem_shares <= slot_rd_shares - cur_evt_shares;
                                lat_is_kill    <= (slot_rd_shares == cur_evt_shares);
                                price_rd_en    <= 1'b1;
                                price_rd_addr  <= {slot_rd_side, slot_rd_pidx};
                                state          <= ST_ECD_C6;
                            end
                        end
                    end

                    ST_ECD_C6: state <= ST_ECD_C7;
                    ST_ECD_C7: state <= ST_ECD_C8;

                    ST_ECD_C8: begin
                        // Price RAM data valid (Latency 3 from C5)
                        if (price_rd_valid) begin
                            if (lat_deduct_shares > price_rd_data) begin
                                error_valid <= 1'b1;
                                error_code  <= FAIL_QTY_UF;
                                if (eff_fail_stop) begin
                                    book_valid <= 1'b0;
                                    state      <= ST_FAIL_STOP;
                                end else begin
                                    state      <= ST_IDLE;
                                end
                            end else begin
                                lat_new_level_qty   <= price_rd_data - lat_deduct_shares;
                                lat_level_zero      <= (price_rd_data == lat_deduct_shares);
                                lat_triggers_search <= bbo_triggers_search && (price_rd_data == lat_deduct_shares);
                                state               <= ST_ECD_C9;
                            end
                        end
                    end

                    ST_ECD_C9: begin
                        // COMMIT POINT
                        // 1. Update slot table
                        slot_wr_en   <= 1'b1;
                        slot_wr_addr <= lat_slot;
                        slot_wr_data <= {!lat_is_kill, lat_ord_side, lat_ord_pidx, lat_rem_shares};

                        // 2. Update price level RAM
                        price_wr_en   <= 1'b1;
                        price_wr_addr <= {lat_ord_side, lat_ord_pidx};
                        price_wr_data <= lat_new_level_qty;

                        // 3. Clear occupancy bit if level emptied
                        if (lat_level_zero) begin
                            occ_leaf_upd_en      <= 1'b1;
                            occ_leaf_upd_side    <= lat_ord_side;
                            occ_leaf_upd_pidx    <= lat_ord_pidx;
                            occ_leaf_upd_bit_val <= 1'b0;
                        end

                        // 4. Invalidate hash and reclaim slot if order died
                        if (lat_is_kill) begin
                            if (lat_is_stash) begin
                                hash_inv_stash_en  <= 1'b1;
                                hash_inv_stash_idx <= lat_stash_idx;
                            end else begin
                                hash_inv_way_en    <= 1'b1;
                                hash_inv_set       <= hash_oid(cur_evt_oid);
                                hash_inv_way_idx   <= lat_way;
                            end

                            free_push_en   <= 1'b1;
                            free_push_slot <= lat_slot;
                        end

                        // 5. BBO update (Fast path or trigger search)
                        if (!lat_triggers_search) begin
                            bbo_direct_upd_en <= 1'b1;
                            bbo_direct_side   <= lat_ord_side;
                            bbo_direct_pidx   <= lat_ord_pidx;
                            bbo_direct_qty    <= lat_new_level_qty;
                        end

                        state <= ST_ECD_C10;
                    end

                    ST_ECD_C10: begin
                        if (lat_triggers_search) begin
                            search_target_side <= lat_ord_side;
                            state              <= ST_SEARCH_START;
                        end else begin
                            event_done <= 1'b1;
                            state      <= ST_IDLE;
                        end
                    end

                    // ---------------------------------------------------------
                    // 4. REPLACE OPERATION SCHEDULE (C1..C12)
                    // ---------------------------------------------------------
                    ST_REP_C1: begin
                        // Lookup old OID
                        hash_rd_en      <= 1'b1;
                        hash_rd_set     <= hash_oid(cur_evt_oid);
                        hash_lookup_key <= cur_evt_oid;
                        state           <= ST_REP_C2;
                    end

                    ST_REP_C2: state <= ST_REP_C3;

                    ST_REP_C3: begin
                        if (!hash_match_hit) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_MISSING_OID;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else begin
                            rep_slot          <= hash_match_slot;
                            rep_old_way       <= hash_match_way;
                            rep_old_is_stash  <= hash_match_is_stash;
                            rep_old_stash_idx <= hash_match_stash_idx;

                            // Lookup new NOID (must NOT exist)
                            hash_rd_en      <= 1'b1;
                            hash_rd_set     <= hash_oid(cur_evt_noid);
                            hash_lookup_key <= cur_evt_noid;

                            // Read slot table
                            slot_rd_en   <= 1'b1;
                            slot_rd_addr <= hash_match_slot;

                            state <= ST_REP_C4;
                        end
                    end

                    ST_REP_C4: state <= ST_REP_C5;

                    ST_REP_C5: begin
                        // Check new NOID duplicate
                        if (hash_match_hit) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_DUP_OID;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else if (hash_bucket_full) begin
                            error_valid <= 1'b1;
                            error_code  <= FAIL_HASH_FULL;
                            if (eff_fail_stop) begin
                                book_valid <= 1'b0;
                                state      <= ST_FAIL_STOP;
                            end else begin
                                state      <= ST_IDLE;
                            end
                        end else begin
                            rep_new_way       <= hash_free_way_idx;
                            rep_new_use_stash <= !hash_free_way_avail && hash_free_stash_avail;
                            rep_new_stash_idx <= hash_free_stash_idx;

                            rep_ord_side      <= slot_rd_side;
                            rep_old_pidx      <= slot_rd_pidx;
                            rep_old_shares    <= slot_rd_shares;
                            rep_new_pidx      <= cur_evt_pidx;
                            rep_new_shares    <= cur_evt_shares;

                            // Read Price RAM for old price level
                            price_rd_en   <= 1'b1;
                            price_rd_addr <= {slot_rd_side, slot_rd_pidx};

                            state <= ST_REP_C6;
                        end
                    end

                    ST_REP_C6: begin
                        // Read Price RAM for new price level
                        price_rd_en   <= 1'b1;
                        price_rd_addr <= {rep_ord_side, rep_new_pidx};
                        state         <= ST_REP_C7;
                    end

                    ST_REP_C7: state <= ST_REP_C8;

                    ST_REP_C8: begin
                        // Old Price RAM data valid
                        if (price_rd_valid) begin
                            rep_price_old_qty <= price_rd_data;
                            if (rep_old_shares > price_rd_data) begin
                                error_valid <= 1'b1;
                                error_code  <= FAIL_QTY_UF;
                                if (eff_fail_stop) begin
                                    book_valid <= 1'b0;
                                    state      <= ST_FAIL_STOP;
                                end else begin
                                    state      <= ST_IDLE;
                                end
                            end else begin
                                rep_new_old_level_qty <= price_rd_data - rep_old_shares;
                                rep_old_level_zero    <= (price_rd_data == rep_old_shares);
                                rep_triggers_search   <= bbo_triggers_search && (price_rd_data == rep_old_shares);
                                state                 <= ST_REP_C9;
                            end
                        end
                    end

                    ST_REP_C9: begin
                        // New Price RAM data valid
                        if (price_rd_valid) begin
                            rep_price_new_qty <= price_rd_data;
                            // If same level, net arithmetic on price_old
                            if (rep_old_pidx == rep_new_pidx) begin
                                if ((rep_new_old_level_qty + rep_new_shares) < rep_new_old_level_qty) begin
                                    error_valid <= 1'b1;
                                    error_code  <= FAIL_QTY_OVF;
                                    if (eff_fail_stop) begin
                                        book_valid <= 1'b0;
                                        state      <= ST_FAIL_STOP;
                                    end else begin
                                        state      <= ST_IDLE;
                                    end
                                end else begin
                                    rep_new_new_level_qty <= rep_new_old_level_qty + rep_new_shares;
                                    state                 <= ST_REP_C10;
                                end
                            end else begin
                                if ((price_rd_data + rep_new_shares) < price_rd_data) begin
                                    error_valid <= 1'b1;
                                    error_code  <= FAIL_QTY_OVF;
                                    if (eff_fail_stop) begin
                                        book_valid <= 1'b0;
                                        state      <= ST_FAIL_STOP;
                                    end else begin
                                        state      <= ST_IDLE;
                                    end
                                end else begin
                                    rep_new_new_level_qty <= price_rd_data + rep_new_shares;
                                    state                 <= ST_REP_C10;
                                end
                            end
                        end
                    end

                    ST_REP_C10: begin
                        // COMMIT BEAT K1 (Old level removal & hash invalidation)
                        if (rep_old_is_stash) begin
                            hash_inv_stash_en  <= 1'b1;
                            hash_inv_stash_idx <= rep_old_stash_idx;
                        end else begin
                            hash_inv_way_en    <= 1'b1;
                            hash_inv_set       <= hash_oid(cur_evt_oid);
                            hash_inv_way_idx   <= rep_old_way;
                        end

                        if (rep_old_pidx != rep_new_pidx) begin
                            price_wr_en   <= 1'b1;
                            price_wr_addr <= {rep_ord_side, rep_old_pidx};
                            price_wr_data <= rep_new_old_level_qty;

                            if (rep_old_level_zero) begin
                                occ_leaf_upd_en      <= 1'b1;
                                occ_leaf_upd_side    <= rep_ord_side;
                                occ_leaf_upd_pidx    <= rep_old_pidx;
                                occ_leaf_upd_bit_val <= 1'b0;
                            end
                        end

                        state <= ST_REP_C11;
                    end

                    ST_REP_C11: begin
                        // COMMIT BEAT K2 (New key insert, slot update, new price write)
                        if (rep_new_use_stash) begin
                            hash_wr_stash_en  <= 1'b1;
                            hash_wr_stash_idx <= rep_new_stash_idx;
                            hash_wr_slot      <= rep_slot;
                            hash_wr_key       <= cur_evt_noid;
                        end else begin
                            hash_wr_way_en    <= 1'b1;
                            hash_wr_set       <= hash_oid(cur_evt_noid);
                            hash_wr_way_idx   <= rep_new_way;
                            hash_wr_slot      <= rep_slot;
                            hash_wr_key       <= cur_evt_noid;
                        end

                        // Slot reuse with new price & shares
                        slot_wr_en   <= 1'b1;
                        slot_wr_addr <= rep_slot;
                        slot_wr_data <= {1'b1, rep_ord_side, rep_new_pidx, rep_new_shares};

                        // New price RAM write
                        price_wr_en   <= 1'b1;
                        price_wr_addr <= {rep_ord_side, rep_new_pidx};
                        price_wr_data <= rep_new_new_level_qty;

                        // New occupancy bit set
                        occ_leaf_upd_en      <= 1'b1;
                        occ_leaf_upd_side    <= rep_ord_side;
                        occ_leaf_upd_pidx    <= rep_new_pidx;
                        occ_leaf_upd_bit_val <= 1'b1;

                        // BBO update decision
                        if (rep_triggers_search && (rep_old_pidx != rep_new_pidx)) begin
                            // Old level was best and is now 0; evaluate search
                            search_target_side <= rep_ord_side;
                            state              <= ST_SEARCH_START;
                        end else begin
                            bbo_direct_upd_en <= 1'b1;
                            bbo_direct_side   <= rep_ord_side;
                            bbo_direct_pidx   <= rep_new_pidx;
                            bbo_direct_qty    <= rep_new_new_level_qty;
                            state             <= ST_REP_C12;
                        end
                    end

                    ST_REP_C12: begin
                        event_done <= 1'b1;
                        state      <= ST_IDLE;
                    end

                    // ---------------------------------------------------------
                    // 5. OCCUPANCY SEARCH PIPELINE
                    // ---------------------------------------------------------
                    ST_SEARCH_START: begin
                        occ_search_start <= 1'b1;
                        occ_search_side  <= search_target_side;
                        state            <= ST_SEARCH_WAIT;
                    end

                    ST_SEARCH_WAIT: begin
                        if (occ_search_done) begin
                            found_search_valid <= occ_search_valid;
                            found_search_pidx  <= occ_search_pidx;
                            if (occ_search_valid) begin
                                // Read new best price level quantity
                                price_rd_en   <= 1'b1;
                                price_rd_addr <= {search_target_side, occ_search_pidx};
                                state         <= ST_SEARCH_PRICER;
                            end else begin
                                // Side is now completely empty
                                bbo_search_upd_en <= 1'b1;
                                bbo_search_side   <= search_target_side;
                                bbo_search_valid  <= 1'b0;
                                bbo_search_pidx   <= 0;
                                bbo_search_qty    <= 32'd0;
                                state             <= ST_DONE;
                            end
                        end
                    end

                    ST_SEARCH_PRICER: state <= ST_SEARCH_PRICE1;
                    ST_SEARCH_PRICE1: state <= ST_SEARCH_PRICE2;

                    ST_SEARCH_PRICE2: begin
                        if (price_rd_valid) begin
                            bbo_search_upd_en <= 1'b1;
                            bbo_search_side   <= search_target_side;
                            bbo_search_valid  <= 1'b1;
                            bbo_search_pidx   <= found_search_pidx;
                            bbo_search_qty    <= price_rd_data;
                            state             <= ST_DONE;
                        end
                    end

                    ST_DONE: begin
                        event_done <= 1'b1;
                        state      <= ST_IDLE;
                    end

                    // ---------------------------------------------------------
                    // 6. FAIL-STOP TERMINAL STATE
                    // ---------------------------------------------------------
                    ST_FAIL_STOP: begin
                        // Halts intake until external reset or cfg_clear
                        // State remains here, book_valid=0, error_code latched
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
