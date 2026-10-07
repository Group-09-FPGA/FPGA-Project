`timescale 1ns / 1ps

////////////////////////////////////////////////////////////
// seven_seg_driver.v
// Displays a 32-bit value as 8 hex digits on the Nexys A7
// 7-segment display. Needs the fast board clock (100 MHz)
// for proper multiplexed refresh (~1 kHz per digit).
//
// Ports:
//   clk    - fast board clock (100 MHz)
//   reset  - active-low reset
//   value  - 32-bit value to display (8 hex nibbles)
//   an     - 8-bit anode select, active-low (AN[7:0])
//   seg    - 7-bit segment, active-low {CG,CF,CE,CD,CC,CB,CA}
//   dp     - decimal point, active-low (always off)
////////////////////////////////////////////////////////////

module seven_seg_driver (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] value,
    output reg  [7:0]  an,    // active-low anode select
    output reg  [6:0]  seg,   // active-low segments {CG..CA}
    output wire        dp     // decimal point: always off
);

    // DP always off (active-low, so 1 = off)
    assign dp = 1'b1;

    ////////////////////////////////////////////////////////////
    // Refresh counter
    // At 100 MHz, count to 100,000 -> each digit held for 1 ms
    // -> full 8-digit refresh every 8 ms = 125 Hz (flicker-free)
    ////////////////////////////////////////////////////////////
    reg [16:0] refresh_cnt;
    reg [2:0]  digit_sel;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            refresh_cnt <= 17'd0;
            digit_sel   <= 3'd0;
        end else begin
            if (refresh_cnt == 17'd99_999) begin
                refresh_cnt <= 17'd0;
                digit_sel   <= digit_sel + 1'b1;
            end else begin
                refresh_cnt <= refresh_cnt + 1'b1;
            end
        end
    end

    ////////////////////////////////////////////////////////////
    // Nibble mux: select which hex digit to show
    // digit_sel=0 -> rightmost digit (LSB nibble)
    // digit_sel=7 -> leftmost digit (MSB nibble)
    ////////////////////////////////////////////////////////////
    reg [3:0] nibble;
    always @(*) begin
        case (digit_sel)
            3'd0: nibble = value[ 3: 0];
            3'd1: nibble = value[ 7: 4];
            3'd2: nibble = value[11: 8];
            3'd3: nibble = value[15:12];
            3'd4: nibble = value[19:16];
            3'd5: nibble = value[23:20];
            3'd6: nibble = value[27:24];
            3'd7: nibble = value[31:28];
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
