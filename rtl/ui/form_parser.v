`timescale 1ns/1ps

// Continuously converts the four order-form text fields into numbers.
// Field 0 is price (decimal with exactly four fractional digits), field 1 is
// quantity (decimal), fields 2 and 3 are order IDs (hexadecimal).
// One field is parsed every 17 cycles; `current` says whether a field's parsed
// value still matches the text it was parsed from.
module form_parser (
    input  wire         clk,
    input  wire         reset_n,
    input  wire [511:0] text,        // four 16-character fields, field 0 in bits [127:0]
    input  wire [19:0]  lengths,     // four 5-bit lengths
    output wire [255:0] values,      // four 64-bit values
    output reg  [3:0]   ok,          // syntax and range are valid
    output wire [3:0]   current
);
    function [7:0] chr;
        input [127:0] value;
        input integer position;
        begin chr = value[127-position*8 -: 8]; end
    endfunction

    function [3:0] hex_value;
        input [7:0] c;
        begin
            if (c >= "0" && c <= "9")      hex_value = c - "0";
            else if (c >= "A" && c <= "F") hex_value = c - "A" + 10;
            else                           hex_value = 0;
        end
    endfunction

    function syntax_valid;
        input [127:0] value;
        input [4:0]   length;
        input [1:0]   kind;          // 0 price, 1 quantity, 2/3 hex id
        integer n, dots, fraction;
        reg good, seen_dot;
        reg [7:0] c;
        begin
            good = (length != 0); dots = 0; fraction = 0; seen_dot = 0;
            for (n = 0; n < 16; n = n + 1) if (n < length) begin
                c = chr(value, n);
                if (kind == 0 && c == ".") begin
                    dots = dots + 1; seen_dot = 1;
                    if (n == 0) good = 0;
                end else if (kind >= 2 && c >= "A" && c <= "F") begin
                end else if (c >= "0" && c <= "9") begin
                    if (seen_dot) fraction = fraction + 1;
                end else good = 0;
            end
            if (kind == 0 && (dots != 1 || fraction != 4 || length > 11)) good = 0;
            if (kind == 1 && length > 10) good = 0;
            syntax_valid = good;
        end
    endfunction

    reg [63:0]  value_r [0:3];
    reg [127:0] text_r  [0:3];
    reg [4:0]   length_r[0:3];

    reg [1:0]   field;
    reg [4:0]   index, length;
    reg [127:0] field_text;
    reg [63:0]  acc;
    integer     k;

    wire [7:0]  ch   = chr(field_text, index - 1'b1);
    wire [63:0] next = (index - 1'b1 >= length || ch == ".") ? acc :
                       field >= 2 ? (acc << 4) + hex_value(ch) : acc * 10 + (ch - "0");

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : gen_field
        assign values[g*64 +: 64] = value_r[g];
        assign current[g] = text_r[g] == text[g*128 +: 128] && length_r[g] == lengths[g*5 +: 5];
    end endgenerate

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            field <= 0; index <= 0; length <= 0; field_text <= 0; acc <= 0; ok <= 0;
            for (k = 0; k < 4; k = k + 1) begin
                value_r[k] <= 0; text_r[k] <= 0; length_r[k] <= 0;
            end
        end else if (index == 0) begin
            field_text <= text[field*128 +: 128];
            length     <= lengths[field*5 +: 5];
            acc <= 0; index <= 1;
        end else begin
            acc <= next;
            if (index == 16) begin
                value_r[field]  <= next;
                text_r[field]   <= field_text;
                length_r[field] <= length;
                ok[field] <= syntax_valid(field_text, length, field) &&
                    (field == 0 ? next <= 32'hffffffff :
                     field == 1 ? next != 0 && next <= 32'hffffffff : next != 0);
                field <= field + 1'b1; index <= 0;
            end else index <= index + 1'b1;
        end
    end
endmodule
