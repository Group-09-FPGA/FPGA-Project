`timescale 1ns / 1ps

module tb_bus_error;

    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    wire bus_req_valid;
    wire bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [ 3:0] bus_req_wstrb;
    wire bus_rsp_valid;
    wire [31:0] bus_rsp_rdata;
    wire bus_rsp_error;

    wire imem_req_valid;
    wire imem_req_write;
    wire [31:0] imem_req_addr;
    wire [31:0] imem_req_wdata;
    wire [ 3:0] imem_req_wstrb;
    wire imem_rsp_valid;
    wire [31:0] imem_rsp_rdata;

    wire dmem_req_valid;
    wire dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [ 3:0] dmem_req_wstrb;
    wire dmem_rsp_valid;
    wire [31:0] dmem_rsp_rdata;

    wire exception;
    wire [31:0] pc_out;

    cpu_core DUT (
        .clk(clk),
        .reset(reset),
        .stall(1'b0),
        .exception(exception),
        .pc_out(pc_out),
        .bus_req_valid(bus_req_valid),
        .bus_req_write(bus_req_write),
        .bus_req_addr(bus_req_addr),
        .bus_req_wdata(bus_req_wdata),
        .bus_req_wstrb(bus_req_wstrb),
        .bus_rsp_valid(bus_rsp_valid),
        .bus_rsp_rdata(bus_rsp_rdata),
        .bus_rsp_error(bus_rsp_error)
    );

    sys_bus_interconnect interconnect_u (
        .clk(clk),
        .reset(reset),
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
        .dmem_rsp_rdata(dmem_rsp_rdata)
    );

    imem_slave imem_u (
        .clk(clk),
        .reset(reset),
        .req_valid(imem_req_valid),
        .req_write(imem_req_write),
        .req_addr(imem_req_addr),
        .req_wdata(imem_req_wdata),
        .req_wstrb(imem_req_wstrb),
        .rsp_valid(imem_rsp_valid),
        .rsp_rdata(imem_rsp_rdata)
    );

    dmem_slave dmem_u (
        .clk(clk),
        .reset(reset),
        .req_valid(dmem_req_valid),
        .req_write(dmem_req_write),
        .req_addr(dmem_req_addr),
        .req_wdata(dmem_req_wdata),
        .req_wstrb(dmem_req_wstrb),
        .rsp_valid(dmem_rsp_valid),
        .rsp_rdata(dmem_rsp_rdata)
    );

    reg error_detected;
    initial error_detected = 0;

    initial begin
        reset = 0;
        #100;
        reset = 1;

        // Populate instruction memory with code that accesses unmapped address 0x30000000:
        // PC 0: lui x6, 0x30000      (30000337)
        // PC 4: lw  x5, 0(x6)        (00032283)
        // PC 8: nop                  (00000013)
        imem_u.IMEM.imem[0] = 32'h30000337;
        imem_u.IMEM.imem[1] = 32'h00032283;
        imem_u.IMEM.imem[2] = 32'h00000013;

        #300;
        if (error_detected) begin
            $display("[PASS] Bus error correctly triggered and CPU asserted exception!");
        end else begin
            $display("[FAIL] Bus error not detected!");
        end
        $finish;
    end

    always @(posedge clk) begin
        if (reset) begin
            if (bus_rsp_valid && bus_rsp_error) begin
                $display("time: %10t [INTERCONNECT] bus_rsp_error received for unmapped access (addr=%08x)!", $time, bus_req_addr);
                error_detected <= 1;
            end
            if (exception) begin
                $display("time: %10t [CPU] Exception signal asserted!", $time);
            end
        end
    end

endmodule
