`timescale 1ns / 1ps

// UART front end: periodic status line, CPU-visible TX window, and RAM readback.
// The readback engine runs in the UI clock domain next to the display RAM ports.
module uart_system (
    input  wire         clk_core,
    input  wire         rst_core_n,
    input  wire         clk_ui,
    input  wire         rst_ui_n,
    input  wire         uart_rxd,
    output wire         uart_txd,

    input  wire         bus_req_valid,
    input  wire         bus_req_write,
    input  wire [31:0]  bus_req_addr,
    input  wire [31:0]  bus_req_wdata,
    output wire         bus_rsp_valid,
    output wire [31:0]  bus_rsp_rdata,

    input  wire         lob_event_done,
    input  wire         book_valid,
    input  wire [7:0]   error_code,
    input  wire [11:0]  active_orders,
    input  wire [31:0]  best_bid_price,
    input  wire [31:0]  best_bid_qty,
    input  wire [31:0]  best_ask_price,
    input  wire [31:0]  best_ask_qty,
    input  wire [315:0] storage_trace,
    input  wire [31:0]  price_base,
    input  wire [31:0]  price_tick,
    input  wire [351:0] net_diag,
    input  wire [31:0]  ip_csum_errors,
    input  wire [159:0] pipe_stats,
    input  wire [31:0]  done_events,
    input  wire [75:0]  kbd_diag,

    // Readback RAM access (UI clock domain)
    output wire         readback_active,
    output wire [7:0]   readback_kind,
    output wire [13:0]  readback_addr,
    output wire [9:0]   readback_scan_set,
    input  wire [7:0]   readback_hash_valid,
    input  wire [607:0] readback_data
);
    wire        tx_valid, tx_ready, rsp_update, req_toggle;
    wire [7:0]  tx_byte, req_kind;
    wire [13:0] req_addr;
    wire [630:0] rsp_core;

    uart_readback #(.CLK_FREQ(50_000_000), .BAUD_RATE(115_200)) u_readback (
        .clk(clk_core), .rst_n(rst_core_n), .uart_rxd(uart_rxd),
        .req_toggle(req_toggle), .req_kind(req_kind), .req_addr(req_addr),
        .rsp_update(rsp_update), .rsp_payload(rsp_core),
        .tx_valid(tx_valid), .tx_byte(tx_byte), .tx_ready(tx_ready)
    );

    wire [22:0] req_ui;
    wire        req_update_ui;
    config_cdc #(.WIDTH(23), .RESET_VALUE(23'd0)) u_request_cdc (
        .src_clk(clk_core), .src_rst_n(rst_core_n),
        .src_data({req_toggle, req_kind, req_addr}), .src_busy(), .src_ready(),
        .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(req_ui), .dst_update(req_update_ui)
    );
    assign readback_kind = req_ui[21:14];
    assign readback_addr = req_ui[13:0];

    wire [630:0] rsp_ui;
    readback_engine u_engine (
        .clk(clk_ui), .rst_n(rst_ui_n), .req_update(req_update_ui), .req(req_ui),
        .hash_valid(readback_hash_valid), .data(readback_data),
        .active(readback_active), .scan_set(readback_scan_set), .rsp(rsp_ui)
    );

    config_cdc #(.WIDTH(631), .RESET_VALUE(631'd0)) u_response_cdc (
        .src_clk(clk_ui), .src_rst_n(rst_ui_n), .src_data(rsp_ui),
        .src_busy(), .src_ready(), .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(rsp_core), .dst_update(rsp_update)
    );

    uart_telemetry #(.CLK_FREQ(50_000_000), .BAUD_RATE(115_200)) u_telemetry (
        .clk(clk_core), .rst_n(rst_core_n),
        .bus_req_valid(bus_req_valid), .bus_req_write(bus_req_write),
        .bus_req_addr(bus_req_addr), .bus_req_wdata(bus_req_wdata),
        .bus_rsp_valid(bus_rsp_valid), .bus_rsp_rdata(bus_rsp_rdata),
        .hw_telem_trigger(lob_event_done),
        .best_bid_price(best_bid_price), .best_bid_qty(best_bid_qty),
        .best_ask_price(best_ask_price), .best_ask_qty(best_ask_qty),
        .active_orders(active_orders), .book_valid(book_valid), .error_code(error_code),
        .crc_errors(net_diag[319:288]), .udp_checksum_errors(net_diag[63:32]),
        .ip_checksum_errors(ip_csum_errors),
        .pipe_rx_frames(pipe_stats[159:128]), .pipe_udp_packets(pipe_stats[127:96]),
        .pipe_mold_msgs(pipe_stats[95:64]), .pipe_itch_events(pipe_stats[63:32]),
        .pipe_fifo_events(pipe_stats[31:0]), .pipe_done_events(done_events),
        .storage_trace(storage_trace),
        .price_base(price_base), .price_tick(price_tick),
        .kbd_diag(kbd_diag),
        .readback_valid(tx_valid), .readback_byte(tx_byte), .readback_ready(tx_ready),
        .uart_txd(uart_txd)
    );
endmodule
