`timescale 1ns / 1ps

// Memories that exist only for display and readback: orders per price level and
// the quote / event history rings.
module book_views (
    input  wire         core_clk,
    input  wire         core_rst_n,
    input  wire         event_done,
    input  wire [31:0]  completed_count,
    input  wire [315:0] storage_trace,
    input  wire [45:0]  event_meta,
    input  wire         book_valid,
    input  wire         bid_valid,
    input  wire [31:0]  bid_price,
    input  wire [31:0]  bid_qty,
    input  wire         ask_valid,
    input  wire [31:0]  ask_price,
    input  wire [31:0]  ask_qty,
    input  wire [11:0]  active_orders,

    input  wire         level_delta_valid,
    input  wire         level_delta_inc,
    input  wire [13:0]  level_delta_addr,

    input  wire         read_clk,
    input  wire [13:0]  level_addr,
    output wire [11:0]  level_count,
    input  wire [6:0]   quote_addr,
    output wire [174:0] quote_data,
    input  wire [7:0]   event_addr,
    output wire [393:0] event_data,
    output wire [31:0]  history_meta     // {quote count, event count, quote next, event next}, core domain
);
    lob_level_order_count u_levels (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .delta_valid(level_delta_valid), .delta_inc(level_delta_inc),
        .delta_addr(level_delta_addr), .init_done(),
        .read_clk(read_clk), .read_addr(level_addr), .read_count(level_count)
    );

    wire [7:0] quote_count;
    wire [8:0] event_count;
    wire [6:0] quote_next;
    wire [7:0] event_next;

    lob_display_journal u_display_journal (
        .core_clk(core_clk), .core_rst_n(core_rst_n),
        .event_done(event_done), .completed_count(completed_count),
        .storage_trace(storage_trace), .event_meta(event_meta),
        .book_valid(book_valid),
        .bid_valid(bid_valid), .bid_price(bid_price), .bid_qty(bid_qty),
        .ask_valid(ask_valid), .ask_price(ask_price), .ask_qty(ask_qty),
        .active_orders(active_orders), .read_clk(read_clk),
        .quote_read_addr(quote_addr), .quote_read_data(quote_data),
        .event_read_addr(event_addr), .event_read_data(event_data),
        .quote_count(quote_count), .event_count(event_count),
        .quote_next(quote_next), .event_next(event_next)
    );
    assign history_meta = {quote_count, event_count, quote_next, event_next};
endmodule
