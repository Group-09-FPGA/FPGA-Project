`timescale 1ns/1ps
// Stable under backpressure; alternate sources after each accepted event.
module order_source_arbiter (
    input wire clk, rst_n,
    input wire net_valid, board_valid,
    input wire [255:0] net_data, board_data,
    output wire net_ready, board_ready,
    output wire valid,
    output wire [255:0] data,
    input wire ready
);
    reg prefer_board, locked, locked_board;
    wire choose_board = locked ? locked_board :
        board_valid && (!net_valid || prefer_board);
    assign valid = choose_board ? board_valid : net_valid;
    assign data = choose_board ? board_data : net_data;
    assign board_ready = ready && choose_board;
    assign net_ready = ready && !choose_board;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin prefer_board<=0; locked<=0; locked_board<=0; end
        else if (valid && ready) begin prefer_board<=!choose_board; locked<=0; end
        else if (valid && !ready && !locked) begin locked<=1; locked_board<=choose_board; end
    end
endmodule
