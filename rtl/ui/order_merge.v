`timescale 1ns / 1ps

`include "lob_defines.vh"

// Passes network events to the order book and remembers the side, shares and
// price index of the last accepted event for the display journal. The network
// is the only order source; the board's keyboard and VGA are read-only.
module order_merge (
    input  wire         clk_core,
    input  wire         rst_core_n,

    input  wire         net_valid,
    input  wire [255:0] net_data,
    output wire         net_ready,

    output wire         evt_valid,
    output wire [255:0] evt_data,
    input  wire         evt_ready,

    output reg  [45:0]  event_meta
);
    assign evt_valid = net_valid;
    assign evt_data  = net_data;
    assign net_ready = evt_ready;

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n)
            event_meta <= 46'd0;
        else if (evt_valid && evt_ready)
            event_meta <= {evt_data[`EVT_SIDE_BIT], evt_data[`EVT_SHARES_SLICE],
                           evt_data[`EVT_PIDX_SLICE]};
    end
endmodule
