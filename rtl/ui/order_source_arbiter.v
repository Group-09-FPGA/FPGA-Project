`timescale 1ns/1ps
// Stable under backpressure; alternate sources after each accepted event.
module order_source_arbiter (
    input wire clk, rst_n,
    input wire net_valid, local_valid,
    input wire [255:0] net_data, local_data,
    output wire net_ready, local_ready,
    output wire valid,
    output wire [255:0] data,
    output wire chosen_local,
    input wire ready
);
    reg prefer_local, locked, locked_local;
    wire choose_local = locked ? locked_local :
        local_valid && (!net_valid || prefer_local);
    assign valid = choose_local ? local_valid : net_valid;
    assign data = choose_local ? local_data : net_data;
    assign chosen_local = choose_local;
    assign local_ready = ready && choose_local;
    assign net_ready = ready && !choose_local;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin prefer_local<=0; locked<=0; locked_local<=0; end
        else if (valid && ready) begin prefer_local<=!choose_local; locked<=0; end
        else if (valid && !ready && !locked) begin locked<=1; locked_local<=choose_local; end
    end
endmodule
