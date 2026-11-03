`timescale 1ns/1ps

// Iterative double-dabble: converts a 32-bit number to 10 decimal digits (BCD)
// one bit per `step`. After 32 steps `digits` holds the result; `last` marks the
// final step, when `digits` is already valid.
module bin_to_decimal (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        load,
    input  wire [31:0] value,
    input  wire        step,
    output wire        last,
    output wire [39:0] digits
);
    reg [31:0] bin;
    reg [39:0] bcd;
    reg [5:0]  count;
    reg [39:0] adjusted;
    integer    n;

    always @* begin
        adjusted = bcd;
        for (n = 0; n < 10; n = n + 1)
            if (adjusted[n*4 +: 4] >= 5) adjusted[n*4 +: 4] = adjusted[n*4 +: 4] + 3;
    end

    assign digits = {adjusted[38:0], bin[31]};
    assign last   = (count == 31);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bin <= 0; bcd <= 0; count <= 0;
        end else if (load) begin
            bin <= value; bcd <= 0; count <= 0;
        end else if (step) begin
            bcd <= digits; bin <= {bin[30:0], 1'b0}; count <= count + 1'b1;
        end
    end
endmodule
