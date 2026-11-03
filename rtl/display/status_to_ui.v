`timescale 1ns / 1ps

// Copies slow-changing core-domain status into the UI clock domain.
module status_to_ui #(
    parameter [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter [31:0] DEFAULT_TICK       = 32'd1000
) (
    input  wire         clk_core,
    input  wire         rst_core_n,
    input  wire         clk_ui,
    input  wire         rst_ui_n,

    input  wire         book_valid,
    input  wire         bid_valid,
    input  wire [31:0]  bid_price,
    input  wire [31:0]  bid_qty,
    input  wire         ask_valid,
    input  wire [31:0]  ask_price,
    input  wire [31:0]  ask_qty,
    input  wire [11:0]  active_orders,
    input  wire [31:0]  event_count,
    input  wire [7:0]   error_code,
    input  wire [31:0]  price_base,
    input  wire [31:0]  tick,
    input  wire [351:0] net_diag,
    input  wire [159:0] pipe_stats,
    input  wire [31:0]  history_meta,
    input  wire [31:0]  local_done_count,
    input  wire         local_done_valid,
    input  wire [7:0]   local_done_error,

    output wire [174:0] book,          // {book valid, bid valid, bid px/qty, ask valid, ask px/qty, orders, events}
    output wire [127:0] net,           // rx frames, crc errors, mold messages, sequence gaps
    output wire [95:0]  pipe,          // udp packets, itch events, fifo events
    output wire [7:0]   error,
    output wire [63:0]  settings,        // {price base, tick}
    output wire [31:0]  history,
    output wire [40:0]  local_done     // {count, valid, error}
);
    config_cdc #(.WIDTH(175)) u_book (
        .src_clk(clk_core), .src_rst_n(rst_core_n),
        .src_data({book_valid, bid_valid, bid_price, bid_qty, ask_valid, ask_price,
                   ask_qty, active_orders, event_count}),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(book), .dst_update()
    );
    config_cdc #(.WIDTH(128)) u_net (
        .src_clk(clk_core), .src_rst_n(rst_core_n), .src_data(net_diag[351:224]),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(net), .dst_update()
    );
    config_cdc #(.WIDTH(96)) u_pipe (
        .src_clk(clk_core), .src_rst_n(rst_core_n),
        .src_data({pipe_stats[127:96], pipe_stats[63:32], pipe_stats[31:0]}),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(pipe), .dst_update()
    );
    config_cdc #(.WIDTH(8)) u_error (
        .src_clk(clk_core), .src_rst_n(rst_core_n), .src_data(error_code),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(error), .dst_update()
    );
    config_cdc #(.WIDTH(64), .RESET_VALUE({DEFAULT_PRICE_BASE, DEFAULT_TICK})) u_config (
        .src_clk(clk_core), .src_rst_n(rst_core_n), .src_data({price_base, tick}),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(settings), .dst_update()
    );
    config_cdc #(.WIDTH(32)) u_history (
        .src_clk(clk_core), .src_rst_n(rst_core_n), .src_data(history_meta),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(history), .dst_update()
    );
    config_cdc #(.WIDTH(41)) u_local_done (
        .src_clk(clk_core), .src_rst_n(rst_core_n),
        .src_data({local_done_count, local_done_valid, local_done_error}),
        .src_busy(), .src_ready(), .dst_clk(clk_ui), .dst_rst_n(rst_ui_n),
        .dst_data(local_done), .dst_update()
    );
endmodule
