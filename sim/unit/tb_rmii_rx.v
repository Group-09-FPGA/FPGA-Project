// RMII receiver and CRC testbench (IEEE 1364-2001 Verilog).
`timescale 1ns / 1ps

module tb_rmii_rx;
    reg clk_50 = 1'b0;
    reg rst_n = 1'b0;
    reg rmii_crs_dv = 1'b0;
    reg rmii_rx_err = 1'b0;
    reg [1:0] rmii_rxd = 2'b0;
    reg frame_read_en = 1'b0;
    wire frame_valid;
    wire [11:0] frame_len;
    wire [7:0] frame_byte_out;
    wire frame_byte_last;
    wire frame_done_ack;
    wire [31:0] cnt_rx_frames, cnt_crc_err, cnt_len_err;
    wire [31:0] cnt_phy_err, cnt_overflow_err;
    reg [7:0] test_pkt [0:59];
    reg [7:0] full_frame [0:63];
    integer pass_count = 0;
    integer test_count = 0;
    integer i;

    rmii_rx dut (
        .clk_50(clk_50), .rst_n(rst_n), .rmii_crs_dv(rmii_crs_dv),
        .rmii_rx_err(rmii_rx_err), .rmii_rxd(rmii_rxd),
        .frame_valid(frame_valid), .frame_len(frame_len),
        .frame_read_en(frame_read_en), .frame_byte_out(frame_byte_out),
        .frame_byte_last(frame_byte_last), .frame_done_ack(frame_done_ack),
        .cnt_rx_frames(cnt_rx_frames), .cnt_crc_err(cnt_crc_err),
        .cnt_len_err(cnt_len_err), .cnt_phy_err(cnt_phy_err),
        .cnt_overflow_err(cnt_overflow_err)
    );

    always #10 clk_50 = ~clk_50;

    function [31:0] calc_crc32;
        input integer len;
        reg [31:0] crc;
        integer j, k;
        begin
            crc = 32'hffff_ffff;
            for (j = 0; j < len; j = j + 1)
                for (k = 0; k < 8; k = k + 1)
                    if (crc[0] ^ test_pkt[j][k])
                        crc = (crc >> 1) ^ 32'hedb8_8320;
                    else
                        crc = crc >> 1;
            calc_crc32 = ~crc;
        end
    endfunction

    task send_dibit;
        input [1:0] dibit;
        input error_bit;
        begin
            @(negedge clk_50);
            rmii_rxd = dibit;
            rmii_rx_err = error_bit;
        end
    endtask

    task transmit_rmii_frame;
        input integer payload_len;
        input corrupt_crc;
        input inject_phy_err;
        reg [31:0] fcs;
        reg [7:0] value;
        integer j;
        begin
            fcs = calc_crc32(payload_len);
            if (corrupt_crc) fcs = fcs ^ 32'hdead_beef;
            for (j = 0; j < payload_len; j = j + 1)
                full_frame[j] = test_pkt[j];
            full_frame[payload_len] = fcs[7:0];
            full_frame[payload_len+1] = fcs[15:8];
            full_frame[payload_len+2] = fcs[23:16];
            full_frame[payload_len+3] = fcs[31:24];

            @(negedge clk_50);
            rmii_crs_dv = 1'b1;
            for (j = 0; j < 28; j = j + 1) send_dibit(2'b01, 1'b0);
            send_dibit(2'b01, 1'b0);
            send_dibit(2'b01, 1'b0);
            send_dibit(2'b01, 1'b0);
            send_dibit(2'b11, 1'b0);
            for (j = 0; j < payload_len + 4; j = j + 1) begin
                value = full_frame[j];
                send_dibit(value[1:0], inject_phy_err && j == 10);
                send_dibit(value[3:2], inject_phy_err && j == 10);
                send_dibit(value[5:4], inject_phy_err && j == 10);
                send_dibit(value[7:6], inject_phy_err && j == 10);
            end
            @(negedge clk_50);
            rmii_crs_dv = 1'b0;
            rmii_rx_err = 1'b0;
            rmii_rxd = 2'b00;
            repeat (12) @(posedge clk_50);
        end
    endtask

    task verify;
        input [8*100-1:0] name;
        input cond;
        begin
            test_count = test_count + 1;
            if (cond === 1'b1) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    initial begin
        #40 rst_n = 1'b1;
        #40;
        for (i = 0; i < 60; i = i + 1) test_pkt[i] = i + 1;
        transmit_rmii_frame(60, 1'b0, 1'b0);
        #100;
        verify("Valid frame accepted", cnt_rx_frames == 1);
        verify("Payload length is 60", frame_len == 60);
        verify("Frame ready", frame_valid);
        @(negedge clk_50);
        frame_read_en = 1'b1;
        for (i = 0; i < 60; i = i + 1) begin
            #1;
            verify("Payload byte", frame_byte_out == test_pkt[i]);
            @(posedge clk_50);
            @(negedge clk_50);
        end
        frame_read_en = 1'b0;
        verify("Frame consumed", !frame_valid);

        transmit_rmii_frame(60, 1'b1, 1'b0);
        #100;
        verify("Corrupt CRC rejected", cnt_crc_err == 1 && !frame_valid);
        for (i = 0; i < 30; i = i + 1) test_pkt[i] = i;
        transmit_rmii_frame(30, 1'b0, 1'b0);
        #100;
        verify("Runt rejected", cnt_len_err == 1 && !frame_valid);
        for (i = 0; i < 60; i = i + 1) test_pkt[i] = i;
        transmit_rmii_frame(60, 1'b0, 1'b1);
        #100;
        verify("PHY error rejected", cnt_phy_err == 1 && !frame_valid);
        $display("tb_rmii_rx: %0d/%0d checks passed", pass_count, test_count);
        if (pass_count != test_count) begin $display("FAIL: ", "RMII test failed"); $stop; end
        $finish;
    end
endmodule
