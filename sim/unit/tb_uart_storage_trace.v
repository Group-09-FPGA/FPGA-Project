`timescale 1ns/1ps

module tb_uart_storage_trace;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg trigger = 0;
    wire tx;
    wire rsp_valid;
    wire [31:0] rsp_data;
    localparam [315:0] TRACE = {1'b1, 315'd0};
    integer count = 0;
    integer timeout = 0;

    uart_telemetry #(.CLK_FREQ(1000000), .BAUD_RATE(1000000)) dut (
        .clk(clk), .rst_n(rst_n),
        .bus_req_valid(1'b0), .bus_req_write(1'b0),
        .bus_req_addr(32'd0), .bus_req_wdata(32'd0),
        .bus_rsp_valid(rsp_valid), .bus_rsp_rdata(rsp_data),
        .hw_telem_trigger(trigger),
        .best_bid_price(32'd0), .best_bid_qty(32'd0),
        .best_ask_price(32'd0), .best_ask_qty(32'd0),
        .active_orders(12'd0), .book_valid(1'b1), .error_code(8'd0),
        .crc_errors(32'd0), .udp_checksum_errors(32'd0),
        .ip_checksum_errors(32'd0), .pipe_rx_frames(32'd0),
        .pipe_udp_packets(32'd0), .pipe_mold_msgs(32'd0),
        .pipe_itch_events(32'd0), .pipe_fifo_events(32'd0),
        .pipe_done_events(32'd1), .storage_trace(TRACE),
        .price_base(32'd900000), .price_tick(32'd1000),
        .kbd_diag(76'd0), .readback_valid(1'b0), .readback_byte(8'd0), .readback_ready(),
        .uart_txd(tx)
    );

    always @(posedge clk) begin
        if (rst_n && dut.hw_wr_en) begin
            if ((count == 0 && dut.hw_char !== "[") ||
                (count == 203 && dut.hw_char !== "|") ||
                (count == 205 && dut.hw_char !== "T") ||
                (count == 206 && dut.hw_char !== ":") ||
                (count == 207 && dut.hw_char !== "8") ||
                (count >= 208 && count <= 285 && dut.hw_char !== "0") ||
                (count == 289 && dut.hw_char !== "B") ||
                (count == 293 && dut.hw_char !== ":") ||
                (count == 305 && dut.hw_char !== "T") ||
                (count == 309 && dut.hw_char !== ":") ||
                (count == 323 && dut.hw_char !== ":") ||
                (count == 348 && dut.hw_char !== 8'h0D) ||
                (count == 349 && dut.hw_char !== 8'h0A)) begin
                $display("FAIL UART storage trace character %0d: %h", count, dut.hw_char);
                $fatal(1);
            end
            count = count + 1;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
        trigger = 1;
        @(negedge clk);
        trigger = 0;
        while (count < 320 && timeout < 12000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (count != 320) $fatal(1, "UART storage telemetry incomplete: %0d bytes", count);
        $display("PASS UART storage telemetry: 320 bytes, trace and price configuration");
        $finish;
    end
endmodule
