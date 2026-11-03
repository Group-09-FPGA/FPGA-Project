`timescale 1ns / 1ps

// Counts cycles in which `inc` is high.
module event_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        inc,
    output reg  [31:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 32'd0;
        else if (inc)
            count <= count + 32'd1;
    end
endmodule
