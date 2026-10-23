`timescale 1ns/1ps

module tb_net_parser_max_payload;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg frame_valid = 0;
    reg [11:0] rd_idx = 0;
    reg [7:0] frame [0:1513];
    wire read_en;
    wire [7:0] frame_data = frame[rd_idx];
    wire frame_last = rd_idx == 12'd1513;
    wire udp_valid, udp_start, udp_last;
    wire [11:0] udp_len;
    wire [7:0] udp_byte;
    wire [31:0] cnt_udp, cnt_len_err;
    integer i, delivered = 0;
    reg [31:0] ip_sum;

    net_parser dut (
        .clk(clk), .rst_n(rst_n), .frame_valid(frame_valid),
        .frame_len(12'd1514), .frame_read_en(read_en),
        .frame_byte_in(frame_data), .frame_byte_last(frame_last),
        .cfg_udp_port(16'd10443), .cfg_dst_mac(48'd0), .cfg_dst_ip(32'd0),
        .udp_payload_valid(udp_valid), .udp_payload_len(udp_len),
        .udp_payload_byte(udp_byte), .udp_payload_start(udp_start),
        .udp_payload_last(udp_last), .udp_payload_ready(1'b1),
        .cnt_udp_packets(cnt_udp), .cnt_udp_len_err(cnt_len_err)
    );

    always @(posedge clk) begin
        if (read_en && frame_valid) begin
            if (frame_last) frame_valid <= 0;
            else rd_idx <= rd_idx + 12'd1;
        end
        if (udp_valid) begin
            if (udp_len !== 12'd1472 ||
                udp_byte !== frame[42 + delivered] ||
                udp_start !== (delivered == 0) ||
                udp_last !== (delivered == 1471))
                $fatal(1, "payload mismatch at byte %0d: got %02h", delivered, udp_byte);
            delivered = delivered + 1;
        end
    end

    initial begin
        for (i = 0; i < 1514; i = i + 1) frame[i] = 0;
        frame[12] = 8'h08; frame[13] = 8'h00;
        frame[14] = 8'h45;
        frame[16] = 8'h05; frame[17] = 8'hdc; // IPv4 length 1500
        frame[22] = 8'd64; frame[23] = 8'd17;
        ip_sum = 0;
        for (i = 14; i < 34; i = i + 2)
            ip_sum = ip_sum + {frame[i], frame[i+1]};
        ip_sum = ip_sum[15:0] + ip_sum[31:16];
        frame[24] = (~ip_sum >> 8) & 8'hff;
        frame[25] = ~ip_sum & 8'hff;
        frame[36] = 8'h28; frame[37] = 8'hcb;
        frame[38] = 8'h05; frame[39] = 8'hc8; // UDP length 1480
        for (i = 0; i < 1472; i = i + 1)
            frame[42+i] = (i * 37 + 13) & 8'hff;
        repeat (4) @(negedge clk);
        rst_n = 1;
        frame_valid = 1;
        repeat (3500) @(negedge clk);
        if (delivered != 1472 || cnt_udp != 1 || cnt_len_err != 0)
            $fatal(1, "max packet incomplete: bytes=%0d udp=%0d len_err=%0d",
                   delivered, cnt_udp, cnt_len_err);
        $display("PASS: 1472-byte UDP payload replay across RAM address boundary");
        $finish;
    end
endmodule
