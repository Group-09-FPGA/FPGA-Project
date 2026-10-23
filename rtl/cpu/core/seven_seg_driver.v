`timescale 1ns / 1ps

////////////////////////////////////////////////////////////
// seven_seg_driver.v
// Displays a 32-bit value as hexadecimal, eight decimal digits, or
// two four-digit decimal fields on the Nexys A7 7-segment display.
// Decimal conversion runs over 32 clock cycles to keep the logic small.
// Refresh interval is derived from CLK_FREQ_HZ (~1 kHz per digit).
//
// Ports:
//   clk    - display clock
//   reset  - active-low reset
//   value  - raw 32-bit value to display
//   format - 0: hex, 1: eight decimal digits, 2: two decimal 16-bit fields
//   point_mask - bit per digit, 1 lights that digit's decimal point
//   an     - 8-bit anode select, active-low (AN[7:0])
//   seg    - 7-bit segment, active-low {CG,CF,CE,CD,CC,CB,CA}
//   dp     - decimal point, active-low
////////////////////////////////////////////////////////////

module seven_seg_driver #(
    parameter CLK_FREQ_HZ = 100_000_000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] value,
    input  wire [1:0]  format,
    input  wire [7:0]  point_mask,
    output reg  [7:0]  an,    // active-low anode select
    output reg  [6:0]  seg,   // active-low segments {CG..CA}
    output wire        dp
);

    // Double-dabble conversion. In split mode each 16-bit half is converted
    // independently; values above 9999 show their four least-significant
    // decimal digits. The displayed result changes only after a full pass.
    reg [31:0] binary_shift;
    reg [31:0] bcd_work;
    reg [31:0] decimal_digits;
    reg [5:0]  steps_remaining;
    reg [1:0]  working_format;
    reg [31:0] bcd_adjusted;
    reg [31:0] bcd_next;
    integer i;

    always @(*) begin
        bcd_adjusted = bcd_work;
        for (i = 0; i < 8; i = i + 1) begin
            if (bcd_work[i*4 +: 4] >= 4'd5)
                bcd_adjusted[i*4 +: 4] = bcd_work[i*4 +: 4] + 4'd3;
        end
        if (working_format == 2'b10)
            bcd_next = {bcd_adjusted[30:16], binary_shift[31],
                        bcd_adjusted[14:0], binary_shift[15]};
        else
            bcd_next = {bcd_adjusted[30:0], binary_shift[31]};
    end

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            binary_shift    <= 32'd0;
            bcd_work        <= 32'd0;
            decimal_digits  <= 32'd0;
            steps_remaining <= 6'd0;
            working_format  <= 2'b00;
        end else if (steps_remaining == 6'd0) begin
            binary_shift    <= value;
            bcd_work        <= 32'd0;
            working_format  <= format;
            steps_remaining <= (format == 2'b10) ? 6'd16 : 6'd32;
        end else begin
            bcd_work <= bcd_next;
            if (working_format == 2'b10)
                binary_shift <= {binary_shift[30:16], 1'b0,
                                 binary_shift[14:0], 1'b0};
            else
                binary_shift <= {binary_shift[30:0], 1'b0};
            steps_remaining <= steps_remaining - 1'b1;
            if (steps_remaining == 6'd1)
                decimal_digits <= bcd_next;
        end
    end

    ////////////////////////////////////////////////////////////
    // Refresh counter
    // Hold each digit for 1 ms regardless of the selected core clock.
    // -> full 8-digit refresh every 8 ms = 125 Hz (flicker-free)
    ////////////////////////////////////////////////////////////
    localparam [16:0] REFRESH_RELOAD = CLK_FREQ_HZ / 1000 - 1;
    reg [16:0] refresh_cnt;
    reg [2:0]  digit_sel;
    assign dp = ~point_mask[digit_sel];

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            refresh_cnt <= 17'd0;
            digit_sel   <= 3'd0;
        end else begin
            if (refresh_cnt == REFRESH_RELOAD) begin
                refresh_cnt <= 17'd0;
                digit_sel   <= digit_sel + 1'b1;
            end else begin
                refresh_cnt <= refresh_cnt + 1'b1;
            end
        end
    end

    ////////////////////////////////////////////////////////////
    // Digit mux: select hexadecimal or converted decimal digit
    // digit_sel=0 -> rightmost digit (LSB nibble)
    // digit_sel=7 -> leftmost digit (MSB nibble)
    ////////////////////////////////////////////////////////////
    reg [3:0] nibble;
    wire [31:0] displayed_value = (format == 2'b00) ? value : decimal_digits;
    always @(*) begin
        case (digit_sel)
            3'd0: nibble = displayed_value[ 3: 0];
            3'd1: nibble = displayed_value[ 7: 4];
            3'd2: nibble = displayed_value[11: 8];
            3'd3: nibble = displayed_value[15:12];
            3'd4: nibble = displayed_value[19:16];
            3'd5: nibble = displayed_value[23:20];
            3'd6: nibble = displayed_value[27:24];
            3'd7: nibble = displayed_value[31:28];
            default: nibble = 4'h0;
        endcase
    end

    ////////////////////////////////////////////////////////////
    // Anode select (active-low: 0 = digit ON)
    ////////////////////////////////////////////////////////////
    always @(*) begin
        case (digit_sel)
            3'd0: an = 8'b1111_1110; // rightmost
            3'd1: an = 8'b1111_1101;
            3'd2: an = 8'b1111_1011;
            3'd3: an = 8'b1111_0111;
            3'd4: an = 8'b1110_1111;
            3'd5: an = 8'b1101_1111;
            3'd6: an = 8'b1011_1111;
            3'd7: an = 8'b0111_1111; // leftmost
            default: an = 8'b1111_1111; // all off
        endcase
    end

    ////////////////////////////////////////////////////////////
    // Hex to 7-segment decoder (active-low)
    // seg[6:0] = {CG, CF, CE, CD, CC, CB, CA}
    //   CA=top, CB=upper-right, CC=lower-right,
    //   CD=bottom, CE=lower-left, CF=upper-left, CG=middle
    ////////////////////////////////////////////////////////////
    always @(*) begin
        case (nibble)
            4'h0: seg = 7'b100_0000; // 0
            4'h1: seg = 7'b111_1001; // 1
            4'h2: seg = 7'b010_0100; // 2
            4'h3: seg = 7'b011_0000; // 3
            4'h4: seg = 7'b001_1001; // 4
            4'h5: seg = 7'b001_0010; // 5
            4'h6: seg = 7'b000_0010; // 6
            4'h7: seg = 7'b111_1000; // 7
            4'h8: seg = 7'b000_0000; // 8
            4'h9: seg = 7'b001_0000; // 9
            4'ha: seg = 7'b000_1000; // A
            4'hb: seg = 7'b000_0011; // b
            4'hc: seg = 7'b100_0110; // C
            4'hd: seg = 7'b010_0001; // d
            4'he: seg = 7'b000_0110; // E
            4'hf: seg = 7'b000_1110; // F
            default: seg = 7'b111_1111; // all off
        endcase
    end

endmodule
