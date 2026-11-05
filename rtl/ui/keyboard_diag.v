`timescale 1ns/1ps
// Keyboard bring-up counters, reported on the UART status line.
// Distinguishes "no clock activity" from "bytes rejected" from "keys decoded".
module keyboard_diag (
    input wire clk, rst_n,
    input wire ps2_clk, ps2_data,
    input wire byte_valid, frame_error, key_valid,
    input wire [7:0] byte_data,
    output wire [75:0] diag
);
    (* ASYNC_REG="TRUE" *) reg [2:0] clk_sync;
    (* ASYNC_REG="TRUE" *) reg data_sync;
    reg [15:0] edges, bytes, frame_errors, keys;
    reg [7:0] last_byte;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_sync<=3'b111; data_sync<=1;
            edges<=0;bytes<=0;frame_errors<=0;keys<=0;last_byte<=0;
        end else begin
            clk_sync<={clk_sync[1:0],ps2_clk};
            data_sync<=ps2_data;
            if (clk_sync[2]!=clk_sync[1]) edges<=edges+1'b1;
            if (byte_valid) begin bytes<=bytes+1'b1; last_byte<=byte_data; end
            if (frame_error) frame_errors<=frame_errors+1'b1;
            if (key_valid) keys<=keys+1'b1;
        end
    end
    assign diag = {edges, bytes, frame_errors, keys, last_byte, data_sync, clk_sync[2], 2'b00};
endmodule
