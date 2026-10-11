// =============================================================================
// File: tb_cpu_lob_mmio.sv
// Description: Integration testbench verifying CPU + MMIO + LOB core interaction
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module tb_cpu_lob_mmio;

    logic clk;
    logic rst_n;
    wire [31:0] cpu_pc;

    // CPU System Bus signals
    wire        bus_req_valid;
    wire        bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [ 3:0] bus_req_wstrb;
    wire        bus_rsp_valid;
    wire [31:0] bus_rsp_rdata;
    wire        bus_rsp_error;

    // IMEM Bus signals
    wire        imem_req_valid;
    wire        imem_req_write;
    wire [31:0] imem_req_addr;
    wire [31:0] imem_req_wdata;
    wire [ 3:0] imem_req_wstrb;
    wire        imem_rsp_valid;
    wire [31:0] imem_rsp_rdata;

    // DMEM Bus signals
    wire        dmem_req_valid;
    wire        dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [ 3:0] dmem_req_wstrb;
    wire        dmem_rsp_valid;
    wire [31:0] dmem_rsp_rdata;

    // LOB MMIO Bus signals
    wire        lob_req_valid;
    wire        lob_req_write;
    wire [31:0] lob_req_addr;
    wire [31:0] lob_req_wdata;
    wire [ 3:0] lob_req_wstrb;
    wire        lob_rsp_valid;
    wire [31:0] lob_rsp_rdata;

    // LOB Core Controls from MMIO
    wire        cfg_clear_strobe;
    wire        cfg_fail_stop_en;
    wire [31:0] cfg_price_base;
    wire [31:0] cfg_tick;
    wire [15:0] cfg_stock_locate;
    wire        accel_enable;

    // LOB Core Status to MMIO
    wire        book_valid;
    wire        init_done;
    wire        busy;
    wire        error_valid;
    wire [ 7:0] error_code;
    wire [11:0] active_order_count;
    wire        event_done;
    wire        event_ready;

    // BBO signals
    wire        best_bid_valid;
    wire [31:0] best_bid_price;
    wire [31:0] best_bid_qty;
    wire        best_ask_valid;
    wire [31:0] best_ask_price;
    wire [31:0] best_ask_qty;

    // Event Ingestion into LOB
    logic         inj_event_valid;
    wire          inj_event_ready;
    logic [255:0] inj_event_data;

    // Clock generator: 100 MHz (10 ns period)
    always #5 clk = ~clk;

    // 1. CPU Core instance
    cpu_core u_cpu (
        .clk(clk),
        .reset(rst_n),
        .stall(1'b0),
        .exception(),
        .pc_out(cpu_pc),

        .bus_req_valid(bus_req_valid),
        .bus_req_write(bus_req_write),
        .bus_req_addr(bus_req_addr),
        .bus_req_wdata(bus_req_wdata),
        .bus_req_wstrb(bus_req_wstrb),
        .bus_rsp_valid(bus_rsp_valid),
        .bus_rsp_rdata(bus_rsp_rdata),
        .bus_rsp_error(bus_rsp_error)
    );

    // 2. System Bus Interconnect instance
    sys_bus_interconnect u_interconnect (
        .clk(clk),
        .reset(rst_n),
        .cpu_req_valid(bus_req_valid),
        .cpu_req_write(bus_req_write),
        .cpu_req_addr(bus_req_addr),
        .cpu_req_wdata(bus_req_wdata),
        .cpu_req_wstrb(bus_req_wstrb),
        .cpu_rsp_valid(bus_rsp_valid),
        .cpu_rsp_rdata(bus_rsp_rdata),
        .cpu_rsp_error(bus_rsp_error),

        .imem_req_valid(imem_req_valid),
        .imem_req_write(imem_req_write),
        .imem_req_addr(imem_req_addr),
        .imem_req_wdata(imem_req_wdata),
        .imem_req_wstrb(imem_req_wstrb),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_rdata(imem_rsp_rdata),

        .dmem_req_valid(dmem_req_valid),
        .dmem_req_write(dmem_req_write),
        .dmem_req_addr(dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_wstrb(dmem_req_wstrb),
        .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_rdata(dmem_rsp_rdata),

        .lob_req_valid(lob_req_valid),
        .lob_req_write(lob_req_write),
        .lob_req_addr(lob_req_addr),
        .lob_req_wdata(lob_req_wdata),
        .lob_req_wstrb(lob_req_wstrb),
        .lob_rsp_valid(lob_rsp_valid),
        .lob_rsp_rdata(lob_rsp_rdata),

        .net_req_valid(),
        .net_req_write(),
        .net_req_addr(),
        .net_req_wdata(),
        .net_req_wstrb(),
        .net_rsp_valid(1'b0),
        .net_rsp_rdata(32'h0),

        .uart_req_valid(),
        .uart_req_write(),
        .uart_req_addr(),
        .uart_req_wdata(),
        .uart_req_wstrb(),
        .uart_rsp_valid(1'b0),
        .uart_rsp_rdata(32'h0),

        .sys_req_valid(),
        .sys_req_write(),
        .sys_req_addr(),
        .sys_req_wdata(),
        .sys_req_wstrb(),
        .sys_rsp_valid(1'b0),
        .sys_rsp_rdata(32'h0)
    );

    // 3. Instruction Memory Slave
    imem_slave u_imem (
        .clk(clk),
        .reset(rst_n),
        .req_valid(imem_req_valid),
        .req_write(imem_req_write),
        .req_addr(imem_req_addr),
        .req_wdata(imem_req_wdata),
        .req_wstrb(imem_req_wstrb),
        .rsp_valid(imem_rsp_valid),
        .rsp_rdata(imem_rsp_rdata)
    );

    // 4. Data Memory Slave
    dmem_slave #(
        .DELAY_CYCLES(0)
    ) u_dmem (
        .clk(clk),
        .reset(rst_n),
        .req_valid(dmem_req_valid),
        .req_write(dmem_req_write),
        .req_addr(dmem_req_addr),
        .req_wdata(dmem_req_wdata),
        .req_wstrb(dmem_req_wstrb),
        .rsp_valid(dmem_rsp_valid),
        .rsp_rdata(dmem_rsp_rdata)
    );

    // 5. LOB MMIO Slave
    lob_mmio_slave #(
        .DEFAULT_PRICE_BASE(32'd900000),
        .DEFAULT_TICK(32'd1000),
        .DEFAULT_LOCATE(16'd1)
    ) u_lob_mmio (
        .clk(clk),
        .reset(rst_n),
        .bus_req_valid(lob_req_valid),
        .bus_req_write(lob_req_write),
        .bus_req_addr(lob_req_addr),
        .bus_req_wdata(lob_req_wdata),
        .bus_req_wstrb(lob_req_wstrb),
        .bus_rsp_valid(lob_rsp_valid),
        .bus_rsp_rdata(lob_rsp_rdata),

        .cfg_clear_strobe(cfg_clear_strobe),
        .cfg_fail_stop_en(cfg_fail_stop_en),
        .cfg_price_base(cfg_price_base),
        .cfg_tick(cfg_tick),
        .cfg_stock_locate(cfg_stock_locate),
        .accel_enable(accel_enable),

        .book_valid(book_valid),
        .init_done(init_done),
        .busy(busy),
        .error_valid(error_valid),
        .error_code(error_code),
        .active_order_count(active_order_count),
        .event_done(event_done),
        .event_ready(event_ready),

        .best_bid_valid(best_bid_valid),
        .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty),
        .best_ask_valid(best_ask_valid),
        .best_ask_price(best_ask_price),
        .best_ask_qty(best_ask_qty),

        .inject_valid(),
        .inject_event_data(),
        .inject_ready(1'b1)
    );

    // 6. LOB Accelerator Core
    lob_core #(
        .DEFAULT_PRICE_BASE(32'd900000),
        .DEFAULT_TICK(32'd1000),
        .DEFAULT_FAIL_STOP_EN(1'b1)
    ) u_lob_core (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(inj_event_valid),
        .event_ready(inj_event_ready),
        .event_data(inj_event_data),

        .cfg_clear(cfg_clear_strobe),
        .cfg_fail_stop_en(cfg_fail_stop_en),
        .cfg_price_base(cfg_price_base),
        .cfg_tick(cfg_tick),

        .book_valid(book_valid),
        .init_done(init_done),
        .busy(busy),
        .error_valid(error_valid),
        .error_code(error_code),
        .active_order_count(active_order_count),
        .event_done(event_done),

        .best_bid_valid(best_bid_valid),
        .best_bid_price(best_bid_price),
        .best_bid_qty(best_bid_qty),
        .best_ask_valid(best_ask_valid),
        .best_ask_price(best_ask_price),
        .best_ask_qty(best_ask_qty)
    );

    assign event_ready = inj_event_ready;

    // Helper task to send an event synchronously into LOB
    task send_event(input canonical_event_t evt);
        wait(inj_event_ready == 1);
        @(posedge clk);
        #1;
        inj_event_valid = 1'b1;
        inj_event_data  = evt;
        @(posedge clk);
        #1;
        inj_event_valid = 1'b0;
        inj_event_data  = '0;
        wait(event_done == 1 || error_valid == 1);
        @(posedge clk);
        #1;
    endtask

    canonical_event_t evt;
    int timeout_cycles;

    initial begin
        clk = 0;
        rst_n = 0;
        inj_event_valid = 0;
        inj_event_data = '0;

        $display("===============================================================");
        $display("   STARTING CPU + MMIO + LOB ACCELERATOR INTEGRATION TEST      ");
        $display("===============================================================");

        #20 rst_n = 1;
        $display("[TB] Reset deasserted. CPU and LOB starting execution...");

        // Wait for LOB core memory zeroing initialization (16,384 cycles)
        wait(init_done == 1);
        $display("[TB] LOB Core Initialization Complete! init_done=1, book_valid=%b", book_valid);

        // Allow CPU to execute its configuration writes
        #500;

        // Verify configuration was accepted through MMIO
        $display("[TB] Current MMIO Config: PriceBase=%0d, Tick=%0d, Locate=%0d",
                 cfg_price_base, cfg_tick, cfg_stock_locate);

        // Inject Event 1: ADD Order 101 (BUY, $100.1000 -> pidx=101, 50 shares)
        $display("[TB] Injecting Canonical Event 1: ADD BUY Order 101, 50 shares, pidx=101");
        evt = '0;
        evt.ver = 4'h1;
        evt.op  = OP_ADD;
        evt.side= SIDE_BID;
        evt.oid = 64'd101;
        evt.shares = 32'd50;
        evt.pidx = 13'd101;
        evt.seq = 32'd1;
        send_event(evt);

        // Inject Event 2: ADD Order 201 (SELL, $100.1500 -> pidx=115, 30 shares)
        $display("[TB] Injecting Canonical Event 2: ADD SELL Order 201, 30 shares, pidx=115");
        evt = '0;
        evt.ver = 4'h1;
        evt.op  = OP_ADD;
        evt.side= SIDE_ASK;
        evt.oid = 64'd201;
        evt.shares = 32'd30;
        evt.pidx = 13'd115;
        evt.seq = 32'd2;
        send_event(evt);

        $display("[TB] Hardware LOB State: BestBid=$%0d (Qty %0d), BestAsk=$%0d (Qty %0d), Orders=%0d",
                 best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, active_order_count);

        // Wait for CPU to read BBO via MMIO, store into DMEM, and signal completion
        $display("[TB] Waiting for CPU bare-metal firmware to process BBO and signal PASS sentinel...");
        timeout_cycles = 0;
        while (u_dmem.DMEM.dmem[5] != 32'hCAFEBEEF && timeout_cycles < 10000) begin
            @(posedge clk);
            timeout_cycles++;
        end

        if (timeout_cycles >= 10000) begin
            $display("[FAIL] Timeout waiting for CPU firmware completion sentinel 0xCAFEBEEF!");
            $display("       DMEM[0] = %08x (snap_bid_price)", u_dmem.DMEM.dmem[0]);
            $display("       DMEM[1] = %08x (snap_bid_qty)",   u_dmem.DMEM.dmem[1]);
            $display("       DMEM[2] = %08x (snap_ask_price)", u_dmem.DMEM.dmem[2]);
            $display("       DMEM[3] = %08x (snap_ask_qty)",   u_dmem.DMEM.dmem[3]);
            $display("       DMEM[4] = %08x (order_count)",    u_dmem.DMEM.dmem[4]);
            $display("       DMEM[5] = %08x (sentinel)",       u_dmem.DMEM.dmem[5]);
            $finish(1);
        end

        $display("\n===============================================================");
        $display("   CPU + MMIO + LOB VERIFICATION RESULTS (FROM DMEM)");
        $display("===============================================================");
        $display("[VERIFY] Snap Bid Price : %0d (Expected: 1001000 = $100.1000)", u_dmem.DMEM.dmem[0]);
        $display("[VERIFY] Snap Bid Qty   : %0d (Expected: 50)",                   u_dmem.DMEM.dmem[1]);
        $display("[VERIFY] Snap Ask Price : %0d (Expected: 1015000 = $100.1500)", u_dmem.DMEM.dmem[2]);
        $display("[VERIFY] Snap Ask Qty   : %0d (Expected: 30)",                   u_dmem.DMEM.dmem[3]);
        $display("[VERIFY] Active Orders  : %0d (Expected: 2)",                    u_dmem.DMEM.dmem[4]);
        $display("[VERIFY] PASS Sentinel  : %08x (Expected: cafebeef)",            u_dmem.DMEM.dmem[5]);

        if (u_dmem.DMEM.dmem[0] == 32'd1001000 &&
            u_dmem.DMEM.dmem[1] == 32'd50      &&
            u_dmem.DMEM.dmem[2] == 32'd1015000 &&
            u_dmem.DMEM.dmem[3] == 32'd30      &&
            u_dmem.DMEM.dmem[4] == 32'd2       &&
            u_dmem.DMEM.dmem[5] == 32'hCAFEBEEF) begin
            $display("\n>>> ALL CPU + MMIO + LOB INTEGRATION CHECKS PASSED (0 ERRORS) <<<\n");
            $finish(0);
        end else begin
            $display("\n>>> MISMATCH DETECTED IN INTEGRATION TEST <<<\n");
            $finish(1);
        end
    end

endmodule
