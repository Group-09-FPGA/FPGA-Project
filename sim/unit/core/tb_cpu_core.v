`timescale 1ns / 1ps

module tb_cpu_core;

////////////////////////////////////////////////////////////
// CLOCK & RESET
////////////////////////////////////////////////////////////
reg clk;
reg reset;

// 100 MHz clock
initial begin
	clk = 0;
	forever #5 clk = ~clk;
end

// reset (active low in our CPU)
initial begin
	reset = 0;
	#100;
	reset = 1;
end


////////////////////////////////////////////////////////////
// BUS SIGNALS
////////////////////////////////////////////////////////////
    wire        bus_req_valid;
    wire        bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [ 3:0] bus_req_wstrb;
    wire        bus_rsp_valid;
    wire [31:0] bus_rsp_rdata;
    wire        bus_rsp_error;
    
    wire        imem_req_valid;
    wire        imem_req_write;
    wire [31:0] imem_req_addr;
    wire [31:0] imem_req_wdata;
    wire [ 3:0] imem_req_wstrb;
    wire        imem_rsp_valid;
    wire [31:0] imem_rsp_rdata;

    wire        dmem_req_valid;
    wire        dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [ 3:0] dmem_req_wstrb;
    wire        dmem_rsp_valid;
    wire [31:0] dmem_rsp_rdata;

    wire exception;
    wire [31:0] pc_out;
    
    // Optional delay for DMEM (can be changed to test delayed slave)
    parameter DMEM_DELAY_CYCLES = 0;


////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
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


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY SLAVE
////////////////////////////////////////////////////////////
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

////////////////////////////////////////////////////////////
// DATA MEMORY SLAVE
////////////////////////////////////////////////////////////
dmem_slave #(
    .DELAY_CYCLES(DMEM_DELAY_CYCLES)
) dmem_u (
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


////////////////////////////////////////////////////////////
// SIMULATION TIME & LOGGING
////////////////////////////////////////////////////////////
initial begin
	$dumpfile("pipeline.vcd");
	$dumpvars(0, tb_cpu_core);
	#20000;   // run long enough to see program execute
	$finish;
end










always @(posedge clk) begin
    if (reset) begin
        $display("next_pc = %08x", DUT.fetch_pc);



        if (DUT.wb_reg_write_en && DUT.wb_dest_reg_sel == 15 && !DUT.wb_stall && !DUT.stall_pipeline && !DUT.wb_mem_to_reg) begin
            $display("time:\t%10t ,result =\t%10d", $time, $signed(DUT.wb_result));
        end

        // Dynamic stop condition for ALL workloads
        if (DUT.instruction == 32'h00008067) begin
            $display("All instructions are Fetched");
            $display("next_pc = 00000000");
            #10 $finish;
        end
    end
end

endmodule
