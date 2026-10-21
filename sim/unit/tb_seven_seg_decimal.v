`timescale 1ns / 1ps

module tb_seven_seg_decimal;
    reg clk = 1'b0;
    reg reset = 1'b0;
    reg [31:0] value = 32'd0;
    reg [1:0] format = 2'b01;
    reg [7:0] point_mask = 8'b0001_0000;
    wire [7:0] an;
    wire [6:0] seg;
    wire dp;

    always #5 clk = ~clk;

    seven_seg_driver dut (
        .clk(clk), .reset(reset), .value(value), .format(format),
        .point_mask(point_mask), .an(an), .seg(seg), .dp(dp)
    );

    initial begin
        #12 reset = 1'b1;
        value = 32'd905000;
        repeat (35) @(posedge clk);
        #1;
        if (dut.decimal_digits !== 32'h0090_5000)
            begin $display("FAIL: ", "price BCD: %h", dut.decimal_digits); $stop; end

        force dut.digit_sel = 3'd4;
        #1;
        if (dp !== 1'b0 || an !== 8'b1110_1111)
            begin $display("FAIL: ", "price point: dp=%b an=%b", dp, an); $stop; end
        force dut.digit_sel = 3'd3;
        #1;
        if (dp !== 1'b1)
            begin $display("FAIL: ", "unexpected point: dp=%b", dp); $stop; end
        release dut.digit_sel;

        @(negedge clk);
        format = 2'b10;
        point_mask = 8'b0;
        value = 32'h0002_000c;
        repeat (65) @(posedge clk);
        #1;
        if (dut.decimal_digits !== 32'h0002_0012 || dp !== 1'b1)
            begin $display("FAIL: ", "split BCD: %h dp=%b", dut.decimal_digits, dp); $stop; end

        @(negedge clk);
        value = 32'h0010_0048;
        repeat (50) @(posedge clk);
        #1;
        if (dut.decimal_digits !== 32'h0016_0072)
            begin $display("FAIL: ", "frames/PC BCD: %h", dut.decimal_digits); $stop; end

        $display("PASS: decimal price, decimal point, and split counters");
        $finish;
    end
endmodule
