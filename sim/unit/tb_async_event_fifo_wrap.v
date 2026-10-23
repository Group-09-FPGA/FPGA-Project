`timescale 1ns/1ps

module tb_async_event_fifo_wrap;
    reg wr_clk = 0, rd_clk = 0, rst_n = 0;
    always #7 wr_clk = ~wr_clk;
    always #11 rd_clk = ~rd_clk;
    reg wr_valid = 0, rd_ready = 0;
    reg [15:0] wr_data = 0;
    wire wr_ready, wr_full, rd_valid, rd_empty;
    wire [15:0] rd_data;
    wire wr_overflow, rd_underflow;
    wire [3:0] wr_count, rd_count;
    reg [15:0] expected [0:199];
    integer produced = 0, consumed = 0, saw_full = 0;

    async_event_fifo #(.DATA_WIDTH(16), .ADDR_WIDTH(3)) dut (
        .wr_clk(wr_clk), .wr_rst_n(rst_n), .wr_valid(wr_valid),
        .wr_data(wr_data), .wr_ready(wr_ready), .wr_full(wr_full),
        .wr_overflow(wr_overflow), .rd_clk(rd_clk), .rd_rst_n(rst_n),
        .rd_ready(rd_ready), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_empty(rd_empty), .rd_underflow(rd_underflow),
        .wr_count(wr_count), .rd_count(rd_count)
    );

    always @(negedge wr_clk) begin
        wr_valid = rst_n && produced < 200;
        wr_data = (produced * 16'h39a7) ^ 16'hb52c;
    end
    always @(negedge rd_clk)
        rd_ready = rst_n && $time > 220 && (($time / 11) % 4 != 0);

    always @(posedge wr_clk) begin
        if (rst_n && wr_full) saw_full = 1;
        if (rst_n && wr_valid && wr_ready) begin
            expected[produced] = wr_data;
            produced <= produced + 1;
        end
    end
    always @(posedge rd_clk) begin
        if (rst_n && rd_valid && rd_ready) begin
            if (consumed >= produced || rd_data !== expected[consumed])
                $fatal(1, "FIFO mismatch at %0d: got %04h expected %04h",
                       consumed, rd_data, expected[consumed]);
            consumed <= consumed + 1;
        end
    end

    initial begin
        repeat (5) @(negedge wr_clk);
        rst_n = 1;
        wait (consumed == 200);
        repeat (4) @(negedge rd_clk);
        if (produced != 200 || !saw_full || !rd_empty || rd_underflow)
            $fatal(1, "FIFO completion/full/empty failed: prod=%0d cons=%0d full=%0d empty=%b",
                   produced, consumed, saw_full, rd_empty);
        $display("PASS: async FIFO 200 events, wrap, backpressure, and full recovery");
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "FIFO test timeout: produced=%0d consumed=%0d", produced, consumed);
    end
endmodule
