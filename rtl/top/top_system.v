`timescale 1ns / 1ps

// Nexys A7-100T limit order book: Ethernet and keyboard orders in,
// order book in the middle, VGA / UART / LEDs out.
// Clock domains: eth (50 MHz RMII), core (50 MHz), ui (25 MHz), pixel (74.25 MHz).
module top_system #(
    parameter [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter [31:0] DEFAULT_TICK       = 32'd1000,
    parameter [15:0] DEFAULT_LOCATE     = 16'd1,
    parameter [47:0] DEST_MAC           = 48'd0,
    parameter [31:0] DEST_IP            = 32'd0
) (
    input  wire        clk,             // 100 MHz oscillator
    input  wire        reset,           // CPU_RESETN, active low

    input  wire [1:0]  sw,              // SW14, SW15: seven-segment source
    input  wire        ps2_clk,
    input  wire        ps2_data,

    output wire [15:0] led,
    output wire [7:0]  an,
    output wire [6:0]  seg,
    output wire        dp,

    output wire        eth_refclk,
    output wire        eth_rstn,
    input  wire        eth_crsdv,
    input  wire        eth_rxerr,
    input  wire [1:0]  eth_rxd,

    output wire        uart_txd_out,
    input  wire        uart_rxd_in,

    output wire        vga_hs,
    output wire        vga_vs,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);
    // ---- clocks and resets ------------------------------------------------
    wire clk_core, clk_eth, clk_eth_phy, clk_ui;
    wire rst_core_n, rst_eth_n, rst_ui_n, mmcm_locked;

    clk_rst_mgr u_clk_mgr (
        .clk_100mhz_in(clk), .rst_btn_n(reset),
        .clk_core(clk_core), .clk_eth(clk_eth), .clk_eth_phy(clk_eth_phy), .clk_vga(clk_ui),
        .rst_core_n(rst_core_n), .rst_eth_n(rst_eth_n), .rst_vga_n(rst_ui_n),
        .phy_rst_n(eth_rstn), .mmcm_locked(mmcm_locked)
    );
    phy_refclk_out u_phy_refclk (.clk_phy(clk_eth_phy), .clk_eth(clk_eth), .refclk(eth_refclk));

    // ---- network input ----------------------------------------------------
    wire         net_valid, net_ready, feed_loss;
    wire [255:0] net_data;
    wire [351:0] net_diag;
    wire [31:0]  ip_csum_errors;
    wire [159:0] pipe_stats;
    wire [31:0]  cfg_price_base, cfg_tick;
    wire [15:0]  cfg_locate;
    wire         cfg_ready;

    net_ingest #(
        .DEFAULT_PRICE_BASE(DEFAULT_PRICE_BASE), .DEFAULT_TICK(DEFAULT_TICK),
        .DEFAULT_LOCATE(DEFAULT_LOCATE), .DEST_MAC(DEST_MAC), .DEST_IP(DEST_IP)
    ) u_ingest (
        .clk_eth(clk_eth), .rst_eth_n(rst_eth_n),
        .clk_core(clk_core), .rst_core_n(rst_core_n),
        .eth_crsdv(eth_crsdv), .eth_rxerr(eth_rxerr), .eth_rxd(eth_rxd),
        .cfg_core({cfg_locate, cfg_price_base, cfg_tick}), .cfg_ready(cfg_ready),
        .evt_valid(net_valid), .evt_data(net_data), .evt_ready(net_ready),
        .feed_loss(feed_loss), .diag(net_diag),
        .ip_csum_errors(ip_csum_errors), .pipe_stats(pipe_stats)
    );

    // ---- order sources -> order book --------------------------------------
    wire         ui_valid, ui_ready, evt_valid, evt_ready;
    wire [255:0] ui_data, evt_data;
    wire [31:0]  local_done_count;
    wire         local_done_valid;
    wire [7:0]   local_done_error;
    wire [45:0]  event_meta;
    wire         lob_event_done, lob_book_valid, lob_init_done, lob_busy;
    wire         lob_error_valid, lob_bid_valid, lob_ask_valid;
    wire [7:0]   lob_error_code;
    wire [11:0]  lob_active_orders;
    wire [315:0] lob_storage_trace;
    wire [31:0]  lob_bid_price, lob_bid_qty, lob_ask_price, lob_ask_qty;

    order_merge u_order_merge (
        .clk_core(clk_core), .rst_core_n(rst_core_n),
        .net_valid(net_valid), .net_data(net_data), .net_ready(net_ready),
        .clk_ui(clk_ui), .rst_ui_n(rst_ui_n),
        .ui_valid(ui_valid), .ui_data(ui_data), .ui_ready(ui_ready),
        .evt_valid(evt_valid), .evt_data(evt_data), .evt_ready(evt_ready),
        .lob_event_done(lob_event_done), .lob_book_valid(lob_book_valid),
        .lob_error_code(lob_error_code),
        .local_done_count(local_done_count), .local_done_valid(local_done_valid),
        .local_done_error(local_done_error), .event_meta(event_meta)
    );

    wire [10:0]  slot_addr, free_addr;
    wire [9:0]   hash_set;
    wire [2:0]   stash_idx;
    wire [13:0]  price_addr;
    wire [46:0]  slot_data;
    wire [607:0] hash_ways;
    wire [75:0]  stash_data;
    wire [31:0]  price_data;
    wire [10:0]  free_data;
    wire [11:0]  free_count;
    wire         level_delta_valid, level_delta_inc, accel_enable;
    wire [13:0]  level_delta_addr;

    lob_core #(
        .DEFAULT_PRICE_BASE(DEFAULT_PRICE_BASE), .DEFAULT_TICK(DEFAULT_TICK),
        .DEFAULT_FAIL_STOP_EN(1'b1)
    ) u_lob_core (
        .clk(clk_core), .rst_n(rst_core_n),
        .event_valid(evt_valid), .event_ready(evt_ready), .event_data(evt_data),
        .cfg_clear(1'b0), .cfg_fail_stop_en(1'b1), .run_enable(accel_enable),
        .feed_fault(feed_loss), .cfg_price_base(cfg_price_base), .cfg_tick(cfg_tick),
        .book_valid(lob_book_valid), .init_done(lob_init_done), .busy(lob_busy),
        .error_valid(lob_error_valid), .error_code(lob_error_code),
        .active_order_count(lob_active_orders), .event_done(lob_event_done),
        .storage_trace(lob_storage_trace),
        .best_bid_valid(lob_bid_valid), .best_bid_price(lob_bid_price), .best_bid_qty(lob_bid_qty),
        .best_ask_valid(lob_ask_valid), .best_ask_price(lob_ask_price), .best_ask_qty(lob_ask_qty),
        .display_clk(clk_ui),
        .display_slot_addr(slot_addr), .display_slot_data(slot_data),
        .display_hash_set(hash_set), .display_hash_ways(hash_ways),
        .display_stash_idx(stash_idx), .display_stash_data(stash_data),
        .display_price_addr(price_addr), .display_price_data(price_data),
        .display_free_addr(free_addr), .display_free_data(free_data),
        .display_free_count(free_count),
        .level_count_delta_valid(level_delta_valid), .level_count_delta_inc(level_delta_inc),
        .level_count_delta_addr(level_delta_addr)
    );

    wire [31:0] core_event_count;
    event_counter u_core_events (
        .clk(clk_core), .rst_n(rst_core_n), .inc(lob_event_done), .count(core_event_count)
    );

    // ---- supervisor CPU ---------------------------------------------------
    wire        uart_req_valid, uart_req_write, uart_rsp_valid;
    wire [31:0] uart_req_addr, uart_req_wdata, uart_rsp_rdata, cpu_pc;

    cpu_system u_cpu_system (
        .clk(clk_core), .rst_n(rst_core_n), .sw(sw), .mmcm_locked(mmcm_locked),
        .cfg_ready(cfg_ready), .book_valid(lob_book_valid), .init_done(lob_init_done),
        .busy(lob_busy), .error_valid(lob_error_valid), .error_code(lob_error_code),
        .active_order_count(lob_active_orders), .event_done(lob_event_done),
        .event_ready(evt_ready),
        .best_bid_valid(lob_bid_valid), .best_bid_price(lob_bid_price), .best_bid_qty(lob_bid_qty),
        .best_ask_valid(lob_ask_valid), .best_ask_price(lob_ask_price), .best_ask_qty(lob_ask_qty),
        .cfg_price_base(cfg_price_base), .cfg_tick(cfg_tick),
        .cfg_stock_locate(cfg_locate), .accel_enable(accel_enable),
        .net_diag(net_diag),
        .uart_req_valid(uart_req_valid), .uart_req_write(uart_req_write),
        .uart_req_addr(uart_req_addr), .uart_req_wdata(uart_req_wdata),
        .uart_rsp_valid(uart_rsp_valid), .uart_rsp_rdata(uart_rsp_rdata),
        .pc(cpu_pc)
    );

    // ---- history memories and UI-domain status ----------------------------
    wire [11:0]  level_count;
    wire [174:0] quote_data, ui_book;
    wire [393:0] event_history;
    wire [31:0]  history_meta, ui_history;
    wire [6:0]   quote_addr;
    wire [7:0]   event_addr;
    wire [127:0] ui_net;
    wire [95:0]  ui_pipe;
    wire [7:0]   ui_error;
    wire [63:0]  ui_config;
    wire [40:0]  ui_local_done;

    book_views u_views (
        .core_clk(clk_core), .core_rst_n(rst_core_n),
        .event_done(lob_event_done), .completed_count(core_event_count),
        .storage_trace(lob_storage_trace), .event_meta(event_meta),
        .book_valid(lob_book_valid),
        .bid_valid(lob_bid_valid), .bid_price(lob_bid_price), .bid_qty(lob_bid_qty),
        .ask_valid(lob_ask_valid), .ask_price(lob_ask_price), .ask_qty(lob_ask_qty),
        .active_orders(lob_active_orders),
        .level_delta_valid(level_delta_valid), .level_delta_inc(level_delta_inc),
        .level_delta_addr(level_delta_addr),
        .read_clk(clk_ui), .level_addr(price_addr), .level_count(level_count),
        .quote_addr(quote_addr), .quote_data(quote_data),
        .event_addr(event_addr), .event_data(event_history),
        .history_meta(history_meta)
    );

    status_to_ui #(.DEFAULT_PRICE_BASE(DEFAULT_PRICE_BASE), .DEFAULT_TICK(DEFAULT_TICK)) u_status_to_ui (
        .clk_core(clk_core), .rst_core_n(rst_core_n), .clk_ui(clk_ui), .rst_ui_n(rst_ui_n),
        .book_valid(lob_book_valid), .bid_valid(lob_bid_valid),
        .bid_price(lob_bid_price), .bid_qty(lob_bid_qty),
        .ask_valid(lob_ask_valid), .ask_price(lob_ask_price), .ask_qty(lob_ask_qty),
        .active_orders(lob_active_orders), .event_count(core_event_count),
        .error_code(lob_error_code), .price_base(cfg_price_base), .tick(cfg_tick),
        .net_diag(net_diag), .pipe_stats(pipe_stats), .history_meta(history_meta),
        .local_done_count(local_done_count), .local_done_valid(local_done_valid),
        .local_done_error(local_done_error),
        .book(ui_book), .net(ui_net), .pipe(ui_pipe), .error(ui_error),
        .settings(ui_config), .history(ui_history), .local_done(ui_local_done)
    );

    // ---- UART and display -------------------------------------------------
    wire         readback_active;
    wire [7:0]   readback_kind, readback_hash_valid;
    wire [13:0]  readback_addr;
    wire [9:0]   readback_scan_set;
    wire [607:0] readback_data;

    uart_system u_uart (
        .clk_core(clk_core), .rst_core_n(rst_core_n), .clk_ui(clk_ui), .rst_ui_n(rst_ui_n),
        .uart_rxd(uart_rxd_in), .uart_txd(uart_txd_out),
        .bus_req_valid(uart_req_valid), .bus_req_write(uart_req_write),
        .bus_req_addr(uart_req_addr), .bus_req_wdata(uart_req_wdata),
        .bus_rsp_valid(uart_rsp_valid), .bus_rsp_rdata(uart_rsp_rdata),
        .lob_event_done(lob_event_done), .book_valid(lob_book_valid),
        .error_code(lob_error_code), .active_orders(lob_active_orders),
        .best_bid_price(lob_bid_price), .best_bid_qty(lob_bid_qty),
        .best_ask_price(lob_ask_price), .best_ask_qty(lob_ask_qty),
        .storage_trace(lob_storage_trace),
        .price_base(cfg_price_base), .price_tick(cfg_tick),
        .net_diag(net_diag), .ip_csum_errors(ip_csum_errors),
        .pipe_stats(pipe_stats), .done_events(core_event_count),
        .readback_active(readback_active), .readback_kind(readback_kind),
        .readback_addr(readback_addr), .readback_scan_set(readback_scan_set),
        .readback_hash_valid(readback_hash_valid), .readback_data(readback_data)
    );

    display_system #(.DEFAULT_PRICE_BASE(DEFAULT_PRICE_BASE), .DEFAULT_TICK(DEFAULT_TICK)) u_display (
        .clk_100(clk), .rst_100_n(reset), .clk(clk_ui), .rst_n(rst_ui_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .event_valid(ui_valid), .event_data(ui_data), .event_ready(ui_ready),
        .book(ui_book), .net(ui_net), .pipe(ui_pipe), .error(ui_error),
        .settings(ui_config), .history(ui_history), .local_done(ui_local_done),
        .readback_active(readback_active), .readback_kind(readback_kind),
        .readback_addr(readback_addr), .readback_scan_set(readback_scan_set),
        .slot_addr(slot_addr), .hash_set(hash_set), .stash_idx(stash_idx),
        .price_addr(price_addr), .free_addr(free_addr),
        .quote_addr(quote_addr), .event_addr(event_addr),
        .slot_data(slot_data), .hash_ways(hash_ways), .stash_data(stash_data),
        .price_data(price_data), .free_data(free_data), .level_count(level_count),
        .quote_data(quote_data), .event_history(event_history),
        .readback_data(readback_data), .hash_valid(readback_hash_valid),
        .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b)
    );

    // ---- board indicators -------------------------------------------------
    board_status u_board_status (
        .clk(clk_core), .rst_n(rst_core_n), .sw(sw),
        .mmcm_locked(mmcm_locked), .eth_phy_rst_n(eth_rstn), .eth_crsdv(eth_crsdv),
        .init_done(lob_init_done), .book_valid(lob_book_valid),
        .bid_valid(lob_bid_valid), .ask_valid(lob_ask_valid), .busy(lob_busy),
        .error_valid(lob_error_valid), .error_code(lob_error_code),
        .event_pending(evt_valid), .net_diag(net_diag),
        .bid_price(lob_bid_price), .ask_price(lob_ask_price),
        .active_orders(lob_active_orders), .event_count(core_event_count),
        .cpu_pc(cpu_pc),
        .led(led), .an(an), .seg(seg), .dp(dp)
    );
endmodule
