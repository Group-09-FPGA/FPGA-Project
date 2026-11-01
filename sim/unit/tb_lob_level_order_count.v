`timescale 1ns/1ps

module tb_lob_level_order_count;
    reg core_clk = 0;
    reg read_clk = 0;
    always #5 core_clk = ~core_clk;
    always #10 read_clk = ~read_clk;
    reg rst_n = 0;
    reg delta_valid = 0;
    reg delta_inc = 0;
    reg [13:0] delta_addr = 0;
    reg [13:0] read_addr = 0;
    wire init_done;
    wire [11:0] read_count;

    lob_level_order_count dut (
        .core_clk(core_clk), .core_rst_n(rst_n),
        .delta_valid(delta_valid), .delta_inc(delta_inc),
        .delta_addr(delta_addr), .init_done(init_done),
        .read_clk(read_clk), .read_addr(read_addr),
        .read_count(read_count)
    );

    task change_count;
        input inc;
        input [13:0] addr;
        begin
            @(negedge core_clk);
            delta_valid = 1;
            delta_inc = inc;
            delta_addr = addr;
            @(negedge core_clk);
            delta_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge core_clk);
        rst_n = 1;
        wait (init_done);
        change_count(1, 14'd5);
        change_count(1, 14'd5);
        change_count(1, 14'h2005);
        change_count(0, 14'd5);
        repeat (3) @(negedge core_clk);
        read_addr = 14'd5;
        repeat (2) @(posedge read_clk);
        #1;
        if (read_count !== 12'd1) $fatal(1, "bid level count %0d", read_count);
        read_addr = 14'h2005;
        repeat (2) @(posedge read_clk);
        #1;
        if (read_count !== 12'd1) $fatal(1, "ask level count %0d", read_count);
        change_count(0, 14'd5);
        repeat (3) @(negedge core_clk);
        read_addr = 14'd5;
        repeat (2) @(posedge read_clk);
        #1;
        if (read_count !== 12'd0) $fatal(1, "empty level did not disappear");
        $display("PASS FPGA price-level order counts update and clear");
        $finish;
    end
endmodule
