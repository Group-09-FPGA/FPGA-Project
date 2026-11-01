`timescale 1ns/1ps
module tb_uart_readback;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, uart_rxd = 1, rsp_update = 0;
    reg [630:0] rsp_payload = 0;
    wire req_toggle;
    wire [7:0] req_kind, tx_byte;
    wire [13:0] req_addr;
    wire tx_valid;
    uart_readback #(.CLK_FREQ(1_000_000), .BAUD_RATE(100_000)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rxd(uart_rxd),
        .req_toggle(req_toggle), .req_kind(req_kind), .req_addr(req_addr),
        .rsp_update(rsp_update), .rsp_payload(rsp_payload),
        .tx_valid(tx_valid), .tx_byte(tx_byte), .tx_ready(1'b1)
    );
    task send_byte(input [7:0] data);
        integer i;
        begin
            uart_rxd = 0; repeat (10) @(posedge clk);
            for (i=0; i<8; i=i+1) begin
                uart_rxd = data[i]; repeat (10) @(posedge clk);
            end
            uart_rxd = 1; repeat (10) @(posedge clk);
        end
    endtask
    integer n = 0;
    reg [7:0] reply [0:20];
    always @(posedge clk) if (rst_n && tx_valid) begin
        if (n < 21) reply[n] <= tx_byte;
        n <= n + 1;
    end
    initial begin
        repeat (4) @(posedge clk); rst_n = 1;
        send_byte("?"); send_byte("S"); send_byte("0");
        send_byte("7"); send_byte("F"); send_byte("F"); send_byte(8'h0A);
        repeat (6) @(posedge clk);
        if (req_toggle !== 1 || req_kind !== "S" || req_addr !== 14'h07FF)
            $fatal(1, "UART request decode failed");
        rsp_payload = {1'b1, 8'h53, 14'h07FF, 608'h123456789ABC};
        rsp_update = 1; @(posedge clk); rsp_update = 0;
        wait (n == 21); @(posedge clk);
        if (reply[0] !== "@" || reply[1] !== "S" ||
            reply[2] !== "0" || reply[5] !== "F" || reply[6] !== "=" ||
            reply[7] !== "1" || reply[18] !== "C" ||
            reply[19] !== 8'h0D || reply[20] !== 8'h0A)
            $fatal(1, "UART readback response formatting failed");
        $display("[PASS] UART query and fixed-width RAM response");
        $finish;
    end
    initial begin #200000; $fatal(1, "timeout"); end
endmodule
