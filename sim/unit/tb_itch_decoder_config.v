`timescale 1ns / 1ps
module tb_itch_decoder_config;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, valid = 0, start = 0, last = 0, ready = 0;
    reg [15:0] length = 36;
    reg [7:0] byte_in = 0;
    wire msg_ready, event_valid, decode_error;
    wire [255:0] event_data;
    reg [7:0] msg [0:35];
    integer i;

    itch_decoder dut (
        .clk(clk), .rst_n(rst_n), .itch_msg_valid(valid),
        .itch_msg_len(length), .itch_msg_byte(byte_in),
        .itch_msg_seq(64'd1), .itch_msg_start(start),
        .itch_msg_last(last), .itch_msg_ready(msg_ready),
        .cfg_stock_locate(16'd7), .cfg_price_base(32'd900000),
        .cfg_tick(32'd500), .canon_event_valid(event_valid),
        .canon_event_data(event_data), .canon_event_ready(ready),
        .decode_error(decode_error)
    );

    task send_add;
        input [15:0] declared_length;
        begin
            length = declared_length;
            for (i = 0; i < 36; i = i + 1) begin
                @(negedge clk);
                if (!msg_ready) begin $display("FAIL: input stalled"); $fatal; end
                valid = 1; start = i == 0; last = i == 35;
                byte_in = msg[i];
            end
            @(negedge clk);
            valid = 0; start = 0; last = 0;
        end
    endtask

    initial begin
        for (i = 0; i < 36; i = i + 1) msg[i] = 0;
        msg[0] = "A";
        msg[2] = 7;
        msg[18] = 1;
        msg[19] = "B";
        msg[23] = 10;
        // 902500 = 0x000DC564 = base 900000 + five 500-unit ticks.
        msg[32] = 8'h00; msg[33] = 8'h0d;
        msg[34] = 8'hc5; msg[35] = 8'h64;
        repeat (4) @(negedge clk);
        rst_n = 1;
        send_add(36);
        wait (event_valid);
        if (event_data[79:67] !== 13'd5 || event_data[66] !== 0 ||
            event_data[251:248] !== 4'h1) begin
            $display("FAIL: dynamic tick conversion pidx=%0d oow=%b", event_data[79:67], event_data[66]);
            $fatal;
        end
        repeat (5) @(negedge clk);
        if (!event_valid) begin $display("FAIL: event lost during backpressure"); $fatal; end
        ready = 1;
        @(negedge clk);
        ready = 0;
        wait (msg_ready);
        send_add(35);
        repeat (5) @(negedge clk);
        if (!decode_error || event_valid) begin
            $display("FAIL: malformed order length accepted"); $fatal;
        end
        $display("PASS: configurable tick, output backpressure, malformed length");
        $finish;
    end
endmodule
