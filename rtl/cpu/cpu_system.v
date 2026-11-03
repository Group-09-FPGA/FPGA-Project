`timescale 1ns / 1ps

// Supervisor RV32IM CPU with its memories and memory-mapped peripherals.
// Address map: see docs/rtl_reference.md.
module cpu_system (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [1:0]   sw,
    input  wire         mmcm_locked,

    // LOB status read by the CPU, and configuration written by it
    input  wire         cfg_ready,
    input  wire         book_valid,
    input  wire         init_done,
    input  wire         busy,
    input  wire         error_valid,
    input  wire [7:0]   error_code,
    input  wire [11:0]  active_order_count,
    input  wire         event_done,
    input  wire         event_ready,
    input  wire         best_bid_valid,
    input  wire [31:0]  best_bid_price,
    input  wire [31:0]  best_bid_qty,
    input  wire         best_ask_valid,
    input  wire [31:0]  best_ask_price,
    input  wire [31:0]  best_ask_qty,
    output wire [31:0]  cfg_price_base,
    output wire [31:0]  cfg_tick,
    output wire [15:0]  cfg_stock_locate,
    output wire         accel_enable,

    input  wire [351:0] net_diag,

    // UART window (the UART slave lives outside)
    output wire         uart_req_valid,
    output wire         uart_req_write,
    output wire [31:0]  uart_req_addr,
    output wire [31:0]  uart_req_wdata,
    input  wire         uart_rsp_valid,
    input  wire [31:0]  uart_rsp_rdata,

    output wire [31:0]  pc
);
    wire        cpu_req_valid, cpu_req_write, cpu_rsp_valid, cpu_rsp_error;
    wire [31:0] cpu_req_addr, cpu_req_wdata, cpu_rsp_rdata;
    wire [3:0]  cpu_req_wstrb;

    cpu_core u_cpu (
        .clk(clk), .reset(rst_n), .stall(1'b0), .exception(), .pc_out(pc),
        .bus_req_valid(cpu_req_valid), .bus_req_write(cpu_req_write),
        .bus_req_addr(cpu_req_addr), .bus_req_wdata(cpu_req_wdata),
        .bus_req_wstrb(cpu_req_wstrb), .bus_rsp_valid(cpu_rsp_valid),
        .bus_rsp_rdata(cpu_rsp_rdata), .bus_rsp_error(cpu_rsp_error)
    );

    wire        imem_valid, imem_write, imem_rsp_valid;
    wire [31:0] imem_addr, imem_wdata, imem_rdata;
    wire [3:0]  imem_wstrb;
    wire        dmem_valid, dmem_write, dmem_rsp_valid;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        lob_valid, lob_write, lob_rsp_valid;
    wire [31:0] lob_addr, lob_wdata, lob_rdata;
    wire [3:0]  lob_wstrb;
    wire        net_valid, net_write, net_rsp_valid;
    wire [31:0] net_addr, net_wdata, net_rdata;
    wire [3:0]  net_wstrb;
    wire        sys_valid, sys_write;
    wire [31:0] sys_addr, sys_wdata;
    wire [3:0]  sys_wstrb;
    reg         sys_rsp_valid;
    reg  [31:0] sys_rdata;
    wire [3:0]  uart_wstrb;

    sys_bus_interconnect u_interconnect (
        .clk(clk), .reset(rst_n),
        .cpu_req_valid(cpu_req_valid), .cpu_req_write(cpu_req_write),
        .cpu_req_addr(cpu_req_addr), .cpu_req_wdata(cpu_req_wdata),
        .cpu_req_wstrb(cpu_req_wstrb), .cpu_rsp_valid(cpu_rsp_valid),
        .cpu_rsp_rdata(cpu_rsp_rdata), .cpu_rsp_error(cpu_rsp_error),
        .imem_req_valid(imem_valid), .imem_req_write(imem_write),
        .imem_req_addr(imem_addr), .imem_req_wdata(imem_wdata),
        .imem_req_wstrb(imem_wstrb), .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_rdata(imem_rdata),
        .dmem_req_valid(dmem_valid), .dmem_req_write(dmem_write),
        .dmem_req_addr(dmem_addr), .dmem_req_wdata(dmem_wdata),
        .dmem_req_wstrb(dmem_wstrb), .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_rdata(dmem_rdata),
        .lob_req_valid(lob_valid), .lob_req_write(lob_write),
        .lob_req_addr(lob_addr), .lob_req_wdata(lob_wdata),
        .lob_req_wstrb(lob_wstrb), .lob_rsp_valid(lob_rsp_valid),
        .lob_rsp_rdata(lob_rdata),
        .net_req_valid(net_valid), .net_req_write(net_write),
        .net_req_addr(net_addr), .net_req_wdata(net_wdata),
        .net_req_wstrb(net_wstrb), .net_rsp_valid(net_rsp_valid),
        .net_rsp_rdata(net_rdata),
        .uart_req_valid(uart_req_valid), .uart_req_write(uart_req_write),
        .uart_req_addr(uart_req_addr), .uart_req_wdata(uart_req_wdata),
        .uart_req_wstrb(uart_wstrb), .uart_rsp_valid(uart_rsp_valid),
        .uart_rsp_rdata(uart_rsp_rdata),
        .sys_req_valid(sys_valid), .sys_req_write(sys_write),
        .sys_req_addr(sys_addr), .sys_req_wdata(sys_wdata),
        .sys_req_wstrb(sys_wstrb), .sys_rsp_valid(sys_rsp_valid),
        .sys_rsp_rdata(sys_rdata)
    );

    imem_slave u_imem (
        .clk(clk), .reset(rst_n),
        .req_valid(imem_valid), .req_write(imem_write), .req_addr(imem_addr),
        .req_wdata(imem_wdata), .req_wstrb(imem_wstrb),
        .rsp_valid(imem_rsp_valid), .rsp_rdata(imem_rdata)
    );

    dmem_slave #(.DELAY_CYCLES(0)) u_dmem (
        .clk(clk), .reset(rst_n),
        .req_valid(dmem_valid), .req_write(dmem_write), .req_addr(dmem_addr),
        .req_wdata(dmem_wdata), .req_wstrb(dmem_wstrb),
        .rsp_valid(dmem_rsp_valid), .rsp_rdata(dmem_rdata)
    );

    lob_mmio_slave u_lob_mmio (
        .clk(clk), .reset(rst_n),
        .bus_req_valid(lob_valid), .bus_req_write(lob_write),
        .bus_req_addr(lob_addr), .bus_req_wdata(lob_wdata),
        .bus_req_wstrb(lob_wstrb), .bus_rsp_valid(lob_rsp_valid),
        .bus_rsp_rdata(lob_rdata),
        .cfg_price_base(cfg_price_base), .cfg_tick(cfg_tick),
        .cfg_stock_locate(cfg_stock_locate), .accel_enable(accel_enable),
        .config_ready(cfg_ready),
        .book_valid(book_valid), .init_done(init_done), .busy(busy),
        .error_valid(error_valid), .error_code(error_code),
        .active_order_count(active_order_count), .event_done(event_done),
        .event_ready(event_ready),
        .best_bid_valid(best_bid_valid), .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty), .best_ask_valid(best_ask_valid),
        .best_ask_price(best_ask_price), .best_ask_qty(best_ask_qty)
    );

    net_mmio_slave u_net_mmio (
        .clk(clk), .reset(rst_n),
        .bus_req_valid(net_valid), .bus_req_addr(net_addr[7:0]),
        .bus_rsp_valid(net_rsp_valid), .bus_rsp_rdata(net_rdata),
        .net_diag_snapshot(net_diag)
    );

    // System window: 0x00 = {SW15, SW14}, 0x04 = clock lock.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_rsp_valid <= 1'b0;
            sys_rdata     <= 32'd0;
        end else begin
            sys_rsp_valid <= sys_valid;
            if (sys_valid) begin
                case (sys_addr[7:0])
                    8'h00:   sys_rdata <= {30'd0, sw};
                    8'h04:   sys_rdata <= {31'd0, mmcm_locked};
                    default: sys_rdata <= 32'd0;
                endcase
            end
        end
    end
endmodule
