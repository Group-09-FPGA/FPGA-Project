`timescale 1ns / 1ps
module tb_config_cdc;
    reg src_clk = 0, dst_clk = 0, src_rst_n = 0, dst_rst_n = 0;
    always #5 src_clk = ~src_clk;
    always #11 dst_clk = ~dst_clk;
    reg [79:0] src_data = 80'd0;
    wire [79:0] dst_data;
    wire busy, ready, update;
    integer updates = 0;
    config_cdc #(.WIDTH(80), .RESET_VALUE(80'd0)) dut (
        .src_clk(src_clk), .src_rst_n(src_rst_n),
        .src_data(src_data), .src_busy(busy), .src_ready(ready),
        .dst_clk(dst_clk), .dst_rst_n(dst_rst_n),
        .dst_data(dst_data), .dst_update(update)
    );
    always @(posedge dst_clk) if (dst_rst_n && update) begin
        updates = updates + 1;
        if (dst_data !== 80'h123456789abcdef01234 &&
            dst_data !== 80'hfedcba9876543210abcd) begin
            $display("FAIL: torn CDC update %h", dst_data); $fatal(1);
        end
    end
    initial begin
        repeat (4) @(negedge src_clk);
        src_rst_n = 1; dst_rst_n = 1;
        src_data = 80'h123456789abcdef01234;
        wait (busy);
        @(negedge src_clk);
        src_data = 80'hfedcba9876543210abcd;
        repeat (30) @(negedge src_clk);
        if (dst_data !== src_data || !ready || updates != 2) begin
            $display("FAIL: CDC did not deliver both coherent configs"); $fatal(1);
        end
        $display("PASS: bundled configuration CDC acknowledgement and coherence");
        $finish;
    end
endmodule
