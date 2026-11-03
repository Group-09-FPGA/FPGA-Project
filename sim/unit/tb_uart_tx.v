`timescale 1ns/1ps
// Pushes bytes into uart_tx and checks the serial 8N1 frames bit by bit.
module tb_uart_tx;
    localparam BIT = 40;
    reg clk = 0, rst_n = 0, wr_en = 0;
    reg [7:0] wr_data = 0;
    wire full, empty, busy, txd;
    wire [7:0] head;
    uart_tx #(.CLKS_PER_BIT(BIT)) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_data(wr_data),
        .full(full), .empty(empty), .busy(busy), .head_byte(head), .txd(txd)
    );
    always #5 clk = ~clk;

    integer errors = 0, i;
    reg [7:0] got;

    task push(input [7:0] b);
        begin
            @(posedge clk); wr_en <= 1; wr_data <= b;
            @(posedge clk); wr_en <= 0;
        end
    endtask

    task expect_frame(input [7:0] b);
        begin
            wait (txd === 1'b0);                       // start bit
            repeat (BIT + BIT/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                got[i] = txd;
                repeat (BIT) @(posedge clk);
            end
            if (got !== b) begin
                errors = errors + 1;
                $display("[FAIL] sent %02x got %02x", b, got);
            end
            if (txd !== 1'b1) begin
                errors = errors + 1;
                $display("[FAIL] missing stop bit after %02x", b);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        push(8'hA5); push(8'h0A); push(8'h00); push(8'hFF);
        expect_frame(8'hA5);
        expect_frame(8'h0A);
        expect_frame(8'h00);
        expect_frame(8'hFF);
        repeat (4 * BIT) @(posedge clk);
        if (!empty || busy) begin
            errors = errors + 1;
            $display("[FAIL] transmitter not idle after draining");
        end
        for (i = 0; i < 65; i = i + 1) push(i[7:0]);   // the first byte leaves the FIFO at once
        #1;
        if (!full) begin
            errors = errors + 1;
            $display("[FAIL] FIFO should be full with 64 bytes queued");
        end
        if (errors == 0) $display("[PASS] uart_tx frames and FIFO flags");
        $finish;
    end
endmodule
