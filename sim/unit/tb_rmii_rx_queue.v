`timescale 1ns / 1ps

module tb_rmii_rx_queue;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg crs = 0;
    reg err = 0;
    reg [1:0] rxd = 0;
    reg read_en = 0;
    wire valid;
    wire [11:0] len;
    wire [7:0] data;
    wire last;
    wire ack;
    wire [31:0] rx_count, crc_err, len_err, phy_err, overflow_err;
    integer i;

    rmii_rx dut (
        .clk_50(clk), .rst_n(rst_n), .rmii_crs_dv(crs), .rmii_rx_err(err),
        .rmii_rxd(rxd), .frame_valid(valid), .frame_len(len),
        .frame_read_en(read_en), .frame_byte_out(data), .frame_byte_last(last),
        .frame_done_ack(ack), .cnt_rx_frames(rx_count), .cnt_crc_err(crc_err),
        .cnt_len_err(len_err), .cnt_phy_err(phy_err), .cnt_overflow_err(overflow_err)
    );

    function [31:0] crc_byte;
        input [31:0] old_crc;
        input [7:0] b;
        reg [31:0] c;
        integer j;
        begin
            c = old_crc;
            for (j = 0; j < 8; j = j + 1)
                c = (c[0] ^ b[j]) ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
            crc_byte = c;
        end
    endfunction

    task dibit;
        input [1:0] d;
        begin
            @(negedge clk);
            crs = 1;
            rxd = d;
        end
    endtask

    task send_byte;
        input [7:0] b;
        begin
            dibit(b[1:0]); dibit(b[3:2]); dibit(b[5:4]); dibit(b[7:6]);
        end
    endtask

    task send_frame;
        input [7:0] marker;
        reg [31:0] c;
        reg [7:0] b;
        integer n;
        begin
            for (n = 0; n < 7; n = n + 1) send_byte(8'h55);
            send_byte(8'hD5);
            c = 32'hFFFF_FFFF;
            for (n = 0; n < 60; n = n + 1) begin
                b = marker + n;
                send_byte(b);
                c = crc_byte(c, b);
            end
            c = ~c;
            send_byte(c[7:0]); send_byte(c[15:8]);
            send_byte(c[23:16]); send_byte(c[31:24]);
            @(negedge clk);
            crs = 0;
            rxd = 0;
            repeat (12) @(negedge clk);
        end
    endtask

    task consume_frame;
        input [7:0] marker;
        integer n;
        begin
            if (!valid || len != 60) begin $display("FAIL: ", "missing queued frame"); $stop; end
            for (n = 0; n < 60; n = n + 1) begin
                if (data !== (marker + n) % 256)
                    begin $display("FAIL: ", "byte %0d: got %02x expected %02x", n, data, (marker + n) % 256); $stop; end
                if (last !== (n == 59)) begin $display("FAIL: ", "bad last at %0d", n); $stop; end
                read_en = 1;
                @(negedge clk);
            end
            read_en = 0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        send_frame(8'h10);
        send_frame(8'h80);
        if (rx_count != 2 || overflow_err != 0)
            begin $display("FAIL: ", "two frames were not queued: count=%0d overflow=%0d", rx_count, overflow_err); $stop; end
        consume_frame(8'h10);
        consume_frame(8'h80);
        if (valid) begin $display("FAIL: ", "queue failed to retire"); $stop; end
        // Cross the 2048-byte address wrap with repeated commits and reads.
        for (i = 0; i < 40; i = i + 1) begin
            send_frame(i);
            consume_frame(i);
        end
        if (rx_count != 42 || overflow_err != 0 || valid)
            begin $display("FAIL: ", "ring wrap failed: count=%0d overflow=%0d", rx_count, overflow_err); $stop; end
        $display("PASS: queued frames and 2048-byte ring wrap");
        $finish;
    end
endmodule
