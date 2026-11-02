`timescale 1ns/1ps

module tb_lob_display_journal;
    reg core_clk = 0;
    reg read_clk = 0;
    always #5 core_clk = ~core_clk;
    always #10 read_clk = ~read_clk;
    reg rst_n = 0;
    reg done = 0;
    reg [31:0] completed = 0;
    reg [315:0] trace = 0;
    reg [31:0] bid = 0;
    reg [6:0] qaddr = 0;
    reg [7:0] eaddr = 0;
    wire [174:0] qdata;
    wire [393:0] edata;
    wire [7:0] qcount;
    wire [8:0] ecount;
    wire [6:0] qnext;
    wire [7:0] enext;

    lob_display_journal dut (
        .core_clk(core_clk), .core_rst_n(rst_n), .event_done(done),
        .completed_count(completed), .storage_trace(trace), .event_meta(46'h12345),
        .book_valid(1'b1), .bid_valid(1'b1), .bid_price(bid),
        .bid_qty(32'd100), .ask_valid(1'b0), .ask_price(32'd0),
        .ask_qty(32'd0), .active_orders(12'd1), .read_clk(read_clk),
        .quote_read_addr(qaddr), .quote_read_data(qdata),
        .event_read_addr(eaddr), .event_read_data(edata),
        .quote_count(qcount), .event_count(ecount),
        .quote_next(qnext), .event_next(enext)
    );

    task emit_event;
        input [31:0] number;
        input [31:0] price;
        begin
            @(negedge core_clk);
            done = 1;
            completed = number - 1;
            trace = {1'b1, 315'd0} | number;
            bid = price;
            @(negedge core_clk);
            done = 0;
            completed = number;
            repeat (12) @(negedge core_clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge core_clk);
        rst_n = 1;
        emit_event(1, 905000);
        emit_event(2, 907000);
        if (qcount !== 8'd2 || ecount !== 9'd2 ||
            qnext !== 7'd2 || enext !== 8'd2)
            $fatal(1, "journal counts incorrect");
        qaddr = 1;
        eaddr = 1;
        repeat (2) @(posedge read_clk);
        #1;
        if (qdata[31:0] !== 32'd2 || qdata[172:141] !== 32'd907000 ||
            edata[393:362] !== 32'd2 || edata[361:316] !== 46'h12345 ||
            edata[31:0] !== 32'd2)
            $fatal(1, "journal contents incorrect");
        $display("PASS board-owned quote and event history rings");
        $finish;
    end
endmodule
