`timescale 1ns / 1ps

`include "lob_defines.vh"

// Merges network events and keyboard (local) events into one stream for the
// order book, and records the outcome of each local order.
module order_merge (
    input  wire         clk_core,
    input  wire         rst_core_n,

    input  wire         net_valid,
    input  wire [255:0] net_data,
    output wire         net_ready,

    input  wire         clk_ui,
    input  wire         rst_ui_n,
    input  wire         ui_valid,
    input  wire [255:0] ui_data,
    output wire         ui_ready,

    output wire         evt_valid,
    output wire [255:0] evt_data,
    input  wire         evt_ready,

    input  wire         lob_event_done,
    input  wire         lob_book_valid,
    input  wire [7:0]   lob_error_code,

    output reg  [31:0]  local_done_count,
    output reg          local_done_valid,
    output reg  [7:0]   local_done_error,
    output reg  [45:0]  event_meta      // side, shares, price index of the last accepted event
);
    wire         local_valid, local_ready, chosen_local;
    wire [255:0] local_data;

    async_event_fifo #(.DATA_WIDTH(256), .ADDR_WIDTH(2)) u_local_fifo (
        .wr_clk(clk_ui), .wr_rst_n(rst_ui_n),
        .wr_valid(ui_valid), .wr_data(ui_data), .wr_ready(ui_ready),
        .wr_full(), .wr_overflow(), .wr_count(),
        .rd_clk(clk_core), .rd_rst_n(rst_core_n),
        .rd_valid(local_valid), .rd_data(local_data), .rd_ready(local_ready),
        .rd_empty(), .rd_underflow(), .rd_count()
    );

    order_source_arbiter u_arbiter (
        .clk(clk_core), .rst_n(rst_core_n),
        .net_valid(net_valid), .net_data(net_data), .net_ready(net_ready),
        .local_valid(local_valid), .local_data(local_data), .local_ready(local_ready),
        .valid(evt_valid), .data(evt_data), .chosen_local(chosen_local), .ready(evt_ready)
    );

    reg active_local, done_delay;
    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            active_local     <= 1'b0;
            done_delay       <= 1'b0;
            local_done_count <= 32'd0;
            local_done_valid <= 1'b0;
            local_done_error <= 8'd0;
            event_meta       <= 46'd0;
        end else begin
            if (evt_valid && evt_ready) begin
                active_local <= chosen_local;
                event_meta   <= {evt_data[`EVT_SIDE_BIT], evt_data[`EVT_SHARES_SLICE],
                                 evt_data[`EVT_PIDX_SLICE]};
            end
            done_delay <= lob_event_done && active_local;
            if (done_delay) begin
                local_done_count <= local_done_count + 1'b1;
                local_done_valid <= lob_book_valid;
                local_done_error <= lob_error_code;
            end
        end
    end
endmodule
