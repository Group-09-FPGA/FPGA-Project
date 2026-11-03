`timescale 1ns/1ps

// Restoring divider: 32 cycles per division, one quotient bit per cycle.
// On the last cycle `finishing` is high and `quotient` / `remainder` are final.
module price_divider (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [31:0] numerator,
    input  wire [31:0] denominator,
    output reg         busy,
    output wire        finishing,
    output wire [31:0] quotient,
    output wire [32:0] remainder
);
    reg [5:0]  count;
    reg [31:0] q, divisor;
    reg [32:0] rem;

    wire [32:0] shifted = {rem[31:0], q[31]};
    wire        take    = shifted >= {1'b0, divisor};

    assign remainder = take ? shifted - {1'b0, divisor} : shifted;
    assign quotient  = {q[30:0], take};
    assign finishing = busy && count == 31;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy <= 0; count <= 0; q <= 0; divisor <= 0; rem <= 0;
        end else if (busy) begin
            q <= quotient; rem <= remainder; count <= count + 1'b1;
            if (count == 31) busy <= 0;
        end else if (start) begin
            busy <= 1; count <= 0; rem <= 0; q <= numerator; divisor <= denominator;
        end
    end
endmodule
