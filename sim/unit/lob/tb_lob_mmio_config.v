`timescale 1ns/1ps
module tb_lob_mmio_config;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 0;
    reg bus_req_valid = 0;
    reg [31:0] bus_req_addr = 0, bus_req_wdata = 0;
    wire [31:0] cfg_price_base, cfg_tick;
    wire [15:0] cfg_stock_locate;
    wire accel_enable;

    lob_mmio_slave dut (
        .clk(clk), .reset(reset), .bus_req_valid(bus_req_valid),
        .bus_req_write(1'b1), .bus_req_addr(bus_req_addr),
        .bus_req_wdata(bus_req_wdata), .bus_req_wstrb(4'b1111),
        .cfg_price_base(cfg_price_base), .cfg_tick(cfg_tick),
        .cfg_stock_locate(cfg_stock_locate), .accel_enable(accel_enable),
        .config_ready(1'b1), .book_valid(1'b1), .init_done(1'b1),
        .busy(1'b0), .error_valid(1'b0), .error_code(8'd0),
        .active_order_count(12'd0), .event_done(1'b0), .event_ready(1'b1),
        .best_bid_valid(1'b0), .best_bid_price(32'd0), .best_bid_qty(32'd0),
        .best_ask_valid(1'b0), .best_ask_price(32'd0), .best_ask_qty(32'd0)
    );

    task write_reg(input [7:0] offset, input [31:0] value);
        begin
            @(negedge clk);
            bus_req_addr = {24'd0, offset};
            bus_req_wdata = value;
            bus_req_valid = 1;
            @(negedge clk);
            bus_req_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 1;
        write_reg(8'h24, 0);
        write_reg(8'h2c, 0);
        write_reg(8'h28, 0);
        if (cfg_price_base !== 0 || cfg_stock_locate !== 0 || cfg_tick !== 1000) begin
            $display("FAIL: zero config handling base=%0d locate=%0d tick=%0d",
                     cfg_price_base, cfg_stock_locate, cfg_tick);
            $fatal(1);
        end
        $display("PASS: zero base and locate retained; zero tick rejected");
        $finish;
    end
endmodule
