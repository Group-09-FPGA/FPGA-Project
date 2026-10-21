`timescale 1ns / 1ps

module tb_net_parser_padding;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg frame_valid = 0;
    reg [6:0] rd_idx = 0;
    reg [7:0] frame [0:59];
    wire read_en;
    wire [7:0] frame_data = frame[rd_idx];
    wire frame_last = (rd_idx == 59);
    wire udp_valid, udp_start, udp_last;
    wire [11:0] udp_len;
    wire [7:0] udp_byte;
    wire [31:0] cnt_udp;
    integer i;
    reg [31:0] ip_sum;

    net_parser dut (
        .clk(clk), .rst_n(rst_n), .frame_valid(frame_valid), .frame_len(12'd60),
        .frame_read_en(read_en), .frame_byte_in(frame_data), .frame_byte_last(frame_last),
        .cfg_udp_port(16'd10443), .udp_payload_valid(udp_valid),
        .udp_payload_len(udp_len), .udp_payload_byte(udp_byte),
        .udp_payload_start(udp_start), .udp_payload_last(udp_last),
        .udp_payload_ready(1'b1), .cnt_udp_packets(cnt_udp)
    );

    always @(posedge clk) begin
        if (read_en && frame_valid) begin
            if (frame_last) frame_valid <= 0;
            else rd_idx <= rd_idx + 1'b1;
        end
    end

    initial begin
        for (i = 0; i < 60; i = i + 1) frame[i] = 0;
        frame[12] = 8'h08; frame[13] = 8'h00;
        frame[14] = 8'h45; frame[16] = 0; frame[17] = 29;
        frame[22] = 64; frame[23] = 17;
        // IPv4 checksum over the 20-byte header, including its checksum word.
        ip_sum = 0;
        for (i = 14; i < 34; i = i + 2)
            ip_sum = ip_sum + {frame[i], frame[i+1]};
        ip_sum = ip_sum[15:0] + ip_sum[31:16];
        frame[24] = (~ip_sum >> 8) & 8'hff;
        frame[25] = ~ip_sum & 8'hff;
        frame[36] = 8'h28; frame[37] = 8'hcb; // UDP destination 10443
        frame[38] = 0; frame[39] = 9;         // UDP header + one byte
        frame[42] = 8'h5a;
        repeat (4) @(negedge clk);
        rst_n = 1;
        frame_valid = 1;
        repeat (100) @(negedge clk);
        if (frame_valid || rd_idx != 59 || cnt_udp != 1)
            $fatal(1, "padding not drained: valid=%b idx=%0d udp=%0d", frame_valid, rd_idx, cnt_udp);
        $display("PASS: padded Ethernet frame drained after UDP payload");
        $finish;
    end
endmodule
