`timescale 1ns / 1ps

module tb_moldudp64_gap;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg udp_valid = 0;
    reg [7:0] udp_byte = 0;
    reg udp_start = 0;
    reg udp_last = 0;
    wire udp_ready;
    wire [31:0] cnt_pkts, cnt_msgs, cnt_gaps, cnt_trunc;
    wire gap;
    wire [63:0] gap_expected, gap_received;

    moldudp64_decoder dut (
        .clk(clk), .rst_n(rst_n), .udp_payload_valid(udp_valid),
        .udp_payload_len(12'd23), .udp_payload_byte(udp_byte),
        .udp_payload_start(udp_start), .udp_payload_last(udp_last),
        .udp_payload_ready(udp_ready), .cfg_seq_reset(1'b0),
        .cfg_expected_seq(64'd1), .cfg_seq_override(1'b0),
        .seq_gap_detected(gap), .gap_expected_seq(gap_expected),
        .gap_received_seq(gap_received), .itch_msg_ready(1'b1),
        .cnt_mold_pkts(cnt_pkts), .cnt_mold_msgs(cnt_msgs),
        .cnt_seq_gaps(cnt_gaps), .cnt_trunc_errors(cnt_trunc)
    );

    task send_byte;
        input [7:0] b;
        input first;
        input final_byte;
        begin
            @(negedge clk);
            if (!udp_ready) begin $display("FAIL: ", "decoder stalled unexpectedly"); $stop; end
            udp_valid = 1;
            udp_byte = b;
            udp_start = first;
            udp_last = final_byte;
        end
    endtask

    task send_header_only;
        input [7:0] seq;
        input [15:0] count;
        integer n;
        begin
            for (n = 0; n < 10; n = n + 1) send_byte(8'h41, n == 0, 0);
            for (n = 0; n < 7; n = n + 1) send_byte(0, 0, 0);
            send_byte(seq, 0, 0);
            send_byte(count[15:8], 0, 0);
            send_byte(count[7:0], 0, 1);
            @(negedge clk);
            udp_valid = 0;
            udp_start = 0;
            udp_last = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    task send_packet;
        input [7:0] seq;
        integer n;
        begin
            for (n = 0; n < 10; n = n + 1) send_byte(8'h41, n == 0, 0);
            for (n = 0; n < 7; n = n + 1) send_byte(0, 0, 0);
            send_byte(seq, 0, 0);
            send_byte(0, 0, 0);
            send_byte(1, 0, 0); // one message
            send_byte(0, 0, 0);
            send_byte(1, 0, 0); // one-byte message
            send_byte(8'h41, 0, 1);
            @(negedge clk);
            udp_valid = 0;
            udp_start = 0;
            udp_last = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        send_header_only(1, 0); // heartbeat must not eat the next packet
        send_packet(1);
        send_packet(5);
        send_packet(6);
        if (cnt_pkts != 4 || cnt_msgs != 1 || cnt_gaps != 1 || cnt_trunc != 0 ||
            !gap || gap_expected != 2 || gap_received != 5 || dut.expected_seq != 2)
            begin $display("FAIL: ", "feed did not halt: pkts=%0d msgs=%0d gaps=%0d expected=%0d", cnt_pkts, cnt_msgs, cnt_gaps, dut.expected_seq); $stop; end
        $display("PASS: sequence gap halts subsequent message decoding");
        $finish;
    end
endmodule
